/// A locally stored audio file. Identity is independent of its display metadata.
class Track {
  factory Track({
    required String id,
    required String uri,
    required String title,
    String artist = 'Artis tidak diketahui',
    String album = '',
    int durationMs = 0,
    String? genre,
    String? artworkUri,
    Set<String> tags = const {},
    bool isFavorite = false,
    bool isAvailable = true,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'A stable identity is required.');
    }
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !{'content', 'file'}.contains(parsed.scheme)) {
      throw ArgumentError.value(uri, 'uri', 'Audio must use a local URI.');
    }
    if (durationMs < 0) {
      throw ArgumentError.value(durationMs, 'durationMs', 'Must be nonnegative.');
    }
    final fallback = parsed.pathSegments.isEmpty
        ? 'Lagu tanpa judul'
        : parsed.pathSegments.last;
    return Track._(
      id: id,
      uri: uri,
      title: title.trim().isEmpty ? fallback : title.trim(),
      artist: artist.trim().isEmpty ? 'Artis tidak diketahui' : artist.trim(),
      album: album.trim(),
      durationMs: durationMs,
      genre: genre,
      artworkUri: artworkUri,
      tags: Set.unmodifiable(
        tags.map((tag) => tag.trim().toLowerCase()).where((tag) => tag.isNotEmpty),
      ),
      isFavorite: isFavorite,
      isAvailable: isAvailable,
    );
  }

  const Track._({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.genre,
    required this.artworkUri,
    required this.tags,
    required this.isFavorite,
    required this.isAvailable,
  });

  final String id;
  final String uri;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String? genre;
  final String? artworkUri;
  final Set<String> tags;
  final bool isFavorite;
  final bool isAvailable;

  Uri get audioUri => Uri.parse(uri);
  Duration get duration => Duration(milliseconds: durationMs);

  static String mediaStoreId(String volume, int mediaId) {
    if (volume.isEmpty || mediaId < 0) {
      throw ArgumentError('MediaStore identity requires a volume and valid ID.');
    }
    return 'media:${Uri.encodeComponent(volume)}:$mediaId';
  }

  static String importId(String identifier) {
    if (identifier.trim().isEmpty) {
      throw ArgumentError.value(identifier, 'identifier', 'Cannot be empty.');
    }
    return 'import:${Uri.encodeComponent(identifier)}';
  }

  Track copyWith({
    String? uri,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? genre,
    String? artworkUri,
    Set<String>? tags,
    bool? isFavorite,
    bool? isAvailable,
    bool clearGenre = false,
    bool clearArtwork = false,
  }) => Track(
    id: id,
    uri: uri ?? this.uri,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    durationMs: durationMs ?? this.durationMs,
    genre: clearGenre ? null : genre ?? this.genre,
    artworkUri: clearArtwork ? null : artworkUri ?? this.artworkUri,
    tags: tags ?? this.tags,
    isFavorite: isFavorite ?? this.isFavorite,
    isAvailable: isAvailable ?? this.isAvailable,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'uri': uri,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMs,
    'genre': genre,
    'artworkUri': artworkUri,
    'tags': tags.toList()..sort(),
    'isFavorite': isFavorite,
    'isAvailable': isAvailable,
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    uri: json['uri'] as String,
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    album: json['album'] as String? ?? '',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    genre: json['genre'] as String?,
    artworkUri: json['artworkUri'] as String?,
    tags: (json['tags'] as List<dynamic>? ?? []).cast<String>().toSet(),
    isFavorite: json['isFavorite'] as bool? ?? false,
    isAvailable: json['isAvailable'] as bool? ?? true,
  );
}
