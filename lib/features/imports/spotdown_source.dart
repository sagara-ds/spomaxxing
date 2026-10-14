import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'import_service.dart';

typedef SpotdownJsonRequest =
    Future<Map<String, dynamic>> Function(
      String method,
      Uri uri,
      Map<String, dynamic>? body,
    );

class SpotdownAuthenticationRequired extends ImportException {
  const SpotdownAuthenticationRequired()
    : super(
        'Autentikasi Spotdown diperlukan. Selesaikan pemeriksaan keamanan, lalu coba lagi.',
      );
}

class SpotdownServerException extends ImportException {
  const SpotdownServerException()
    : super('Spotdown sedang gagal memproses lagu ini.');
}

class SpotdownSession {
  String? _token;
  DateTime? _expiresAt;

  bool get isValid =>
      _token != null &&
      _expiresAt != null &&
      _expiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 3)));

  String get token {
    if (!isValid) throw const SpotdownAuthenticationRequired();
    return _token!;
  }

  void updateFromStorage(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ImportException('Sesi Spotdown tidak valid.');
    }
    if (decoded is! Map)
      throw const ImportException('Sesi Spotdown tidak valid.');
    final token = decoded['token'];
    final expires = decoded['expires'];
    if (token is! String || token.isEmpty || expires is! num) {
      throw const ImportException('Sesi Spotdown tidak lengkap.');
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(expires.toInt());
    if (!expiry.isAfter(DateTime.now().add(const Duration(minutes: 3)))) {
      throw const SpotdownAuthenticationRequired();
    }
    _token = token;
    _expiresAt = expiry;
  }

  void invalidate() {
    _token = null;
    _expiresAt = null;
  }
}

class SpotdownSource {
  SpotdownSource({
    SpotdownSession? session,
    HttpClient? client,
    SpotdownJsonRequest? jsonRequest,
  }) : session = session ?? SpotdownSession(),
       _client = client ?? HttpClient(),
       _jsonRequestOverride = jsonRequest {
    _client.connectionTimeout = const Duration(seconds: 20);
  }

  static final Uri authenticationUri = Uri.parse(
    'https://spotdown.org/en2/track',
  );
  final SpotdownSession session;
  final HttpClient _client;
  final SpotdownJsonRequest? _jsonRequestOverride;

