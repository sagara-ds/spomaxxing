import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/track.dart';
import '../../core/queue/queue.dart';
import 'offline_audio_handler.dart';

typedef QueueSnapshotWriter = Future<void> Function(Map<String, Object?> data);

/// UI adapter. The audio handler remains alive when a widget is disposed so
/// background notification/headset controls retain the same queue.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required OfflineAudioHandler handler,
    QueueSnapshotWriter? onSnapshot,
  }) : _handler = handler,
       _onSnapshot = onSnapshot,
       _previousState = handler.state.value {
    _handler.state.addListener(_onStateChanged);
    _handler.duration.addListener(_onValueChanged);
    _handler.error.addListener(_onValueChanged);
    _handler.loading.addListener(_onValueChanged);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_dirty) unawaited(flushSnapshot());
    });
  }

  final OfflineAudioHandler _handler;
  final QueueSnapshotWriter? _onSnapshot;
  late final Timer _timer;
  QueueState _previousState;
  Future<void> _saveTail = Future.value();
  bool _disposed = false;
  bool _dirty = false;
  String? _persistenceError;

  QueueState get state => _handler.state.value;
  Duration get position => Duration(milliseconds: state.positionMs);
  Duration get duration => _handler.duration.value;
  String? get error => _handler.error.value ?? _persistenceError;
  bool get isLoading => _handler.loading.value;
  Map<String, Object?> get snapshot => state.toJson();

  Future<void> playTracks(
    Iterable<Track> tracks, {
    int startIndex = 0,
    bool? shuffle,
  }) => _handler.playTracks(tracks, startIndex: startIndex, shuffle: shuffle);

  Future<void> playPause() =>
      state.isPlaying ? _handler.pause() : _handler.play();
  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();
  Future<void> seek(Duration value) => _handler.seek(value);
  Future<void> toggleShuffle() => _handler.toggleShuffle();
  Future<void> cycleRepeat() => _handler.cycleRepeat();
  Future<void> remove(String trackId) => _handler.remove(trackId);
  Future<void> reorder(int oldIndex, int newIndex) =>
      _handler.reorder(oldIndex, newIndex);

  Future<void> restoreSnapshot(
    Map<String, dynamic> data,
    Iterable<Track> catalogue,
  ) => _handler.restoreSnapshot(data, catalogue);

  void _onStateChanged() {
    final next = state;
    final previous = _previousState;
    _previousState = next;
    _dirty = true;
    if (!_disposed) notifyListeners();
    if (next.playbackToken != previous.playbackToken ||
        next.isPlaying != previous.isPlaying ||
        next.repeatMode != previous.repeatMode ||
        next.shuffleEnabled != previous.shuffleEnabled ||
        !listEquals(next.upcomingIds, previous.upcomingIds) ||
        !listEquals(next.tracks, previous.tracks)) {
      unawaited(flushSnapshot());
    }
  }

  void _onValueChanged() {
    if (!_disposed) notifyListeners();
  }

  /// Writes are serialized so a slower old snapshot cannot overwrite a newer
  /// queue. Position ticks save at most once per five seconds.
  Future<void> flushSnapshot() {
    final writer = _onSnapshot;
    if (writer == null) return Future.value();
    final data = snapshot;
    _dirty = false;
    _saveTail = _saveTail.then((_) async {
      try {
        await writer(data);
        if (_persistenceError != null) {
          _persistenceError = null;
          _onValueChanged();
        }
      } catch (_) {
        _dirty = true;
        _persistenceError = 'Posisi pemutaran belum dapat disimpan.';
        _onValueChanged();
      }
    });
    return _saveTail;
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(flushSnapshot());
    _disposed = true;
    _timer.cancel();
    _handler.state.removeListener(_onStateChanged);
    _handler.duration.removeListener(_onValueChanged);
    _handler.error.removeListener(_onValueChanged);
    _handler.loading.removeListener(_onValueChanged);
    super.dispose();
  }
}
