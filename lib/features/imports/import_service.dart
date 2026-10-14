import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'import_models.dart';

export 'import_models.dart';

const supportedAudioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'wav',
  'flac',
  'ogg',
  'opus',
  'mp4',
};
const maxImportTracks = 100;
const maxManifestBytes = 1024 * 1024;
const maxAudioBytes = 256 * 1024 * 1024;

void _debugImport(String message) {
  print('[DEBUG-7F31] $message');
}

/// Validated public HTTPS links only; this policy is also applied to redirects.
Uri validateImportUri(Uri uri) {
  final host = uri.host.toLowerCase();
  if (uri.scheme != 'https' ||
      host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const ImportException(
      'Gunakan URL HTTPS lengkap tanpa kredensial atau fragmen.',
    );
  }
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      !host.contains('.')) {
    throw const ImportException(
      'Host tautan harus berupa alamat HTTPS publik.',
    );
  }
  final ip = InternetAddress.tryParse(host);
  if (ip != null) {
    // Numeric hosts are unnecessary for supported providers and can address LANs.
    throw const ImportException('Gunakan nama domain publik, bukan alamat IP.');
  }
  if (host.length > 253 ||
      host
          .split('.')
          .any(
            (label) => !RegExp(
              r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
            ).hasMatch(label),
          )) {
    throw const ImportException('Nama host tautan tidak valid.');
  }
  return uri;
}

String audioExtension(Uri uri) {
  if (uri.pathSegments.isEmpty) return '';
  final fileName = uri.pathSegments.last.toLowerCase();
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1);
}

ImportLink parseImportLink(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null) throw const ImportException('Tautan tidak valid.');
  validateImportUri(uri);
  if (uri.host.toLowerCase() == 'open.spotify.com') {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isNotEmpty &&
        RegExp(r'^intl-[a-z]{2}$').hasMatch(segments.first))
      segments.removeAt(0);
    if (segments.length != 2 ||
        !{'track', 'playlist'}.contains(segments[0]) ||
        !RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(segments[1])) {
      throw const ImportUnsupportedException(
        'Jenis tautan Spotify ini belum didukung. Gunakan tautan track atau playlist yang lengkap.',
      );
    }
    return ImportLink(
      uri,
      segments[0] == 'track'
          ? ImportLinkKind.spotifyTrack
          : ImportLinkKind.spotifyPlaylist,
      resourceId: segments[1],
    );
  }
  final extension = audioExtension(uri);
  if ({
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
  }.contains(uri.host.toLowerCase())) {
    final segments = uri.pathSegments;
    final videoId = uri.host.toLowerCase() == 'youtu.be'
        ? (segments.length == 1 ? segments.first : null)
        : uri.path == '/watch'
        ? uri.queryParameters['v']
        : segments.length == 2 && {'shorts', 'embed'}.contains(segments.first)
        ? segments[1]
        : null;
    if (videoId != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      return ImportLink(uri, ImportLinkKind.youtubeVideo, resourceId: videoId);
    }
    final playlist = uri.queryParameters['list'];
    if (uri.path == '/playlist' &&
        playlist != null &&
        RegExp(r'^[A-Za-z0-9_-]{10,100}$').hasMatch(playlist)) {
      return ImportLink(
        uri,
        ImportLinkKind.youtubePlaylist,
        resourceId: playlist,
      );
    }
    throw const ImportUnsupportedException(
      'Gunakan tautan video atau playlist YouTube yang lengkap.',
    );
  }
  if (extension == 'json') return ImportLink(uri, ImportLinkKind.manifest);
  if (supportedAudioExtensions.contains(extension))
    return ImportLink(uri, ImportLinkKind.audio);
  throw const ImportUnsupportedException(
    'Gunakan URL langsung berkas audio (.mp3, .m4a, .aac, .wav, .flac, .ogg, .opus, .mp4) atau manifest playlist .json. Halaman web dan tautan pendek belum didukung.',
  );
}

String _requiredText(
  Map<String, dynamic> value,
  String key, {
  int maxLength = 1000,
}) {
  final text = value[key];
  if (text is! String || text.trim().isEmpty || text.length > maxLength) {
    throw ImportException('Manifest membutuhkan $key yang valid.');
  }
  return text.trim();
}

