import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'import_service.dart';

void _debugYoutubeImport(String message) {
  print('[DEBUG-7F31] $message');
}

class YoutubeResult {
  const YoutubeResult({
    required this.id,
    required this.title,
    required this.channel,
    required this.durationMs,
  });
  final String id;
  final String title;
  final String channel;
  final int durationMs;
  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': id});

  ImportCandidate forTrack(ImportCandidate original) => ImportCandidate(
    id: original.id,
    title: original.title,
    artist: original.artist,
    durationMs: original.durationMs,
    url: url,
    provider: 'youtube',
    license: 'Izin unduh dikonfirmasi pengguna',
    source: '${original.source}\nYouTube: $title — $channel\n$url',
  );
}

/// Public embed metadata only. This is an experimental HTML contract, not OAuth.
ImportPreview parseSpotifyEmbed(String html, ImportLink link) {
  if (utf8.encode(html).length > 4 * 1024 * 1024) {
    throw const ImportException('Halaman metadata Spotify terlalu besar.');
  }
  final script = RegExp(
    r'<script\b[^>]*\bid\s*=\s*["\x27]__NEXT_DATA__["\x27][^>]*>([\s\S]*?)</script>',
    caseSensitive: false,
  ).firstMatch(html);
  if (script == null) {
    throw const ImportException(
      'Spotify tidak menyediakan daftar lagu yang dapat dibaca. Playlist privat/radio personal atau perubahan halaman dapat menyebabkan ini.',
    );
  }
  dynamic value;
  try {
    value = jsonDecode(script.group(1)!);
  } on FormatException {
    throw const ImportException('Metadata Spotify tidak valid.');
  }
  for (final key in ['props', 'pageProps', 'state', 'data', 'entity']) {
    if (value is! Map)
      throw const ImportException(
        'Format metadata Spotify berubah atau playlist tidak tersedia.',
      );
    value = value[key];
  }
  if (value is! Map)
    throw const ImportException(
      'Lagu/playlist Spotify tidak tersedia melalui halaman publik.',
    );
  final entity = Map<String, dynamic>.from(value);
  String text(Object? raw) => raw is String ? raw.trim() : '';
  final isPlaylist = link.kind == ImportLinkKind.spotifyPlaylist;
  final rawTracks = isPlaylist ? entity['trackList'] : [entity];
  if (rawTracks is! List ||
      rawTracks.isEmpty ||
      rawTracks.length > maxImportTracks) {
    throw const ImportException(
      'Daftar Spotify tidak tersedia atau melebihi 100 lagu. Tidak ada playlist kosong yang disimpan.',
    );
  }
  final candidates = <ImportCandidate>[];
  final occurrences = <String, int>{};
  for (final raw in rawTracks) {
    if (raw is! Map)
      throw const ImportException('Metadata lagu Spotify tidak lengkap.');
    final title = text(raw['title']).isNotEmpty
        ? text(raw['title'])
        : text(raw['name']);
    var artist = text(raw['subtitle']);
    final artists = raw['artists'];
    if (artist.isEmpty && artists is List) {
      artist = artists
          .whereType<Map>()
          .map((a) => text(a['name']))
          .where((a) => a.isNotEmpty)
          .join(', ');
    }
    if (title.isEmpty || artist.isEmpty)
      throw const ImportException(
        'Judul/artis Spotify tidak lengkap; audio tidak dicocokkan otomatis.',
      );
    final spotifyUri = text(raw['uri']);
    final id = spotifyUri.split(':').last;
    if (!RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id))
      throw const ImportException('Identitas lagu Spotify tidak tersedia.');
    final occurrence = occurrences.update(
      id,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    final duration = raw['duration'] ?? raw['durationMs'];
    candidates.add(
      ImportCandidate(
        id: 'spotify:$id:$occurrence',
        title: title,
        artist: artist,
        durationMs: duration is num ? duration.toInt() : 0,
        url: Uri.https('open.spotify.com', '/track/$id'),
        provider: 'spotify',
        license: 'Pilih sumber YouTube dan konfirmasikan izin unduh',
        source: Uri.https(
          'open.spotify.com',
          '/${isPlaylist ? 'playlist' : 'track'}/${link.resourceId}',
        ).toString(),
      ),
    );
  }
  final name = text(entity['name']).isNotEmpty
      ? text(entity['name'])
      : text(entity['title']);
  return ImportPreview(
    sourceUrl: link.uri.toString(),
    name: name.isEmpty ? candidates.first.title : name,
    tracks: candidates,
    isPlaylist: isPlaylist,
  );
}

