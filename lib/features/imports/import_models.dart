enum ImportLinkKind { audio, manifest, spotifyTrack, spotifyPlaylist, youtubeVideo, youtubePlaylist }

enum ImportTrackStatus {
  queued,
  downloading,
  verifying,
  completed,
  failed,
  paused,
  cancelled,
}

enum ImportJobStatus { queued, downloading, completed, partial, failed, paused, cancelled }

class ImportLink {
  const ImportLink(this.uri, this.kind, {this.resourceId});
  final Uri uri;
  final ImportLinkKind kind;
  final String? resourceId;
}

class ImportCandidate {
  const ImportCandidate({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    required this.license,
    required this.source,
    this.sha256,
    this.provider = 'direct',
    this.durationMs = 0,
  });

  final String id;
  final String title;
  final String artist;
  final Uri url;
  final String license;
  final String source;
  final String? sha256;
  final String provider;
  final int durationMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'url': url.toString(),
    'license': license,
    'source': source,
    'provider': provider,
    'durationMs': durationMs,
    if (sha256 != null) 'sha256': sha256,
  };

  factory ImportCandidate.fromJson(Map<String, dynamic> json) => ImportCandidate(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    url: Uri.parse(json['url'] as String),
    license: json['license'] as String,
    source: json['source'] as String,
    sha256: json['sha256'] as String?,
    provider: json['provider'] as String? ?? 'direct',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
  );
}

class ImportPreview {
  ImportPreview({
    required this.sourceUrl,
    required this.name,
    required List<ImportCandidate> tracks,
    required this.isPlaylist,
  }) : tracks = List.unmodifiable(tracks);

  final String sourceUrl;
  final String name;
  final List<ImportCandidate> tracks;
  final bool isPlaylist;

  Map<String, dynamic> toJson() => {
    'sourceUrl': sourceUrl,
    'name': name,
    'isPlaylist': isPlaylist,
    'tracks': tracks.map((track) => track.toJson()).toList(),
  };

  factory ImportPreview.fromJson(Map<String, dynamic> json) => ImportPreview(
    sourceUrl: json['sourceUrl'] as String,
    name: json['name'] as String,
    isPlaylist: json['isPlaylist'] as bool,
    tracks: (json['tracks'] as List).map((track) => ImportCandidate.fromJson(Map<String, dynamic>.from(track as Map))).toList(),
  );
}

/// A complete, decoder-validated file, supplied to the collection adapter.
class ImportedAudio {
  const ImportedAudio({
    required this.candidate,
    required this.fileUri,
    required this.durationMs,
    required this.sha256,
    required this.bytes,
  });
  final ImportCandidate candidate;
  final Uri fileUri;
  final int durationMs;
  final String sha256;
  final int bytes;
}

class ImportTrackProgress {
  const ImportTrackProgress({
    required this.candidate,
    this.status = ImportTrackStatus.queued,
    this.receivedBytes = 0,
    this.totalBytes,
    this.localTrackId,
    this.error,
  });

  final ImportCandidate candidate;
  final ImportTrackStatus status;
  final int receivedBytes;
  final int? totalBytes;
  final String? localTrackId;
  final String? error;

  ImportTrackProgress copyWith({
    ImportTrackStatus? status,
    int? receivedBytes,
    int? totalBytes,
    String? localTrackId,
    String? error,
    bool clearError = false,
    bool clearTotalBytes = false,
  }) => ImportTrackProgress(
    candidate: candidate,
    status: status ?? this.status,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: clearTotalBytes ? null : totalBytes ?? this.totalBytes,
    localTrackId: localTrackId ?? this.localTrackId,
    error: clearError ? null : error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'candidate': candidate.toJson(),
    'status': status.name,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'localTrackId': localTrackId,
    'error': error,
  };

  factory ImportTrackProgress.fromJson(Map<String, dynamic> json) => ImportTrackProgress(
    candidate: ImportCandidate.fromJson(Map<String, dynamic>.from(json['candidate'] as Map)),
    status: ImportTrackStatus.values.byName(json['status'] as String),
    receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (json['totalBytes'] as num?)?.toInt(),
    localTrackId: json['localTrackId'] as String?,
    error: json['error'] as String?,
  );
}

class ImportJob {
  ImportJob({
    required this.id,
    required this.preview,
    required List<ImportTrackProgress> tracks,
    required this.createdAt,
    required this.updatedAt,
    this.status = ImportJobStatus.queued,
    this.playlistId,
    this.error,
  }) : tracks = List.unmodifiable(tracks);

  final String id;
  final ImportPreview preview;
  final List<ImportTrackProgress> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ImportJobStatus status;
  final String? playlistId;
  final String? error;
  int get completedCount => tracks.where((track) => track.status == ImportTrackStatus.completed).length;
  int get totalCount => tracks.length;
  bool get isActive => status == ImportJobStatus.queued || status == ImportJobStatus.downloading;

  ImportJob copyWith({
    List<ImportTrackProgress>? tracks,
    DateTime? updatedAt,
    ImportJobStatus? status,
    String? playlistId,
    String? error,
    bool clearError = false,
  }) => ImportJob(
    id: id,
    preview: preview,
    tracks: tracks ?? this.tracks,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    playlistId: playlistId ?? this.playlistId,
    error: clearError ? null : error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'preview': preview.toJson(),
    'tracks': tracks.map((track) => track.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'playlistId': playlistId,
    'error': error,
  };

  factory ImportJob.fromJson(Map<String, dynamic> json) => ImportJob(
    id: json['id'] as String,
    preview: ImportPreview.fromJson(Map<String, dynamic>.from(json['preview'] as Map)),
    tracks: (json['tracks'] as List).map((track) => ImportTrackProgress.fromJson(Map<String, dynamic>.from(track as Map))).toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    status: ImportJobStatus.values.byName(json['status'] as String),
    playlistId: json['playlistId'] as String?,
    error: json['error'] as String?,
  );
}

class ImportException implements Exception {
  const ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportOfflineException extends ImportException {
  const ImportOfflineException() : super('Tidak ada koneksi internet. Hubungkan ke internet untuk mengunduh lagu. Lagu yang sudah tersimpan tetap bisa diputar.');
}

class ImportCancelledException extends ImportException {
  const ImportCancelledException() : super('Unduhan dibatalkan.');
}

class ImportUnsupportedException extends ImportException {
  const ImportUnsupportedException(super.message);
}