ImportPreview parsePlaylistManifest(String contents, Uri sourceUri) {
  validateImportUri(sourceUri);
  if (utf8.encode(contents).length > maxManifestBytes)
    throw const ImportException('Manifest melebihi batas 1 MiB.');
  dynamic decoded;
  try {
    decoded = jsonDecode(contents);
  } on FormatException {
    throw const ImportException('Manifest bukan JSON yang valid.');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['version'] is! int ||
      decoded['version'] != 1) {
    throw const ImportException('Manifest harus menggunakan version: 1.');
  }
  final name = _requiredText(decoded, 'name', maxLength: 200);
  final rawTracks = decoded['tracks'];
  if (rawTracks is! List ||
      rawTracks.isEmpty ||
      rawTracks.length > maxImportTracks) {
    throw const ImportException('Manifest harus berisi 1 sampai 100 lagu.');
  }
  final ids = <String>{};
  final tracks = <ImportCandidate>[];
  for (final rawTrack in rawTracks) {
    if (rawTrack is! Map<String, dynamic>)
      throw const ImportException('Entri lagu manifest tidak valid.');
    final id = _requiredText(rawTrack, 'id', maxLength: 200);
    if (!ids.add(id))
      throw const ImportException('ID lagu dalam manifest harus unik.');
    final url = Uri.tryParse(_requiredText(rawTrack, 'url', maxLength: 4096));
    if (url == null)
      throw const ImportException('URL audio manifest tidak valid.');
    validateImportUri(url);
    if (!supportedAudioExtensions.contains(audioExtension(url))) {
      throw const ImportException(
        'URL lagu manifest harus menunjuk berkas audio dengan ekstensi yang didukung.',
      );
    }
    final checksum = rawTrack['sha256'];
    if (checksum != null &&
        (checksum is! String ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(checksum))) {
      throw const ImportException(
        'Checksum sha256 manifest harus berisi 64 digit heksadesimal.',
      );
    }
    tracks.add(
      ImportCandidate(
        id: id,
        title: _requiredText(rawTrack, 'title', maxLength: 500),
        artist: _requiredText(rawTrack, 'artist', maxLength: 500),
        url: url,
        license: _requiredText(rawTrack, 'license'),
        source: _requiredText(rawTrack, 'source', maxLength: 4096),
        sha256: (checksum as String?)?.toLowerCase(),
      ),
    );
  }
  return ImportPreview(
    sourceUrl: sourceUri.toString(),
    name: name,
    tracks: tracks,
    isPlaylist: true,
  );
}

class ImportResponse {
  const ImportResponse({
    required this.statusCode,
    required this.body,
    required this.finalUri,
    this.contentType,
    this.contentLength,
    this.contentRange,
    this.allowPartialContent = false,
    this.abort,
  });
  final int statusCode;
  final Stream<List<int>> body;
  final Uri finalUri;
  final String? contentType;
  final int? contentLength;
  final String? contentRange;
  final bool allowPartialContent;
  final void Function()? abort;
}

abstract class ImportTransport {
  Future<ImportResponse> get(Uri uri);
  void close();
}

/// HttpClient uses the platform certificate verifier; no insecure TLS override.
class HttpImportTransport implements ImportTransport {
  HttpImportTransport({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }
  final HttpClient _client;

  @override
  Future<ImportResponse> get(Uri uri) async {
    var current = validateImportUri(uri);
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
        await response.listen((_) {}).cancel();
        if (redirect == 5 || location == null)
          throw const ImportException(
            'Pengalihan URL terlalu banyak atau tidak valid.',
          );
        final redirectUri = Uri.tryParse(location);
        if (redirectUri == null)
          throw const ImportException('Alamat pengalihan tidak valid.');
        current = validateImportUri(current.resolveUri(redirectUri));
        continue;
      }
      return ImportResponse(
        statusCode: response.statusCode,
        body: response.timeout(const Duration(seconds: 30)),
        finalUri: current,
        contentType: response.headers.contentType?.mimeType.toLowerCase(),
        contentLength: response.contentLength < 0
            ? null
            : response.contentLength,
        abort: () => request.abort(const ImportCancelledException()),
      );
    }
    throw const ImportException('Pengalihan URL terlalu banyak.');
  }

  @override
  void close() => _client.close(force: true);
}

typedef ValidateImportedAudio =
    Future<Map<String, dynamic>> Function(Uri fileUri);
