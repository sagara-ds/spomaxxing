import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../core/models/track.dart';

/// An ordered local playlist. Unknown track IDs are retained for partial imports.
class LocalPlaylist {
  factory LocalPlaylist({
    required String id,
    required String name,
    required List<String> trackIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'A playlist identity is required.');
    }
    if (trackIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(trackIds, 'trackIds', 'Track IDs cannot be empty.');
    }
    final created = createdAt ?? DateTime.now();
    return LocalPlaylist._(
      id: id,
      name: name.trim().isEmpty ? 'Playlist baru' : name.trim(),
      trackIds: List.unmodifiable(trackIds),
      createdAt: created,
      updatedAt: updatedAt ?? created,
    );
  }

  const LocalPlaylist._({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  LocalPlaylist copyWith({
    String? name,
    List<String>? trackIds,
    DateTime? updatedAt,
  }) => LocalPlaylist(
    id: id,
    name: name ?? this.name,
    trackIds: trackIds ?? this.trackIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trackIds': trackIds,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) => LocalPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    trackIds: (json['trackIds'] as List<dynamic>).cast<String>(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num).toInt(),
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['updatedAt'] as num).toInt(),
    ),
  );
}

/// Local metadata only: searching and restoring data never use the network.
class LibraryRepository {
  LibraryRepository._(this._database);

  static const schemaVersion = 1;
  final Database _database;

