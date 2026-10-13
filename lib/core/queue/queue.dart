import 'dart:math';

import '../models/track.dart';

enum RepeatMode { off, one, all }

/// Immutable queue state. History contains tracks actually visited by playback.
class QueueState {
  QueueState._({
    required Iterable<Track> tracks,
    required this.currentId,
    required Iterable<String> upcomingIds,
    required Iterable<String> historyIds,
    required this.isPlaying,
    required this.positionMs,
    required this.repeatMode,
    required this.shuffleEnabled,
    required this.seed,
    required this.playbackToken,
    required this.hasEnded,
  }) : tracks = List.unmodifiable(tracks),
       upcomingIds = List.unmodifiable(upcomingIds),
       historyIds = List.unmodifiable(historyIds),
       _byId = Map.unmodifiable({for (final track in tracks) track.id: track});

  factory QueueState.empty() => QueueState._(
    tracks: [],
    currentId: null,
    upcomingIds: [],
    historyIds: [],
    isPlaying: false,
    positionMs: 0,
    repeatMode: RepeatMode.off,
    shuffleEnabled: false,
    seed: 0,
    playbackToken: 0,
    hasEnded: false,
  );

  final List<Track> tracks;
  final String? currentId;
  final List<String> upcomingIds;
  final List<String> historyIds;
  final bool isPlaying;
  final int positionMs;
  final RepeatMode repeatMode;
  final bool shuffleEnabled;
  final int seed;

  /// Capture this when loading audio; pass it back with its completion event.
  final int playbackToken;
  final bool hasEnded;
  final Map<String, Track> _byId;

  Track? get currentTrack => _byId[currentId];
  List<Track> get upcomingTracks => List.unmodifiable(
    upcomingIds.map((id) => _byId[id]!),
  );
  List<Track> get historyTracks => List.unmodifiable(
    historyIds.map((id) => _byId[id]!),
  );

  QueueState _copy({
    Iterable<Track>? tracks,
    String? currentId,
    bool clearCurrent = false,
    Iterable<String>? upcomingIds,
    Iterable<String>? historyIds,
    bool? isPlaying,
    int? positionMs,
    RepeatMode? repeatMode,
    bool? shuffleEnabled,
    int? seed,
    int? playbackToken,
    bool? hasEnded,
  }) => QueueState._(
    tracks: tracks ?? this.tracks,
    currentId: clearCurrent ? null : currentId ?? this.currentId,
    upcomingIds: upcomingIds ?? this.upcomingIds,
    historyIds: historyIds ?? this.historyIds,
    isPlaying: isPlaying ?? this.isPlaying,
    positionMs: positionMs ?? this.positionMs,
    repeatMode: repeatMode ?? this.repeatMode,
    shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
    seed: seed ?? this.seed,
    playbackToken: playbackToken ?? this.playbackToken,
    hasEnded: hasEnded ?? this.hasEnded,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'trackIds': tracks.map((track) => track.id).toList(),
    'currentId': currentId,
    'upcomingIds': upcomingIds,
    'historyIds': historyIds,
    'positionMs': positionMs,
    'repeatMode': repeatMode.name,
    'shuffleEnabled': shuffleEnabled,
    'seed': seed,
    'playbackToken': playbackToken,
    'hasEnded': hasEnded,
  };