typedef SaveImportedAudio = Future<String> Function(ImportedAudio audio);
typedef SaveImportedPlaylist =
    Future<void> Function(String id, String name, List<String> trackIds);

class ResolvedImportAudio {
  const ResolvedImportAudio({required this.response, required this.extension});
  final ImportResponse response;
  final String extension;
}

/// A serialized foreground queue. Paused work retries from byte zero explicitly.
class ImportService {
  ImportService({
    required this.hasConnection,
    required this.storageDirectory,
    required this.validateAudio,
    required this.saveLocalTrack,
    required this.savePlaylist,
    required this.loadJobs,
    required this.saveJob,
    ImportTransport? transport,
    DateTime Function()? now,
    this.metadataPreview,
    this.resolveYoutubeAudio,
    this.resolveSpotdownAudio,
  }) : _transport = transport ?? HttpImportTransport(),
       _now = now ?? DateTime.now;

  final Future<bool> Function() hasConnection;
  final Future<Directory> Function() storageDirectory;
  final ValidateImportedAudio validateAudio;
  final SaveImportedAudio saveLocalTrack;
  final SaveImportedPlaylist savePlaylist;
  final Future<List<ImportJob>> Function() loadJobs;
  final Future<void> Function(ImportJob job) saveJob;
  final ImportTransport _transport;
  final Future<ImportPreview> Function(ImportLink link)? metadataPreview;
  final Future<ResolvedImportAudio> Function(ImportCandidate candidate)?
  resolveYoutubeAudio;
  final Future<ResolvedImportAudio> Function(ImportCandidate candidate)?
  resolveSpotdownAudio;
  final DateTime Function() _now;
  final _changes = StreamController<ImportJob>.broadcast();
  final Map<String, ImportJob> _jobs = {};
  Stream<ImportJob> get changes => _changes.stream;
  List<ImportJob> get jobs => List.unmodifiable(
    _jobs.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );
  ImportJob? get activeJob => _activeJobId == null ? null : _jobs[_activeJobId];
  String? _activeJobId;
  bool _cancelled = false;
  bool _starting = false;
  bool _disposed = false;
  void Function()? _abort;
  int _sequence = 0;

  Future<void> initialize() async {
    for (var job in await loadJobs()) {
      if (job.isActive) {
        job = job.copyWith(
          status: ImportJobStatus.paused,
          updatedAt: _now(),
          error:
              'Aplikasi ditutup saat unduhan. Coba lagi untuk mengunduh ulang lagu yang belum selesai dari awal.',
          tracks: job.tracks
              .map(
                (track) =>
                    track.status == ImportTrackStatus.completed ||
                        track.status == ImportTrackStatus.failed ||
                        track.status == ImportTrackStatus.cancelled
                    ? track
                    : track.copyWith(
                        status: ImportTrackStatus.paused,
                        receivedBytes: 0,
                        clearTotalBytes: true,
                      ),
              )
              .toList(),
        );
        await saveJob(job);
      }
      _jobs[job.id] = job;
    }
  }

  Future<void> _requireConnection() async {
    if (!await hasConnection()) throw const ImportOfflineException();
  }