/// Resolves metadata/search and fresh streams only when the user requests them.
/// No YouTube credentials, external server, Python, or FFmpeg are bundled.
class YoutubeSource {
  Future<List<YoutubeResult>> search(String query) async {
    if (query.trim().isEmpty || query.length > 500)
      throw const ImportException(
        'Masukkan judul dan artis untuk pencarian YouTube.',
      );
    final client = yt.YoutubeExplode();
    try {
      final results = await client.search
          .search(query.trim())
          .timeout(const Duration(seconds: 30));
      return results
          .where((video) => video.isLive != true && video.duration != null)
          .take(10)
          .map(_result)
          .toList();
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      throw const ImportException(
        'Pencarian YouTube gagal. Layanan mungkin membatasi akses; coba lagi nanti.',
      );
    } finally {
      client.close();
    }
  }

  YoutubeResult _result(yt.Video video) => YoutubeResult(
    id: video.id.value,
    title: video.title,
    channel: video.author,
    durationMs: video.duration?.inMilliseconds ?? 0,
  );

  Future<ImportPreview> preview(ImportLink link) async {
    if (link.kind == ImportLinkKind.spotifyTrack ||
        link.kind == ImportLinkKind.spotifyPlaylist) {
      final transport = HttpImportTransport();
      ImportResponse? response;
      try {
        response = await transport.get(
          Uri.https(
            'open.spotify.com',
            '/embed/${link.kind == ImportLinkKind.spotifyTrack ? 'track' : 'playlist'}/${link.resourceId}',
          ),
        );
        if (response.statusCode != 200)
          throw ImportException(
            'Spotify menolak metadata (HTTP ${response.statusCode}). Playlist mungkin tidak tersedia untuk publik.',
          );
        if (response.contentLength != null &&
            response.contentLength! > 4 * 1024 * 1024)
          throw const ImportException('Metadata Spotify terlalu besar.');
        final bytes = <int>[];
        await for (final chunk in response.body) {
          if (bytes.length + chunk.length > 4 * 1024 * 1024)
            throw const ImportException('Metadata Spotify terlalu besar.');
          bytes.addAll(chunk);
        }
        return parseSpotifyEmbed(utf8.decode(bytes), link);
      } finally {
        response?.abort?.call();
        transport.close();
      }
    }
    final client = yt.YoutubeExplode();
    try {
      final videos = <yt.Video>[];
      String name;
      if (link.kind == ImportLinkKind.youtubePlaylist) {
        final playlist = await client.playlists
            .get(link.resourceId)
            .timeout(const Duration(seconds: 30));
        name = playlist.title;
        videos.addAll(
          await client.playlists
              .getVideos(link.resourceId)
              .take(101)
              .timeout(const Duration(seconds: 30))
              .toList(),
        );
      } else {
        final video = await client.videos
            .get(link.resourceId)
            .timeout(const Duration(seconds: 30));
        name = video.title;
        videos.add(video);
      }
      if (videos.isEmpty || videos.length > maxImportTracks)
        throw const ImportException(
          'Playlist YouTube harus berisi 1 sampai 100 video.',
        );
      if (videos.any((video) => video.isLive == true))
        throw const ImportException(
          'Siaran langsung tidak didukung untuk unduhan offline.',
        );
      return ImportPreview(
        sourceUrl: link.uri.toString(),
        name: name,
        isPlaylist: link.kind == ImportLinkKind.youtubePlaylist,
        tracks: videos.asMap().entries.map((entry) {
          final video = _result(entry.value);
          return ImportCandidate(
            id: 'youtube:${video.id}:${entry.key}',
            title: video.title,
            artist: video.channel,
            durationMs: video.durationMs,
            url: video.url,
            provider: 'youtube',
            license: 'Izin unduh dikonfirmasi pengguna',
            source: video.url.toString(),
          );
        }).toList(),
      );
    } on ImportException {
      rethrow;
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      throw const ImportException(
        'Metadata YouTube tidak tersedia. Video/playlist privat atau dibatasi belum didukung.',
      );
    } finally {
      client.close();
    }
  }