  /// Restoration always pauses. Missing or inaccessible audio is pruned.
  factory QueueState.fromJson(
    Map<String, dynamic> json, {
    required Iterable<Track> tracks,
  }) {
    final catalogue = {
      for (final track in tracks)
        if (track.isAvailable) track.id: track,
    };
    List<String> ids(String key) => (json[key] as List<dynamic>? ?? [])
        .whereType<String>()
        .where(catalogue.containsKey)
        .toList();
    final queueIds = ids('trackIds').toSet().toList();
    final allowed = queueIds.toSet();
    final upcoming = ids('upcomingIds')
        .where(allowed.contains)
        .toSet()
        .toList();
    final history = ids('historyIds').where(allowed.contains).toList();
    var current = json['currentId'] as String?;
    var position = (json['positionMs'] as num?)?.toInt() ?? 0;
    if (!allowed.contains(current)) {
      current = upcoming.isEmpty ? null : upcoming.removeAt(0);
      position = 0;
    }
    upcoming.remove(current);
    final duration = catalogue[current]?.durationMs ?? 0;
    return QueueState._(
      tracks: queueIds.map((id) => catalogue[id]!),
      currentId: current,
      upcomingIds: upcoming,
      historyIds: history,
      isPlaying: false,
      positionMs: position
          .clamp(0, duration > 0 ? duration : max(0, position))
          .toInt(),
      repeatMode: RepeatMode.values.firstWhere(
        (mode) => mode.name == json['repeatMode'],
        orElse: () => RepeatMode.off,
      ),
      shuffleEnabled: json['shuffleEnabled'] as bool? ?? false,
      seed: (json['seed'] as num?)?.toInt() ?? 0,
      playbackToken: ((json['playbackToken'] as num?)?.toInt() ?? 0) + 1,
      hasEnded: current != null && (json['hasEnded'] as bool? ?? false),
    );
  }
}

