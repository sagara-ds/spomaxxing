import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spomaxxing/core/models/track.dart';
import 'package:spomaxxing/data/library_repository.dart';

Track mediaTrack(int id, {String? title, Set<String> tags = const {},
    bool favorite = false}) => Track(
  id: Track.mediaStoreId('external', id),
  uri: 'content://media/external/audio/media/$id',
  title: title ?? 'Lagu $id',
  artist: 'Artis $id',
  album: 'Album $id',
  durationMs: 120000,
  tags: tags,
  isFavorite: favorite,
);

Track importedTrack(String id) => Track(
  id: Track.importId(id),
  uri: 'file:///data/user/0/dev.spomaxxing/files/$id.flac',
  title: 'Audio impor $id',
);

void main() {
  sqfliteFfiInit();
  late Database database;
  late LibraryRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repository = await LibraryRepository.open(database: database);
  });

  tearDown(() async {
    await repository.close();
  });

  test('stores full metadata and normalizes tags without losing edits', () async {
    final track = mediaTrack(1, tags: {' Fokus ', 'SANTAI'}, favorite: true)
        .copyWith(genre: 'Instrumental', artworkUri: 'file:///art/1.jpg');
    await repository.saveTrack(track);
    expect((await repository.loadTracks()).single.toJson(), track.toJson());

    final tagged = await repository.updateTags(track.id, {'Tidur', ' tidur ', ''});
    expect(tagged!.tags, {'tidur'});
    expect(tagged.isFavorite, isTrue);
    final unfavorited = await repository.toggleFavorite(track.id);
    expect(unfavorited!.isFavorite, isFalse);
    expect(unfavorited.tags, {'tidur'});
    expect(await repository.updateTags('unknown', {'fokus'}), isNull);
    expect(await repository.toggleFavorite('unknown'), isNull);
  });

  test('completed rescan retains edits and imports while marking lost files',
      () async {
    final kept = mediaTrack(1, tags: {'fokus'}, favorite: true);
    final missing = mediaTrack(2, tags: {'tidur'});
    final imported = importedTrack('own-recording');
    await repository.saveTracks([kept, missing, imported]);

    await repository.reconcileMediaStore([
      mediaTrack(1, title: 'Metadata baru'),
      mediaTrack(3),
    ]);
    final tracks = {
      for (final track in await repository.loadTracks()) track.id: track,
    };
    expect(tracks[kept.id]!.title, 'Metadata baru');
    expect(tracks[kept.id]!.tags, {'fokus'});
    expect(tracks[kept.id]!.isFavorite, isTrue);
    expect(tracks[missing.id]!.isAvailable, isFalse);
    expect(tracks[missing.id]!.tags, {'tidur'});
    expect(tracks[imported.id]!.isAvailable, isTrue);
    expect((await repository.loadTracks(availableOnly: true)).length, 3);

    await repository.reconcileMediaStore([]);
    expect((await repository.loadTracks(availableOnly: true)).single.id,
        imported.id);
  });

  test('failed rescan rolls back missing flags and metadata changes', () async {
    final existing = mediaTrack(1, title: 'Judul awal');
    final rejected = mediaTrack(3);
    await repository.saveTrack(existing);
    await database.execute('''
      CREATE TRIGGER reject_scan_track BEFORE INSERT ON tracks
      WHEN NEW.id = '${rejected.id}'
      BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END
    ''');
    await expectLater(
      repository.reconcileMediaStore([
        mediaTrack(1, title: 'Perubahan belum selesai'), rejected,
      ]),
      throwsA(isA<DatabaseException>()),
    );
    final recovered = (await repository.loadTracks()).single;
    expect(recovered.toJson(), existing.toJson());
  });

  test('rejects imported identities in a scan before changing library', () async {
    final existing = mediaTrack(1);
    await repository.saveTrack(existing);
    await expectLater(
      repository.reconcileMediaStore([importedTrack('not-a-scan')]),
      throwsArgumentError,
    );
    expect((await repository.loadTracks()).single.isAvailable, isTrue);
  });

  test('searches local title, artist and album with literal punctuation',
      () async {
    await repository.saveTracks([
      mediaTrack(1, title: 'Seratus 100%'),
      mediaTrack(2).copyWith(artist: 'Orkestra Senja'),
      mediaTrack(3).copyWith(album: 'MALAM_BIRU', isAvailable: false),
      mediaTrack(4, title: 'ÉTUDE'),
    ]);
    expect((await repository.loadTracks(query: '%')).single.id,
        mediaTrack(1).id);
    expect((await repository.loadTracks(query: ' SENJA ')).single.id,
        mediaTrack(2).id);
    expect((await repository.loadTracks(query: 'malam_')).single.id,
        mediaTrack(3).id);
    expect(await repository.loadTracks(query: 'malam_', availableOnly: true),
        isEmpty);
    expect((await repository.loadTracks(query: 'étude')).single.id,
        mediaTrack(4).id);
  });

  test('playlist order, repeated and unresolved IDs survive edits', () async {
    final created = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final playlist = LocalPlaylist(
      id: 'mix-1', name: 'Fokus',
      trackIds: ['unresolved:remote', mediaTrack(1).id, mediaTrack(1).id],
      createdAt: created,
    );
    await repository.savePlaylist(playlist);
    expect((await repository.loadPlaylists()).single.toJson(), playlist.toJson());
    final changed = playlist.copyWith(
      name: 'Fokus malam', trackIds: [mediaTrack(2).id, 'unresolved:remote'],
      updatedAt: created.add(const Duration(days: 1)),
    );
    await repository.savePlaylist(changed);
    expect((await repository.loadPlaylists()).single.toJson(), changed.toJson());
    await repository.deletePlaylist(playlist.id);
    expect(await repository.loadPlaylists(), isEmpty);
    expect(await database.query('playlist_entries'), isEmpty);
  });

  test('snapshot and resumable jobs preserve nested JSON and replacement',
      () async {
    expect(await repository.loadPlayerSnapshot(), isNull);
    final snapshot = <String, dynamic>{
      'queue': ['media:external:1', 'import:abc'],
      'currentIndex': 1,
      'positionMs': 4312,
      'shuffle': true,
      'repeat': 'all',
      'history': [0],
    };
    await repository.savePlayerSnapshot(snapshot);
    expect(await repository.loadPlayerSnapshot(), snapshot);
    final payload = <String, dynamic>{
      'status': 'paused',
      'tracks': [
        {'referenceId': 'remote:1', 'status': 'complete', 'bytes': 4096},
        {'referenceId': 'remote:2', 'status': 'waiting', 'error': null},
      ],
      'source': {'url': 'https://example.org/owned-audio.flac'},
    };
    await repository.saveImportJob('job-1', payload);
    expect((await repository.loadImportJobs()).single,
        {...payload, 'id': 'job-1'});
    await repository.saveImportJob('job-1', {...payload, 'status': 'running'});
    expect((await repository.loadImportJobs()).single['status'], 'running');
    await repository.deleteImportJob('job-1');
    expect(await repository.loadImportJobs(), isEmpty);

    await expectLater(repository.savePlayerSnapshot({'bad': Object()}),
        throwsA(isA<JsonUnsupportedObjectError>()));
    expect(await repository.loadPlayerSnapshot(), snapshot);
  });

  test('publishing import is atomic across track, playlist and job', () async {
    final oldPlaylist = LocalPlaylist(
      id: 'playlist', name: 'Awal', trackIds: ['unresolved:1'],
    );
    await repository.savePlaylist(oldPlaylist);
    await database.execute('''
      CREATE TRIGGER reject_import_job BEFORE INSERT ON import_jobs
      WHEN NEW.id = 'failed-job'
      BEGIN SELECT RAISE(ABORT, 'simulated job failure'); END
    ''');
    final track = importedTrack('verified');
    await expectLater(repository.saveImportResult(
      track: track,
      jobId: 'failed-job',
      job: {'status': 'complete'},
      playlist: oldPlaylist.copyWith(trackIds: [track.id]),
    ), throwsA(isA<DatabaseException>()));
    expect(await repository.loadTracks(), isEmpty);
    expect((await repository.loadPlaylists()).single.toJson(),
        oldPlaylist.toJson());
    expect(await repository.loadImportJobs(), isEmpty);

    await repository.saveImportResult(
      track: track,
      jobId: 'good-job',
      job: {'status': 'complete'},
      playlist: oldPlaylist.copyWith(trackIds: [track.id]),
    );
    expect((await repository.loadTracks()).single.id, track.id);
    expect((await repository.loadPlaylists()).single.trackIds, [track.id]);
    expect((await repository.loadImportJobs()).single['status'], 'complete');
  });

  test('reopening disk database restores library, playlist and player', () async {
    final directory = await Directory.systemTemp.createTemp('spomaxxing-db-');
    final location = path.join(directory.path, 'library.db');
    try {
      var diskRepository = await LibraryRepository.open(
        factory: databaseFactoryFfi, databasePath: location,
      );
      final track = mediaTrack(1, tags: {'santai'}, favorite: true);
      final playlist = LocalPlaylist(id: 'saved', name: 'Mix', trackIds: [track.id]);
      final snapshot = <String, dynamic>{'queue': [track.id], 'positionMs': 1500};
      await diskRepository.saveTrack(track);
      await diskRepository.savePlaylist(playlist);
      await diskRepository.savePlayerSnapshot(snapshot);
      await diskRepository.saveImportJob('waiting', {'status': 'paused'});
      await diskRepository.close();
      diskRepository = await LibraryRepository.open(
        factory: databaseFactoryFfi, databasePath: location,
      );
      try {
        expect((await diskRepository.loadTracks()).single.toJson(), track.toJson());
        expect((await diskRepository.loadPlaylists()).single.toJson(),
            playlist.toJson());
        expect(await diskRepository.loadPlayerSnapshot(), snapshot);
        expect((await diskRepository.loadImportJobs()).single['status'], 'paused');
      } finally {
        await diskRepository.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