  Future<ResolvedImportAudio> resolve(ImportCandidate candidate) async {
    _debugYoutubeImport('resolver started');
    final link = parseImportLink(candidate.url.toString());
    if (link.kind != ImportLinkKind.youtubeVideo)
      throw const ImportException('Sumber YouTube tidak valid.');
    final client = yt.YoutubeExplode();
    try {
      _debugYoutubeImport('requesting YouTube stream manifest');
      yt.StreamManifest? manifest;
      Object? manifestError;
      // Mobile clients expose direct formats without the watch-page
      // JavaScript challenges that cannot be solved in this app.
      for (final entry in <(String, yt.YoutubeApiClient)>[
        ('ios', yt.YoutubeApiClient.ios),
        ('androidVr', yt.YoutubeApiClient.androidVr),
        ('tv', yt.YoutubeApiClient.tv),
      ]) {
        try {
          manifest = await client.videos.streams
              .getManifest(
                link.resourceId,
                ytClients: [entry.$2],
                requireWatchPage: false,
              )
              .timeout(const Duration(seconds: 20));
          _debugYoutubeImport('manifest client=${entry.$1} succeeded');
          break;
        } catch (error) {
          manifestError = error;
          _debugYoutubeImport(
            'manifest client=${entry.$1} failed type=${error.runtimeType} details=$error',
          );
        }
      }
      if (manifest == null) throw manifestError!;
      _debugYoutubeImport(
        'manifest returned audioStreams=${manifest.audioOnly.length}',
      );
      final supported = manifest.audioOnly
          .where(
            (stream) =>
                {'mp4', 'webm'}.contains(stream.container.name) &&
                stream.size.totalBytes > 0 &&
                stream.size.totalBytes <= maxAudioBytes,
          )
          .toList();
      if (supported.isEmpty)
        throw const ImportException(
          'YouTube tidak menyediakan audio yang didukung dalam batas 256 MiB.',
        );
      final m4a = supported
          .where((stream) => stream.container.name == 'mp4')
          .toList();
      final selected = (m4a.isNotEmpty ? m4a : supported).withHighestBitrate();
      validateImportUri(selected.url);
      if (!selected.url.host.endsWith('.googlevideo.com'))
        throw const ImportException('Host audio YouTube tidak dikenali.');
      final extension = selected.container.name == 'mp4' ? 'm4a' : 'webm';
      _debugYoutubeImport(
        'selected audio container=$extension bytes=${selected.size.totalBytes}',
      );
      // The package's stream helper suppresses HTTP body stream errors. Request
      // this already-resolved, short-lived URL directly so HTTP status/errors
      // propagate to the import job instead of leaving it waiting for bytes.
      final downloadClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      try {
        final end = selected.size.totalBytes - 1;
        final usesRangeHeader = selected.url.queryParameters['c'] == 'ANDROID';
        final requestUri = usesRangeHeader
            ? selected.url
            : selected.url.replace(
                queryParameters: {
                  ...selected.url.queryParameters,
                  'range': '0-$end',
                },
              );
        final request = await downloadClient
            .getUrl(requestUri)
            .timeout(const Duration(seconds: 30));
        request.followRedirects = true;
        request.maxRedirects = 5;
        for (final header in yt.YoutubeHttpClient.defaultHeaders.entries) {
          request.headers.set(header.key, header.value);
        }
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (usesRangeHeader) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-$end');
        }
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        final finalUri = response.redirects.isEmpty
            ? requestUri
            : response.redirects.last.location;
        validateImportUri(finalUri);
        final contentRange = response.headers.value(
          HttpHeaders.contentRangeHeader,
        );
        final contentLength = response.contentLength < 0
            ? selected.size.totalBytes
            : response.contentLength;
        _debugYoutubeImport(
          'audio response status=${response.statusCode} bytes=$contentLength type=${response.headers.contentType?.mimeType ?? 'unknown'} range=${contentRange ?? 'none'}',
        );
        if (response.statusCode == 403) {
          downloadClient.close(force: true);
          client.close();
          throw const ImportException(
            'YouTube menolak permintaan stream audio (HTTP 403). Coba lagi nanti atau ganti sumber.',
          );
        }
        if (response.statusCode == 429) {
          downloadClient.close(force: true);
          client.close();
          throw const ImportException(
            'YouTube membatasi permintaan audio. Tunggu sebentar, lalu coba lagi.',
          );
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          downloadClient.close(force: true);
          client.close();
          throw ImportException(
            'YouTube mengembalikan HTTP ${response.statusCode} saat mengirim audio.',
          );
        }
        final isCompleteRange =
            response.statusCode == 206 &&
            contentRange == 'bytes 0-$end/${selected.size.totalBytes}' &&
            contentLength == selected.size.totalBytes;
        return ResolvedImportAudio(
          extension: extension,
          response: ImportResponse(
            statusCode: response.statusCode,
            body: response,
            finalUri: finalUri,
            contentType:
                response.headers.contentType?.mimeType.toLowerCase() ??
                (extension == 'm4a' ? 'audio/mp4' : 'audio/webm'),
            contentLength: contentLength,
            contentRange: contentRange,
            allowPartialContent: isCompleteRange,
            abort: () {
              downloadClient.close(force: true);
              client.close();
            },
          ),
        );
      } on TimeoutException {
        downloadClient.close(force: true);
        client.close();
        rethrow;
      } catch (_) {
        downloadClient.close(force: true);
        rethrow;
      }
    } on ImportException {
      client.close();
      rethrow;
    } on SocketException {
      client.close();
      rethrow;
    } on TimeoutException {
      client.close();
      throw const ImportException(
        'Waktu tunggu saat mencari stream YouTube habis. Layanan audio mungkin lambat atau membatasi permintaan; coba lagi atau ganti sumber.',
      );
    } catch (error) {
      _debugYoutubeImport(
        'resolver failed type=${error.runtimeType} details=$error',
      );
      client.close();
      throw ImportException(_safeExtractionError(error));
    }
  }

  String _safeExtractionError(Object error) {
    final details = error.toString().toLowerCase();
    if (RegExp(r'\b403\b|forbidden').hasMatch(details)) {
      return 'YouTube menolak permintaan ekstraksi audio (HTTP 403). Coba lagi nanti atau ganti sumber.';
    }
    if (RegExp(r'\b429\b|too many requests|rate.?limit').hasMatch(details)) {
      return 'YouTube membatasi terlalu banyak permintaan. Tunggu sebentar, lalu coba lagi.';
    }
    if (details.contains('private') ||
        details.contains('unavailable') ||
        details.contains('age')) {
      return 'Video tidak tersedia untuk ekstraksi audio. Coba sumber lain yang dapat diputar publik.';
    }
    if (details.contains('signature') ||
        details.contains('player') ||
        details.contains('cipher')) {
      return 'Format ekstraksi YouTube berubah dan extractor aplikasi belum dapat membacanya. Coba perbarui aplikasi atau ganti sumber.';
    }
    return 'Ekstraksi audio YouTube gagal (${error.runtimeType}). Coba lagi atau ganti sumber.';
  }
}