  Future<ImportPreview> preview(
    String input, {
    bool directDownloadPermission = false,
  }) async {
    _ensureOpen();
    final link = parseImportLink(input);
    if (link.kind == ImportLinkKind.spotifyTrack ||
        link.kind == ImportLinkKind.spotifyPlaylist) {
      if (metadataPreview == null) {
        throw const ImportUnsupportedException(
          'Provider metadata Spotify belum tersedia.',
        );
      }
      await _requireConnection();
      return metadataPreview!(link);
    }
    if (link.kind == ImportLinkKind.youtubeVideo ||
        link.kind == ImportLinkKind.youtubePlaylist) {
      if (metadataPreview == null)
        throw const ImportUnsupportedException(
          'Provider YouTube belum tersedia.',
        );
      if (!directDownloadPermission)
        throw const ImportException('Konfirmasikan izin mengunduh audio ini.');
      await _requireConnection();
      return metadataPreview!(link);
    }
    if (link.kind == ImportLinkKind.audio && !directDownloadPermission) {
      throw const ImportException(
        'Konfirmasikan bahwa Anda memiliki izin mengunduh berkas audio ini.',
      );
    }
    await _requireConnection();
    if (link.kind == ImportLinkKind.audio) {
      final fileName = link.uri.pathSegments.last;
      final title = fileName.substring(0, fileName.lastIndexOf('.'));
      return ImportPreview(
        sourceUrl: link.uri.toString(),
        name: title,
        isPlaylist: false,
        tracks: [
          ImportCandidate(
            id: sha256.convert(utf8.encode(link.uri.toString())).toString(),
            title: title.isEmpty ? 'Lagu impor' : title,
            artist: 'Artis tidak diketahui',
            url: link.uri,
            license: 'Izin unduh dikonfirmasi pengguna',
            source: link.uri.toString(),
          ),
        ],
      );
    }
    final response = await _transport.get(link.uri);
    try {
      _validateResponse(response, maxManifestBytes);
      if (!{
        'application/json',
        'text/json',
        'application/octet-stream',
      }.contains(response.contentType?.split(';').first.toLowerCase())) {
        throw const ImportException('Server tidak mengirim manifest JSON.');
      }
      final bytes = <int>[];
      await for (final chunk in response.body) {
        if (bytes.length + chunk.length > maxManifestBytes)
          throw const ImportException('Manifest melebihi batas 1 MiB.');
        bytes.addAll(chunk);
      }
      if (response.contentLength != null &&
          bytes.length != response.contentLength)
        throw const ImportException('Transfer manifest tidak lengkap.');
      try {
        return parsePlaylistManifest(utf8.decode(bytes), link.uri);
      } on FormatException {
        throw const ImportException(
          'Manifest harus menggunakan teks UTF-8 yang valid.',
        );
      }
    } finally {
      response.abort?.call();
    }
  }

  Future<ImportJob> download(
    ImportPreview preview, {
    Set<String>? selectedTrackIds,
  }) async {
    _ensureOpen();
    if (_starting || _activeJobId != null)
      throw const ImportException(
        'Tunggu unduhan aktif selesai atau batalkan dahulu.',
      );
    final candidates = preview.tracks
        .where(
          (candidate) =>
              selectedTrackIds == null ||
              selectedTrackIds.contains(candidate.id),
        )
        .toList();
    _debugImport('download requested tracks=${candidates.length}');
    if (candidates.isEmpty || candidates.length > maxImportTracks)
      throw const ImportException('Pilih 1 sampai 100 lagu untuk diunduh.');
    _validateCandidates(candidates);
    _starting = true;
    try {
      await _requireConnection();
      final now = _now();
      final id = 'import-${now.microsecondsSinceEpoch}-${_sequence++}';
      final job = ImportJob(
        id: id,
        preview: preview,
        tracks: candidates
            .map((candidate) => ImportTrackProgress(candidate: candidate))
            .toList(),
        createdAt: now,
        updatedAt: now,
        playlistId: preview.isPlaylist ? 'playlist:$id' : null,
      );
      return await _run(job);
    } finally {
      _starting = false;
    }
  }

  Future<ImportJob> retry(ImportJob previous) async {
    _ensureOpen();
    if (_starting || _activeJobId != null)
      throw const ImportException(
        'Tunggu unduhan aktif selesai atau batalkan dahulu.',
      );
    final known = _jobs[previous.id];
    if (known == null)
      throw const ImportException('Pekerjaan impor tidak ditemukan.');
    _validateCandidates(known.tracks.map((track) => track.candidate).toList());
    _starting = true;
    try {
      await _requireConnection();
      final job = known.copyWith(
        status: ImportJobStatus.queued,
        updatedAt: _now(),
        clearError: true,
        tracks: known.tracks
            .map(
              (track) => track.status == ImportTrackStatus.completed
                  ? track
                  : track.copyWith(
                      status: ImportTrackStatus.queued,
                      receivedBytes: 0,
                      clearTotalBytes: true,
                      clearError: true,
                    ),
            )
            .toList(),
      );
      return await _run(job);
    } finally {
      _starting = false;
    }
  }

  void cancel() {
    if (_activeJobId == null) return;
    _cancelled = true;
    _abort?.call();
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('ImportService is disposed.');
  }

  void _ensureNotCancelled() {
    if (_cancelled || _disposed) throw const ImportCancelledException();
  }