/// All transitions are synchronous, making button and player events serializable.
abstract final class QueueReducer {
  static QueueState start(
    Iterable<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
    int seed = 0,
    RepeatMode repeatMode = RepeatMode.off,
    int playbackToken = 0,
  }) {
    final seen = <String>{};
    final queue = tracks
        .where((track) => track.isAvailable && seen.add(track.id))
        .toList();
    if (queue.isEmpty) {
      return QueueState.empty()._copy(
        repeatMode: repeatMode,
        shuffleEnabled: shuffle,
        seed: seed,
        playbackToken: playbackToken + 1,
      );
    }
    if (startIndex < 0 || startIndex >= queue.length) {
      throw RangeError.index(startIndex, queue, 'startIndex');
    }
    final current = queue[startIndex].id;
    final upcoming = (shuffle
            ? queue.where((track) => track.id != current)
            : queue.skip(startIndex + 1))
        .map((track) => track.id)
        .toList();
    if (shuffle) upcoming.shuffle(Random(seed));
    return QueueState._(
      tracks: queue,
      currentId: current,
      upcomingIds: upcoming,
      historyIds: [],
      isPlaying: true,
      positionMs: 0,
      repeatMode: repeatMode,
      shuffleEnabled: shuffle,
      seed: seed,
      playbackToken: playbackToken + 1,
      hasEnded: false,
    );
  }

  static QueueState play(QueueState state) {
    if (state.currentId == null) return state;
    return state._copy(
      isPlaying: true,
      positionMs: state.hasEnded ? 0 : state.positionMs,
      hasEnded: false,
      playbackToken: state.hasEnded
          ? state.playbackToken + 1
          : state.playbackToken,
    );
  }

  static QueueState pause(QueueState state) => state._copy(isPlaying: false);

  /// Select a pending entry without counting skipped entries as played history.
  static QueueState select(QueueState state, String trackId) {
    if (trackId != state.currentId && !state.upcomingIds.contains(trackId)) return state;
    return state._copy(
      currentId: trackId,
      upcomingIds: state.upcomingIds.where((id) => id != trackId),
      historyIds: [
        ...state.historyIds,
        if (state.currentId != null && state.currentId != trackId) state.currentId!,
      ],
      isPlaying: true,
      positionMs: 0,
      hasEnded: false,
      playbackToken: state.playbackToken + 1,
    );
  }

  static QueueState seek(QueueState state, int positionMs) {
    final track = state.currentTrack;
    if (track == null) return state;
    return state._copy(
      positionMs: positionMs.clamp(
        0,
        track.durationMs > 0 ? track.durationMs : max(0, positionMs),
      ).toInt(),
      hasEnded: false,
    );
  }

  static QueueState setRepeat(QueueState state, RepeatMode mode) =>
      state._copy(repeatMode: mode);

  static QueueState setShuffle(QueueState state, bool enabled, {int? seed}) {
    if (enabled == state.shuffleEnabled && seed == null) return state;
    final nextSeed = seed ?? state.seed;
    final remaining = state.upcomingIds.toList();
    if (enabled) {
      remaining.shuffle(Random(nextSeed));
    } else {
      final indexes = {
        for (var i = 0; i < state.tracks.length; i++) state.tracks[i].id: i,
      };
      remaining.sort((a, b) => indexes[a]!.compareTo(indexes[b]!));
    }
    return state._copy(
      upcomingIds: remaining,
      shuffleEnabled: enabled,
      seed: nextSeed,
    );
  }

  static QueueState next(QueueState state) {
    if (state.currentId == null) return state;
    final remaining = state.upcomingIds.toList();
    if (remaining.isEmpty && state.repeatMode == RepeatMode.all) {
      remaining.addAll(state.tracks.map((track) => track.id));
      if (state.shuffleEnabled) {
        remaining.shuffle(Random(state.seed + state.playbackToken));
        // Avoid repeating the boundary track when another choice exists.
        if (remaining.length > 1 && remaining.first == state.currentId) {
          remaining.add(remaining.removeAt(0));
        }
      }
    }
    if (remaining.isEmpty) {
      return state._copy(
        isPlaying: false,
        hasEnded: true,
        positionMs: state.currentTrack!.durationMs,
        playbackToken: state.playbackToken + 1,
      );
    }
    return state._copy(
      currentId: remaining.removeAt(0),
      upcomingIds: remaining,
      historyIds: [...state.historyIds, state.currentId!],
      positionMs: 0,
      hasEnded: false,
      playbackToken: state.playbackToken + 1,
    );
  }

  static QueueState finished(QueueState state, {required int playbackToken}) {
    if (playbackToken != state.playbackToken || !state.isPlaying) return state;
    if (state.repeatMode == RepeatMode.one && state.currentId != null) {
      return state._copy(
        positionMs: 0,
        hasEnded: false,
        playbackToken: state.playbackToken + 1,
      );
    }
    return next(state);
  }

  static QueueState previous(QueueState state, {int restartThresholdMs = 3000}) {
    if (state.currentId == null) return state;
    if (state.positionMs > restartThresholdMs || state.historyIds.isEmpty) {
      return state._copy(
        positionMs: 0,
        hasEnded: false,
        playbackToken: state.playbackToken + 1,
      );
    }
    final history = state.historyIds.toList();
    final previous = history.removeLast();
    return state._copy(
      currentId: previous,
      historyIds: history,
      upcomingIds: [
        state.currentId!,
        ...state.upcomingIds.where((id) => id != state.currentId && id != previous),
      ],
      positionMs: 0,
      hasEnded: false,
      playbackToken: state.playbackToken + 1,
    );
  }

  static QueueState remove(QueueState state, String trackId) {
    if (!state._byId.containsKey(trackId)) return state;
    final tracks = state.tracks.where((track) => track.id != trackId).toList();
    final remaining = state.upcomingIds.where((id) => id != trackId).toList();
    final history = state.historyIds.where((id) => id != trackId).toList();
    if (trackId != state.currentId) {
      return state._copy(
        tracks: tracks,
        upcomingIds: remaining,
        historyIds: history,
      );
    }
    final replacement = remaining.isNotEmpty
        ? remaining.removeAt(0)
        : state.repeatMode == RepeatMode.all && tracks.isNotEmpty
        ? tracks.first.id
        : null;
    return state._copy(
      tracks: tracks,
      currentId: replacement,
      clearCurrent: replacement == null,
      upcomingIds: remaining,
      historyIds: history,
      positionMs: 0,
      isPlaying: replacement != null && state.isPlaying,
      hasEnded: false,
      playbackToken: state.playbackToken + 1,
    );
  }

  /// Uses Flutter's ReorderableListView insertion-index convention.
  static QueueState reorder(
    QueueState state, {
    required int oldIndex,
    required int newIndex,
  }) {
    final remaining = state.upcomingIds.toList();
    RangeError.checkValidIndex(oldIndex, remaining, 'oldIndex');
    RangeError.checkValueInInterval(newIndex, 0, remaining.length, 'newIndex');
    if (newIndex > oldIndex) newIndex--;
    remaining.insert(newIndex, remaining.removeAt(oldIndex));
    return state._copy(upcomingIds: remaining);
  }
}