  Future<ImportPreview> preview(ImportLink link) async {
    if (link.kind != ImportLinkKind.spotifyTrack &&
        link.kind != ImportLinkKind.spotifyPlaylist) {
      throw const ImportException(
        'Spotdown hanya digunakan untuk sumber Spotify.',
      );
    }
    final payload = await _jsonRequest(
      'GET',
      Uri.https('spotdown.org', '/apinew/song-details', {
        'url': link.uri.toString(),
      }),
    );
    if (payload['success'] == false) {
      throw ImportException(
        _text(payload['message']).isEmpty
            ? 'Spotdown tidak menemukan audio untuk tautan ini.'
            : _text(payload['message']),
      );
    }
    final rawSongs = payload['songs'];
    if (rawSongs is! List ||
        rawSongs.isEmpty ||
        rawSongs.length > maxImportTracks) {
      throw const ImportException(
        'Spotdown tidak mengembalikan 1 sampai 100 lagu.',
      );
    }
    final occurrences = <String, int>{};
    final tracks = <ImportCandidate>[];
    for (final raw in rawSongs) {
      if (raw is! Map)
        throw const ImportException('Format lagu Spotdown berubah.');
      final song = Map<String, dynamic>.from(raw);
      final title = _text(song['title']);
      final artist = _text(song['artist']);
      final sourceUrl = Uri.tryParse(_text(song['url']));
      if (title.isEmpty || artist.isEmpty || sourceUrl == null) {
        throw const ImportException('Metadata lagu Spotdown tidak lengkap.');
      }
      validateImportUri(sourceUrl);
      final digest = sha256
          .convert(utf8.encode(sourceUrl.toString()))
          .toString();
      final occurrence = occurrences.update(
        digest,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      tracks.add(
        ImportCandidate(
          id: 'spotdown:$digest:$occurrence',
          title: title,
          artist: artist,
          url: sourceUrl,
          provider: 'spotdown',
          license: 'Izin unduh dikonfirmasi pengguna',
          source: '${link.uri}\nAudio: Spotdown',
        ),
      );
    }
    final contentType = _text(payload['contentType']);
    return ImportPreview(
      sourceUrl: link.uri.toString(),
      name: tracks.length == 1
          ? tracks.first.title
          : contentType.isEmpty
          ? 'Impor Spotify'
          : 'Spotify ${contentType[0].toUpperCase()}${contentType.substring(1)}',
      tracks: tracks,
      isPlaylist:
          tracks.length > 1 || link.kind == ImportLinkKind.spotifyPlaylist,
    );
  }

  Future<ResolvedImportAudio> resolve(ImportCandidate candidate) async {
    if (candidate.provider != 'spotdown') {
      throw const ImportException('Sumber Spotdown tidak valid.');
    }
    final payload = await _jsonRequest(
      'POST',
      Uri.https('spotdown.org', '/apinew/download'),
      body: {'url': candidate.url.toString()},
    );
    final downloadUri = Uri.tryParse(_text(payload['downloadUrl']));
    if (downloadUri == null) {
      throw const ImportException('Spotdown tidak memberikan tautan unduhan.');
    }
    var current = validateImportUri(downloadUri);
    for (var redirect = 0; redirect <= 5; redirect++) {
      final request = await _client
          .getUrl(current)
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (redirect == 5 || location == null) {
          throw const ImportException('Pengalihan audio Spotdown tidak valid.');
        }
        final target = Uri.tryParse(location);
        if (target == null)
          throw const ImportException('Alamat audio Spotdown tidak valid.');
        current = validateImportUri(current.resolveUri(target));
        continue;
      }
      return ResolvedImportAudio(
        extension: _audioExtension(
          current,
          response.headers.contentType?.mimeType,
        ),
        response: ImportResponse(
          statusCode: response.statusCode,
          body: response.timeout(const Duration(seconds: 30)),
          finalUri: current,
          contentType: response.headers.contentType?.mimeType.toLowerCase(),
          contentLength: response.contentLength < 0
              ? null
              : response.contentLength,
          abort: () => request.abort(const ImportCancelledException()),
        ),
      );
    }
    throw const ImportException('Pengalihan audio Spotdown terlalu banyak.');
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _jsonRequestOnce(method, uri, body: body);
      } on SpotdownServerException {
        if (method != 'POST' || attempt >= 3) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<Map<String, dynamic>> _jsonRequestOnce(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final override = _jsonRequestOverride;
    if (override != null) return override(method, uri, body);
    final request = method == 'POST'
        ? await _client.postUrl(uri).timeout(const Duration(seconds: 30))
        : await _client.getUrl(uri).timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('X-Session-Token', session.token);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > maxManifestBytes) {
        throw const ImportException('Respons Spotdown terlalu besar.');
      }
      bytes.addAll(chunk);
    }
    if (response.statusCode == 403) {
      session.invalidate();
      throw const SpotdownAuthenticationRequired();
    }
    if (response.statusCode == 429) {
      throw const ImportException(
        'Batas Spotdown tercapai. Coba lagi setelah satu jam.',
      );
    }
    if (response.statusCode == 500) {
      throw const SpotdownServerException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImportException(
        'Spotdown mengembalikan HTTP ${response.statusCode}.',
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const ImportException('Format respons Spotdown berubah.');
    }
  }

  String _audioExtension(Uri uri, String? contentType) {
    final extension = audioExtension(uri);
    if (supportedAudioExtensions.contains(extension)) return extension;
    return switch (contentType?.toLowerCase()) {
      'audio/mp4' || 'audio/x-m4a' => 'm4a',
      'audio/webm' => 'webm',
      _ => 'mp3',
    };
  }

  String _text(Object? value) => value is String ? value.trim() : '';

  void close() => _client.close(force: true);
}