  void _validateCandidates(List<ImportCandidate> candidates) {
    final ids = <String>{};
    for (final candidate in candidates) {
      validateImportUri(candidate.url);
      if (candidate.provider == 'spotify') {
        throw const ImportException(
          'Pilih sumber YouTube untuk setiap lagu yang ingin diunduh.',
        );
      }
      if (candidate.provider == 'youtube') {
        final link = parseImportLink(candidate.url.toString());
        if (link.kind != ImportLinkKind.youtubeVideo ||
            resolveYoutubeAudio == null) {
          throw const ImportException('Sumber video YouTube belum tersedia.');
        }
      }
      if (candidate.provider == 'spotdown' && resolveSpotdownAudio == null) {
        throw const ImportException('Provider audio Spotdown belum tersedia.');
      }
      if (!{'direct', 'youtube', 'spotdown'}.contains(candidate.provider) ||
          !ids.add(candidate.id) ||
          candidate.id.trim().isEmpty ||
          candidate.license.trim().isEmpty ||
          candidate.source.trim().isEmpty ||
          (candidate.provider == 'direct' &&
              !supportedAudioExtensions.contains(
                audioExtension(candidate.url),
              ))) {
        throw const ImportException(
          'Lagu impor membutuhkan identitas, sumber, izin unduh, dan URL audio yang valid.',
        );
      }
      if (candidate.sha256 != null &&
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(candidate.sha256!))
        throw const ImportException('Checksum audio tidak valid.');
    }
  }

  void _emit(ImportJob job) {
    _jobs[job.id] = job;
    if (!_changes.isClosed) _changes.add(job);
  }

  Future<void> _persist(ImportJob job) async {
    _emit(job);
    await saveJob(job);
  }

  ImportJob _trackUpdate(ImportJob job, int index, ImportTrackProgress track) {
    final tracks = job.tracks.toList();
    tracks[index] = track;
    return job.copyWith(tracks: tracks, updatedAt: _now());
  }