  /// Inject a database or factory to exercise the real schema without Android.
  static Future<LibraryRepository> open({
    Database? database,
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    if (database != null) {
      final version = await database.getVersion();
      if (version > schemaVersion) {
        throw StateError('The library was created by a newer app version.');
      }
      await database.execute('PRAGMA foreign_keys = ON');
      if (version == 0) {
        await database.transaction((transaction) async {
          await _createSchema(transaction);
          await transaction.execute('PRAGMA user_version = $schemaVersion');
        });
      }
      return LibraryRepository._(database);
    }

    final selectedFactory = factory ?? databaseFactory;
    final location = databasePath ??
        path.join(await selectedFactory.getDatabasesPath(), 'spomaxxing.db');
    final opened = await selectedFactory.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _createSchema(db),
      ),
    );
    return LibraryRepository._(opened);
  }

  static Future<void> _createSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE tracks (
        id TEXT PRIMARY KEY,
        uri TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        search_title TEXT NOT NULL,
        search_artist TEXT NOT NULL,
        search_album TEXT NOT NULL,
        duration_ms INTEGER NOT NULL CHECK (duration_ms >= 0),
        genre TEXT,
        artwork_uri TEXT,
        tags_json TEXT NOT NULL,
        is_favorite INTEGER NOT NULL CHECK (is_favorite IN (0, 1)),
        is_available INTEGER NOT NULL CHECK (is_available IN (0, 1)),
        source TEXT NOT NULL CHECK (source IN ('media', 'import'))
      )
    ''');
    await database.execute(
      'CREATE INDEX tracks_availability ON tracks(is_available, title)',
    );
    await database.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE playlist_entries (
        playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        position INTEGER NOT NULL CHECK (position >= 0),
        track_id TEXT NOT NULL,
        PRIMARY KEY (playlist_id, position)
      )
    ''');
    // Entries deliberately do not reference tracks: unresolved imports survive.
    await database.execute('''
      CREATE TABLE player_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        snapshot_json TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE import_jobs (
        id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> close() => _database.close();

  /// Search treats '%' and '_' as ordinary text rather than SQL wildcards.
  Future<List<Track>> loadTracks({
    String query = '',
    bool availableOnly = false,
  }) async {
    final conditions = <String>[];
    final arguments = <Object?>[];
    final search = query.trim().toLowerCase();
    if (search.isNotEmpty) {
      conditions.add('''
        (instr(search_title, ?) > 0 OR
         instr(search_artist, ?) > 0 OR
         instr(search_album, ?) > 0)
      ''');
      arguments.addAll([search, search, search]);
    }
    if (availableOnly) conditions.add('is_available = 1');
    final rows = await _database.query(
      'tracks',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments,
      orderBy: 'title COLLATE NOCASE, id',
    );
    return rows.map(_trackFromRow).toList(growable: false);
  }

  Future<void> saveTrack(Track track) async {
    await _saveTrack(_database, track);
  }

  Future<void> saveTracks(Iterable<Track> tracks) async {
    await _database.transaction((transaction) async {
      for (final track in tracks) {
        await _saveTrack(transaction, track);
      }
    });
  }

  Future<Track?> updateTags(String id, Set<String> tags) =>
      _database.transaction((transaction) async {
        final track = await _loadTrack(transaction, id);
        if (track == null) return null;
        final updated = track.copyWith(tags: tags);
        await _saveTrack(transaction, updated);
        return updated;
      });

  Future<Track?> toggleFavorite(String id) =>
      _database.transaction((transaction) async {
        final track = await _loadTrack(transaction, id);
        if (track == null) return null;
        final updated = track.copyWith(isFavorite: !track.isFavorite);
        await _saveTrack(transaction, updated);
        return updated;
      });

  Future<void> setAvailability(String id, bool available) async {
    await _database.update(
      'tracks',
      {'is_available': available ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Apply only a completed, permission-authorized full MediaStore scan.
  /// Missing files stay visible as unavailable; imports and user edits survive.
  Future<void> reconcileMediaStore(Iterable<Track> scannedTracks) async {
    final tracks = scannedTracks.toList(growable: false);
    if (tracks.any((track) => !track.id.startsWith('media:'))) {
      throw ArgumentError('A MediaStore scan must contain MediaStore identities.');
    }
    await _database.transaction((transaction) async {
      await transaction.update(
        'tracks',
        {'is_available': 0},
        where: 'source = ?',
        whereArgs: ['media'],
      );
      for (final track in tracks) {
        final previous = await _loadTrack(transaction, track.id);
        await _saveTrack(
          transaction,
          track.copyWith(
            isAvailable: true,
            tags: previous?.tags ?? track.tags,
            isFavorite: previous?.isFavorite ?? track.isFavorite,
          ),
        );
      }
    });
  }

  Future<void> savePlaylist(LocalPlaylist playlist) =>
      _database.transaction((transaction) => _savePlaylist(transaction, playlist));

  Future<List<LocalPlaylist>> loadPlaylists() async {
    // One read transaction prevents entries from belonging to a newer revision.
    return _database.transaction((transaction) async {
      final playlists = await transaction.query(
        'playlists',
        orderBy: 'updated_at DESC, id',
      );
      final entries = await transaction.query(
        'playlist_entries',
        orderBy: 'playlist_id, position',
      );
      final ids = <String, List<String>>{};
      for (final entry in entries) {
        ids.putIfAbsent(entry['playlist_id'] as String, () => [])
            .add(entry['track_id'] as String);
      }
      return playlists.map((row) => LocalPlaylist(
        id: row['id'] as String,
        name: row['name'] as String,
        trackIds: ids[row['id']] ?? [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      )).toList(growable: false);
    });
  }

  Future<void> deletePlaylist(String id) async {
    await _database.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> savePlayerSnapshot(Map<String, dynamic> snapshot) async {
    final encoded = jsonEncode(snapshot);
    await _database.insert(
      'player_state',
      {'id': 1, 'snapshot_json': encoded},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadPlayerSnapshot() async {
    final rows = await _database.query('player_state', where: 'id = 1');
    if (rows.isEmpty) return null;
    return _decodeObject(rows.single['snapshot_json'] as String);
  }

  Future<void> saveImportJob(String id, Map<String, dynamic> payload) async {
    _validateJobId(id);
    final encoded = jsonEncode({...payload, 'id': id});
    await _database.transaction((transaction) =>
        _saveImportJob(transaction, id, encoded));
  }

  Future<List<Map<String, dynamic>>> loadImportJobs() async {
    final rows = await _database.query(
      'import_jobs',
      orderBy: 'created_at, id',
    );
    return rows.map((row) => {
      ..._decodeObject(row['payload_json'] as String),
      'id': row['id'] as String,
    }).toList(growable: false);
  }

  Future<void> deleteImportJob(String id) async {
    await _database.delete('import_jobs', where: 'id = ?', whereArgs: [id]);
  }

  /// Publish validated audio and its job/playlist references in one transaction.
  Future<void> saveImportResult({
    required Track track,
    required String jobId,
    required Map<String, dynamic> job,
    LocalPlaylist? playlist,
  }) async {
    _validateJobId(jobId);
    final encoded = jsonEncode({...job, 'id': jobId});
    await _database.transaction((transaction) async {
      await _saveTrack(transaction, track);
      if (playlist != null) await _savePlaylist(transaction, playlist);
      await _saveImportJob(transaction, jobId, encoded);
    });
  }

  static void _validateJobId(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'An import job identity is required.');
    }
  }

  static Future<void> _saveImportJob(
    DatabaseExecutor database,
    String id,
    String encoded,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = await database.update(
      'import_jobs',
      {'payload_json': encoded, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) {
      await database.insert('import_jobs', {
        'id': id,
        'payload_json': encoded,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  static Future<void> _savePlaylist(
    DatabaseExecutor database,
    LocalPlaylist playlist,
  ) async {
    final updated = await database.update(
      'playlists',
      {
        'name': playlist.name,
        'updated_at': playlist.updatedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
    if (updated == 0) {
      await database.insert('playlists', {
        'id': playlist.id,
        'name': playlist.name,
        'created_at': playlist.createdAt.millisecondsSinceEpoch,
        'updated_at': playlist.updatedAt.millisecondsSinceEpoch,
      });
    }
    await database.delete(
      'playlist_entries',
      where: 'playlist_id = ?',
      whereArgs: [playlist.id],
    );
    final batch = database.batch();
    for (var position = 0; position < playlist.trackIds.length; position++) {
      batch.insert('playlist_entries', {
        'playlist_id': playlist.id,
        'position': position,
        'track_id': playlist.trackIds[position],
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<Track?> _loadTrack(DatabaseExecutor database, String id) async {
    final rows = await database.query('tracks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _trackFromRow(rows.single);
  }

  static Future<void> _saveTrack(DatabaseExecutor database, Track track) async {
    await database.insert('tracks', {
      'id': track.id,
      'uri': track.uri,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      // SQLite lower() only folds ASCII; Dart also handles accented metadata.
      'search_title': track.title.toLowerCase(),
      'search_artist': track.artist.toLowerCase(),
      'search_album': track.album.toLowerCase(),
      'duration_ms': track.durationMs,
      'genre': track.genre,
      'artwork_uri': track.artworkUri,
      'tags_json': jsonEncode(track.tags.toList()..sort()),
      'is_favorite': track.isFavorite ? 1 : 0,
      'is_available': track.isAvailable ? 1 : 0,
      'source': track.id.startsWith('media:') ? 'media' : 'import',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Track _trackFromRow(Map<String, Object?> row) => Track(
    id: row['id'] as String,
    uri: row['uri'] as String,
    title: row['title'] as String,
    artist: row['artist'] as String,
    album: row['album'] as String,
    durationMs: row['duration_ms'] as int,
    genre: row['genre'] as String?,
    artworkUri: row['artwork_uri'] as String?,
    tags: (jsonDecode(row['tags_json'] as String) as List<dynamic>)
        .cast<String>().toSet(),
    isFavorite: row['is_favorite'] == 1,
    isAvailable: row['is_available'] == 1,
  );

  static Map<String, dynamic> _decodeObject(String encoded) =>
      Map<String, dynamic>.from(jsonDecode(encoded) as Map);
}
