import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/models/track.dart';
import '../core/radio/radio_mixer.dart';
import '../data/library_repository.dart';
import '../data/platform_library.dart';
import '../features/imports/import_service.dart';
import '../features/player/player_controller.dart';

/// Coordinates local data; the only network path is an explicit import action.
class AppController extends ChangeNotifier {
  AppController({required this.repository, required this.platform,
    required this.player, required this.importer});

  final LibraryRepository repository;
  final PlatformLibrary platform;
  final PlayerController player;
  final ImportService importer;
  List<Track> tracks = [];
  List<LocalPlaylist> playlists = [];
  bool busy = false;
  String? error;
  StreamSubscription<ImportJob>? _imports;

  static Future<ImportService> createImporter(
    LibraryRepository repository, PlatformLibrary platform,
  ) async => ImportService(
    hasConnection: platform.hasConnection,
    storageDirectory: () async => Directory(path.join(
      (await getApplicationSupportDirectory()).path, 'imports')),
    validateAudio: (uri) => platform.validateAudio(uri.toString()),
    saveLocalTrack: (audio) async {
      final id = 'import:download:${audio.sha256}';
      final previous = (await repository.loadTracks())
          .where((track) => track.id == id).firstOrNull;
      await repository.saveTrack(Track(id: id,
        uri: audio.fileUri.toString(), title: audio.candidate.title,
        artist: audio.candidate.artist, durationMs: audio.durationMs,
        tags: previous?.tags ?? {}, isFavorite: previous?.isFavorite ?? false));
      return id;
    },
    savePlaylist: (id, name, ids) async {
      final previous = (await repository.loadPlaylists())
          .where((playlist) => playlist.id == id).firstOrNull;
      await repository.savePlaylist(LocalPlaylist(id: id, name: name,
        trackIds: ids, createdAt: previous?.createdAt));
    },
    loadJobs: () async => (await repository.loadImportJobs())
        .map(ImportJob.fromJson).toList(),
    saveJob: (job) => repository.saveImportJob(job.id, job.toJson()),
  );

  Future<void> init() async {
    await reload();
    // Private files can be checked without prompting for broad audio access.
    for (final track in tracks.where((track) => track.audioUri.scheme == 'file')) {
      final exists = await File.fromUri(track.audioUri).exists();
      if (exists != track.isAvailable) {
        await repository.setAvailability(track.id, exists);
      }
    }
    await reload();
    final saved = await repository.loadPlayerSnapshot();
    if (saved != null) await player.restoreSnapshot(saved, tracks);
    await importer.initialize();
    var completed = importer.jobs.fold<int>(0, (sum, job) => sum + job.completedCount);
    _imports = importer.changes.listen((job) {
      notifyListeners();
      final count = importer.jobs.fold<int>(0, (sum, job) => sum + job.completedCount);
      if (count == completed && job.isActive) return;
      completed = count;
      // Reload publishes only fully validated local files, never .part files.
      unawaited(reload().catchError((Object exception) {
        error = exception.toString();
        notifyListeners();
      }));
    });
  }

  Future<void> reload() async {
    tracks = (await repository.loadTracks())
        .where((track) => !track.id.startsWith('media:')).toList();
    playlists = await repository.loadPlaylists();
    notifyListeners();
  }

  Future<void> _work(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try { await action(); }
    catch (exception) {
      error = exception is PlatformException
          ? exception.message ?? 'Audio belum dapat diakses. Coba lagi.'
          : 'Koleksi belum dapat diperbarui. Coba lagi.';
    }
    finally { busy = false; notifyListeners(); }
  }

  Future<void> pickAudio() => _work(() async {
    final result = await platform.pickAudio();
    await repository.saveTracks(result.tracks);
    await reload();
    if (result.errors.isNotEmpty) error = result.errors.join('\n');
  });

  Future<void> toggleFavorite(Track track) async {
    await repository.toggleFavorite(track.id);
    await reload();
  }

  Future<void> setTags(Iterable<Track> selected, Set<String> tags) async {
    final normalized = tags.map(MoodCatalog.normalize).toSet();
    for (final track in selected) {
      await repository.updateTags(track.id, normalized);
    }
    await reload();
  }

  Future<void> playTracks(Iterable<Track> source,
      {int startIndex = 0, bool shuffle = false}) async {
    final original = source.toList();
    if (original.isEmpty) return;
    final selected = original[startIndex.clamp(0, original.length - 1).toInt()];
    final available = original.where((track) => track.isAvailable).toList();
    if (available.isEmpty) return;
    final index = available.indexWhere((track) => track.id == selected.id);
    await player.playTracks(available,
      startIndex: index < 0 ? 0 : index, shuffle: shuffle);
  }

  RadioMix radio(String mood, {Track? seed}) => RadioMixer.create(tracks,
    mood: mood, seedTrack: seed, seed: DateTime.now().microsecondsSinceEpoch);

  Future<RadioMix> playRadio(String mood, {Track? seed}) async {
    final mix = radio(mood, seed: seed);
    await playTracks(mix.tracks);
    return mix;
  }

  Future<void> saveRadio(String mood, {String? name}) async {
    final mix = radio(mood);
    if (mix.isEmpty) return;
    await repository.savePlaylist(LocalPlaylist(
      id: 'playlist:mix:${DateTime.now().microsecondsSinceEpoch}',
      name: name ?? 'Mix $mood', trackIds: mix.tracks.map((track) => track.id).toList()));
    await reload();
  }

  Future<void> playPlaylist(LocalPlaylist playlist) async {
    final catalogue = {for (final track in tracks) track.id: track};
    await playTracks(playlist.trackIds.map((id) => catalogue[id])
        .whereType<Track>());
  }

  Future<ImportPreview> previewImport(String link, {bool permission = false}) =>
      importer.preview(link, directDownloadPermission: permission);

  Future<void> downloadImport(ImportPreview preview, {Set<String>? ids}) async {
    await importer.download(preview, selectedTrackIds: ids);
    await reload();
  }

  @override
  void dispose() {
    unawaited(_imports?.cancel());
    player.dispose();
    super.dispose();
  }
}