  Future<ImportJob> _run(ImportJob job) async {
    _activeJobId = job.id;
    _cancelled = false;
    _debugImport('job started tracks=${job.tracks.length}');
    try {
      job = job.copyWith(
        status: ImportJobStatus.downloading,
        updatedAt: _now(),
      );
      await _persist(job);
      final directory = await storageDirectory();
      await directory.create(recursive: true);
      _debugImport('storage ready');
      for (var index = 0; index < job.tracks.length; index++) {
        if (job.tracks[index].status == ImportTrackStatus.completed) continue;
        if (_cancelled) break;
        final initialStatus =
            {
              'youtube',
              'spotdown',
            }.contains(job.tracks[index].candidate.provider)
            ? ImportTrackStatus.resolving
            : ImportTrackStatus.downloading;
        job = _trackUpdate(
          job,
          index,
          job.tracks[index].copyWith(
            status: initialStatus,
            receivedBytes: 0,
            clearTotalBytes: true,
            clearError: true,
          ),
        );
        await _persist(job);
        _debugImport('track index=$index state=$initialStatus');
        try {
          final audio = await _downloadAudio(job, index, directory, (track) {
            job = _trackUpdate(job, index, track);
            _emit(job);
          });
          _ensureNotCancelled();
          final localId = await saveLocalTrack(audio);
          _debugImport('track index=$index local save returned');
          if (localId.trim().isEmpty)
            throw const ImportException(
              'Penyimpanan koleksi tidak memberikan identitas lagu.',
            );
          job = _trackUpdate(
            job,
            index,
            job.tracks[index].copyWith(
              status: ImportTrackStatus.completed,
              localTrackId: localId,
              clearError: true,
            ),
          );
          await _persist(job);
          await _publishPlaylist(job);
        } on ImportCancelledException {
          job = _trackUpdate(
            job,
            index,
            job.tracks[index].copyWith(
              status: ImportTrackStatus.cancelled,
              receivedBytes: 0,
              clearTotalBytes: true,
              error: 'Unduhan dibatalkan.',
            ),
          );
          _cancelled = true;
          break;
        } on SocketException catch (_) {
          _debugImport('track index=$index socket exception');
          job = _pause(job, index);
          await _publishPlaylist(job);
          await _persist(job);
          return job;
        } on TimeoutException catch (_) {
          _debugImport('track index=$index timeout exception');
          final isYoutube = job.tracks[index].candidate.provider == 'youtube';
          job = _pause(
            job,
            index,
            error: isYoutube
                ? 'YouTube tidak mengirim data audio dalam 30 detik. Coba lagi atau ganti sumber YouTube.'
                : 'Sumber audio tidak mengirim data dalam 30 detik. Coba lagi.',
          );
          await _publishPlaylist(job);
          await _persist(job);
          return job;
        } catch (error) {
          _debugImport('track index=$index failed type=${error.runtimeType}');
          if (_cancelled) {
            job = _trackUpdate(
              job,
              index,
              job.tracks[index].copyWith(
                status: ImportTrackStatus.cancelled,
                receivedBytes: 0,
                clearTotalBytes: true,
                error: 'Unduhan dibatalkan.',
              ),
            );
            break;
          }
          // Collection files remain complete even if later playlist persistence fails.
          if (job.tracks[index].status == ImportTrackStatus.completed) {
            job = job.copyWith(
              error:
                  'Lagu tersimpan, tetapi playlist belum tersimpan: ${_errorMessage(error)}',
            );
          } else {
            job = _trackUpdate(
              job,
              index,
              job.tracks[index].copyWith(
                status: ImportTrackStatus.failed,
                receivedBytes: 0,
                clearTotalBytes: true,
                error: _errorMessage(error),
              ),
            );
          }
          await _persist(job);
        }
      }
      if (_cancelled) {
        job = job.copyWith(
          status: ImportJobStatus.cancelled,
          tracks: job.tracks
              .map(
                (track) => track.status == ImportTrackStatus.queued
                    ? track.copyWith(
                        status: ImportTrackStatus.cancelled,
                        error: 'Unduhan dibatalkan.',
                      )
                    : track,
              )
              .toList(),
        );
      } else {
        try {
          await _publishPlaylist(job);
        } catch (error) {
          job = job.copyWith(
            error:
                'Lagu tersimpan, tetapi playlist belum tersimpan: ${_errorMessage(error)}',
          );
        }
        final completed = job.completedCount;
        job = job.copyWith(
          status: completed == job.totalCount && job.error == null
              ? ImportJobStatus.completed
              : completed > 0
              ? ImportJobStatus.partial
              : ImportJobStatus.failed,
        );
      }
      if (_cancelled) await _publishPlaylist(job);
      job = job.copyWith(updatedAt: _now());
      await _persist(job);
      _debugImport(
        'job finished state=${job.status} completed=${job.completedCount}/${job.totalCount}',
      );
      return job;
    } catch (error) {
      _debugImport('job failed type=${error.runtimeType}');
      job = job.copyWith(
        status: ImportJobStatus.failed,
        error: _errorMessage(error),
        updatedAt: _now(),
      );
      // A persistence error is surfaced to the caller rather than claiming success.
      _emit(job);
      rethrow;
    } finally {
      _abort = null;
      _activeJobId = null;
    }
  }

  ImportJob _pause(ImportJob job, int index, {String? error}) => job.copyWith(
    status: ImportJobStatus.paused,
    updatedAt: _now(),
    error:
        error ??
        'Koneksi ke sumber terputus. Periksa jaringan atau coba lagi; internet perangkat belum tentu dapat menjangkau layanan audio.',
    tracks: job.tracks
        .asMap()
        .entries
        .map(
          (entry) =>
              entry.key >= index &&
                  entry.value.status != ImportTrackStatus.completed &&
                  entry.value.status != ImportTrackStatus.failed
              ? entry.value.copyWith(
                  status: ImportTrackStatus.paused,
                  receivedBytes: 0,
                  clearTotalBytes: true,
                )
              : entry.value,
        )
        .toList(),
  );

  Future<void> _publishPlaylist(ImportJob job) async {
    if (!job.preview.isPlaylist || job.playlistId == null) return;
    // Unknown IDs retain the selected snapshot's order and honest offline ratio;
    // the collection only resolves and plays IDs backed by complete local files.
    if (job.completedCount == 0) return;
    final ids = job.tracks
        .map(
          (track) =>
              track.localTrackId ??
              'pending:${job.id}:${Uri.encodeComponent(track.candidate.id)}',
        )
        .toList();
    await savePlaylist(job.playlistId!, job.preview.name, ids);
  }

  Future<ImportedAudio> _downloadAudio(
    ImportJob job,
    int index,
    Directory directory,
    void Function(ImportTrackProgress) update,
  ) async {
    final candidate = job.tracks[index].candidate;
    ResolvedImportAudio? resolved;
    if (candidate.provider == 'youtube') {
      _debugImport('track index=$index resolving YouTube audio');
      resolved = await resolveYoutubeAudio!(candidate);
      _debugImport('track index=$index YouTube resolver returned');
      try {
        _ensureNotCancelled();
      } catch (_) {
        resolved.response.abort?.call();
        rethrow;
      }
    } else if (candidate.provider == 'spotdown') {
      _debugImport('track index=$index resolving Spotdown audio');
      resolved = await resolveSpotdownAudio!(candidate);
      _debugImport('track index=$index Spotdown resolver returned');
      try {
        _ensureNotCancelled();
      } catch (_) {
        resolved.response.abort?.call();
        rethrow;
      }
    }
    final response = resolved?.response ?? await _transport.get(candidate.url);
    _debugImport(
      'track index=$index response status=${response.statusCode} bytes=${response.contentLength ?? -1} type=${response.contentType ?? 'unknown'}',
    );
    _abort = response.abort;
    final temp = File('${directory.path}/${job.id}-$index.part');
    IOSink? fileSink;
    try {
      _ensureNotCancelled();
      _validateResponse(response, maxAudioBytes);
      final type = response.contentType?.split(';').first.toLowerCase();
      final extension = resolved?.extension ?? audioExtension(candidate.url);
      if (resolved != null && !supportedAudioExtensions.contains(extension))
        throw const ImportException(
          'Container audio hasil resolver tidak didukung.',
        );
      const audioTypes = {
        'audio/mpeg',
        'audio/mp3',
        'audio/mp4',
        'audio/x-m4a',
        'audio/aac',
        'audio/aacp',
        'audio/wav',
        'audio/x-wav',
        'audio/wave',
        'audio/vnd.wave',
        'audio/flac',
        'audio/x-flac',
        'audio/ogg',
        'audio/opus',
        'application/ogg',
        'audio/webm',
      };
      if (!audioTypes.contains(type) &&
          !(type == 'application/octet-stream' &&
              supportedAudioExtensions.contains(extension))) {
        throw const ImportException(
          'Server tidak mengirim tipe audio yang didukung.',
        );
      }
      if (response.contentLength == 0)
        throw const ImportException('Berkas audio kosong.');
      if (response.statusCode == 206) {
        final match = RegExp(
          r'^bytes\s+(\d+)-(\d+)/(\d+)$',
          caseSensitive: false,
        ).firstMatch(response.contentRange?.trim() ?? '');
        final start = int.tryParse(match?.group(1) ?? '');
        final end = int.tryParse(match?.group(2) ?? '');
        final total = int.tryParse(match?.group(3) ?? '');
        if (start != 0 ||
            end == null ||
            total == null ||
            end + 1 != total ||
            response.contentLength != total) {
          throw const ImportException(
            'YouTube hanya mengirim sebagian audio. Coba lagi untuk mengambil stream lengkap.',
          );
        }
      }
      var progress = job.tracks[index].copyWith(
        status: ImportTrackStatus.downloading,
        totalBytes: response.contentLength,
      );
      update(progress);
      var count = 0;
      var lastUpdate = _now();
      final hashOutput = _DigestOutput();
      final hashInput = sha256.startChunkedConversion(hashOutput);
      fileSink = temp.openWrite(mode: FileMode.writeOnly);
      _debugImport('track index=$index listening for audio bytes');
      var lastLoggedBytes = 0;
      final chunks = response.body
          .map((chunk) {
            _ensureNotCancelled();
            count += chunk.length;
            if (lastLoggedBytes == 0 ||
                count - lastLoggedBytes >= 2 * 1024 * 1024) {
              _debugImport('track index=$index received bytes=$count');
              lastLoggedBytes = count;
            }
            if (count > maxAudioBytes)
              throw const ImportException(
                'Berkas audio melebihi batas 256 MiB.',
              );
            if (response.contentLength != null &&
                count > response.contentLength!)
              throw const ImportException(
                'Ukuran audio berbeda dari ukuran yang diberikan server.',
              );
            hashInput.add(chunk);
            if (_now().difference(lastUpdate).inMilliseconds >= 150) {
              progress = progress.copyWith(receivedBytes: count);
              update(progress);
              lastUpdate = _now();
            }
            return chunk;
          })
          .timeout(
            const Duration(seconds: 30),
            onTimeout: (sink) {
              _debugImport(
                'track index=$index idle timeout; closing audio stream',
              );
              sink.addError(
                TimeoutException('Audio stream was idle for 30 seconds.'),
              );
              sink.close();
              response.abort?.call();
            },
          );
      await for (final chunk in chunks) {
        fileSink.add(chunk);
      }
      await fileSink.flush();
      await fileSink.close();
      fileSink = null;
      hashInput.close();
      _ensureNotCancelled();
      if (count == 0 ||
          (response.contentLength != null && count != response.contentLength))
        throw const ImportException('Transfer audio tidak lengkap.');
      _debugImport('track index=$index stream complete bytes=$count');
      final digest = hashOutput.value!.toString();
      if (candidate.sha256 != null && digest != candidate.sha256!.toLowerCase())
        throw const ImportException(
          'Checksum audio tidak cocok dengan manifest.',
        );
      progress = progress.copyWith(
        status: ImportTrackStatus.verifying,
        receivedBytes: count,
      );
      update(progress);
      await saveJob(_jobs[job.id]!);
      _debugImport('track index=$index validating audio');
      final metadata = await validateAudio(temp.uri);
      _debugImport('track index=$index audio validation returned');
      _ensureNotCancelled();
      if (metadata['isValid'] == false || metadata['valid'] == false)
        throw const ImportException(
          'Decoder tidak dapat membaca berkas audio ini.',
        );
      final rawDuration = metadata['durationMs'];
      if (rawDuration is! num || rawDuration <= 0)
        throw const ImportException(
          'Berkas audio tidak memiliki durasi valid dari decoder.',
        );
      final finalFile = File('${directory.path}/$digest.$extension');
      // Android rename atomically replaces an earlier copy of the same content.
      // Always publish the bytes just hashed and validated, even after a retry.
      await temp.rename(finalFile.path);
      if (!await finalFile.exists())
        throw const ImportException('Berkas audio belum tersimpan.');
      _debugImport('track index=$index file published bytes=$count');
      return ImportedAudio(
        candidate: candidate,
        fileUri: finalFile.uri,
        durationMs: rawDuration.toInt(),
        sha256: digest,
        bytes: count,
      );
    } finally {
      _debugImport('track index=$index response cleanup');
      _abort = null;
      response.abort?.call();
      if (fileSink != null) {
        try {
          await fileSink.close();
        } catch (_) {
          /* Retain the original error. */
        }
      }
      if (await temp.exists()) await temp.delete();
    }
  }

  void _validateResponse(ImportResponse response, int maxBytes) {
    validateImportUri(response.finalUri);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (response.statusCode == 206 && !response.allowPartialContent)) {
      final code = response.statusCode;
      throw ImportException(
        code == 401 || code == 403
            ? 'Sumber menolak akses (HTTP $code). Periksa izin sumber.'
            : code == 404 || code == 410
            ? 'Berkas sumber tidak tersedia lagi (HTTP $code).'
            : code == 429
            ? 'Batas permintaan sumber tercapai. Coba lagi nanti.'
            : 'Sumber mengembalikan HTTP $code.',
      );
    }
    if (response.contentLength != null &&
        (response.contentLength! < 0 || response.contentLength! > maxBytes)) {
      throw ImportException(
        maxBytes == maxAudioBytes
            ? 'Berkas audio melebihi batas 256 MiB.'
            : 'Manifest melebihi batas 1 MiB.',
      );
    }
  }

  String _errorMessage(Object error) {
    if (error is ImportException) return error.message;
    if (error is FileSystemException)
      return 'Berkas tidak dapat disimpan. Periksa ruang penyimpanan dan izin aplikasi.';
    if (error is HandshakeException)
      return 'Sertifikat TLS sumber tidak dapat diverifikasi.';
    if (error is HttpException)
      return 'Transfer HTTP tidak lengkap atau tidak valid.';
    return 'Impor gagal: $error';
  }

  Future<void> dispose() async {
    _disposed = true;
    cancel();
    _transport.close();
    await _changes.close();
  }
}

class _DigestOutput implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
