import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/models/track.dart';
import '../../core/queue/queue.dart';

/// Owns the queue for both application controls and Android media controls.
/// Queue changes happen synchronously; engine work is serialized and checks its
/// revision after each await, so obsolete loads cannot start playing.
class OfflineAudioHandler extends BaseAudioHandler {
  OfflineAudioHandler._(this._player, this._session) {
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (_) => _publishPlayback(),
        onError: (Object error, StackTrace stackTrace) {
          final token = _loadedToken;
          if (token != null) _handleAudioError(token);
        },
      ),
    );
    _subscriptions.add(
      _player.errorStream.listen((_) {
        final token = _loadedToken;
        if (token != null) _handleAudioError(token);
      }),
    );
    _subscriptions.add(
      _player.processingStateStream.listen((processing) {
        final token = _loadedToken;
        if (processing == ProcessingState.completed && token != null) {
          // Capture the token now, before a nearby Next changes the queue.
          scheduleMicrotask(() {
            if (_closed) return;
            final next = QueueReducer.finished(
              state.value,
              playbackToken: token,
            );
            if (!identical(next, state.value)) {
              _lastCompletionAt = DateTime.now();
              _lastCompletionToken = next.playbackToken;
              unawaited(_replace(next));
            }
          });
        }
        _publishPlayback();
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((value) {
        if (_loadedToken != state.value.playbackToken ||
            _loading.value ||
            _pendingSeek != null ||
            state.value.hasEnded) {
          return;
        }
        position.value = value;
        state.value = QueueReducer.seek(state.value, value.inMilliseconds);
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((value) {
        if (_loadedToken == state.value.playbackToken && value != null) {
          duration.value = value;
        }
      }),
    );
    _subscriptions.add(
      _session.interruptionEventStream.listen(_onInterruption),
    );
    _subscriptions.add(
      _session.becomingNoisyEventStream.listen((_) {
        // Unplugging headphones never resumes automatically.
        unawaited(pause());
      }),
    );
    _publishQueue();
    _publishPlayback();
  }

  static Future<OfflineAudioHandler> create() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    return OfflineAudioHandler._(
      AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      ),
      session,
    );
  }

  final AudioPlayer _player;
  final AudioSession _session;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final ValueNotifier<QueueState> state = ValueNotifier(QueueState.empty());
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> _loading = ValueNotifier(false);
  ValueListenable<bool> get loading => _loading;

  Future<void> _engineTail = Future.value();
  int _revision = 0;
  int _userIntent = 0;
  int? _loadedToken;
  Duration? _pendingSeek;
  int? _pendingSeekToken;
  DateTime? _lastCompletionAt;
  int? _lastCompletionToken;
  int? _resumeIntent;
  bool _resumeAfterInterruption = false;
  bool _interrupted = false;
  bool _closed = false;

  Future<void> playTracks(
    Iterable<Track> tracks, {
    int startIndex = 0,
    bool? shuffle,
  }) {
    _assertOpen();
    _userAction(requestPlay: true);
    error.value = null;
    final old = state.value;
    return _replace(
      QueueReducer.start(
        tracks,
        startIndex: startIndex,
        shuffle: shuffle ?? old.shuffleEnabled,
        seed: DateTime.now().millisecondsSinceEpoch,
        repeatMode: old.repeatMode,
        playbackToken: old.playbackToken,
      ),
    );
  }

  Future<void> restoreSnapshot(
    Map<String, dynamic> snapshot,
    Iterable<Track> catalogue,
  ) {
    _assertOpen();
    _userAction();
    error.value = null;
    return _replace(QueueState.fromJson(snapshot, tracks: catalogue));
  }

  @override
  Future<void> play() {
    _assertOpen();
    _userAction(requestPlay: true);
    error.value = null;
    return _replace(QueueReducer.play(state.value));
  }

  @override
  Future<void> pause() {
    _assertOpen();
    _userAction();
    return _replace(QueueReducer.pause(state.value));
  }

  @override
  Future<void> stop() async {
    _assertOpen();
    _userAction();
    final paused = _replace(QueueReducer.pause(state.value));
    final revision = _revision;
    await paused;
    if (_closed || revision != _revision) return;
    final stopped = _engineTail.then((_) async {
      if (_closed || revision != _revision) return;
      await _player.stop();
      if (_closed || revision != _revision) return;
      _loadedToken = null;
      _publishPlayback();
      await super.stop();
    });
    _engineTail = stopped;
    await stopped;
  }

  @override
  Future<void> seek(Duration position) {
    _assertOpen();
    _userAction();
    final next = QueueReducer.seek(state.value, position.inMilliseconds);
    return _replace(next, seek: true);
  }

  @override
  Future<void> skipToNext() {
    _assertOpen();
    _userAction();
    // Completion and headset/UI Next may describe the same boundary in either
    // order. The completion token rejects Next->completion; this tiny boundary
    // window rejects completion->Next without ignoring later manual advances.
    final completion = _lastCompletionAt;
    if (_lastCompletionToken == state.value.playbackToken &&
        completion != null &&
        DateTime.now().difference(completion) <
            const Duration(milliseconds: 150)) {
      return _engineTail;
    }
    return _replace(QueueReducer.next(state.value));
  }

  @override
  Future<void> skipToPrevious() {
    _assertOpen();
    _userAction();
    return _replace(QueueReducer.previous(state.value));
  }

  @override
  Future<void> skipToQueueItem(int index) {
    final tracks = _mediaQueue;
    if (index < 0 || index >= tracks.length) return Future.value();
    _userAction(requestPlay: true);
    return _replace(QueueReducer.select(state.value, tracks[index].id));
  }

  Future<void> remove(String trackId) =>
      _replace(QueueReducer.remove(state.value, trackId));

  Future<void> reorder(int oldIndex, int newIndex) => _replace(
    QueueReducer.reorder(state.value, oldIndex: oldIndex, newIndex: newIndex),
  );

  Future<void> toggleShuffle() => setShuffleMode(
    state.value.shuffleEnabled
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all,
  );

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) => _replace(
    QueueReducer.setShuffle(
      state.value,
      shuffleMode != AudioServiceShuffleMode.none,
      seed: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  Future<void> cycleRepeat() {
    final modes = RepeatMode.values;
    return _replace(
      QueueReducer.setRepeat(
        state.value,
        modes[(state.value.repeatMode.index + 1) % modes.length],
      ),
    );
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) => _replace(
    QueueReducer.setRepeat(
      state.value,
      switch (repeatMode) {
        AudioServiceRepeatMode.one => RepeatMode.one,
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group =>
          RepeatMode.all,
        AudioServiceRepeatMode.none => RepeatMode.off,
      },
    ),
  );

  void _userAction({bool requestPlay = false}) {
    _userIntent++;
    _resumeAfterInterruption = false;
    // Permanent focus loss need not emit an end event. A later explicit Play
    // must be able to request focus again instead of being stuck interrupted.
    if (requestPlay) _interrupted = false;
  }

  Future<void> _replace(QueueState next, {bool seek = false}) {
    _assertOpen();
    state.value = next;
    position.value = Duration(milliseconds: next.positionMs);
    if (_loadedToken != next.playbackToken) {
      duration.value = next.currentTrack?.duration ?? Duration.zero;
    }
    final revision = ++_revision;
    if (seek) {
      _pendingSeek = Duration(milliseconds: next.positionMs);
      _pendingSeekToken = next.playbackToken;
    } else if (_pendingSeekToken != next.playbackToken) {
      _pendingSeek = null;
      _pendingSeekToken = null;
    }
    _publishQueue();
    _publishPlayback();
    final task = _engineTail.then((_) async {
      if (_closed || revision != _revision) return;
      await _syncAudio(revision);
    });
    // A failed operation must not poison later commands.
    _engineTail = task.catchError((Object failure, StackTrace stackTrace) {
      if (!_closed && revision == _revision) {
        _loading.value = false;
        error.value = 'Pemutaran terhenti. Coba putar lagi.';
        state.value = QueueReducer.pause(state.value);
        _publishPlayback();
      }
    });
    return _engineTail;
  }

  Future<void> _syncAudio(int revision) async {
    final current = state.value;
    final track = current.currentTrack;
    if (track == null) {
      _loadedToken = null;
      await _player.stop();
      if (_closed || revision != _revision) return;
      if (!_retainInterruptedFocus) await _session.setActive(false);
      _loading.value = false;
      _publishPlayback();
      return;
    }
    if (_loadedToken != current.playbackToken) {
      _loadedToken = null;
      // Restoration shows the saved position without opening/starting audio.
      if (!current.isPlaying) {
        await _player.stop();
        if (_closed || revision != _revision) return;
        if (!_retainInterruptedFocus) await _session.setActive(false);
        _loading.value = false;
        _publishPlayback();
        return;
      }
      if (!track.isAvailable ||
          !{'file', 'content'}.contains(track.audioUri.scheme)) {
        _handleAudioError(current.playbackToken);
        return;
      }
      _loading.value = true;
      _publishPlayback();
      try {
        // setAudioSource preserves just_audio's playing flag. Pause first so
        // neither a superseded load nor a paused/interrupted request can start
        // audio before the intent/focus checks below.
        await _player.pause();
        if (_closed || revision != _revision) return;
        final loadedDuration = await _player.setAudioSource(
          AudioSource.uri(track.audioUri, tag: _mediaItem(track)),
          initialPosition: Duration(milliseconds: current.positionMs),
        );
        if (_closed || revision != _revision) return;
        _loadedToken = current.playbackToken;
        duration.value = loadedDuration ?? track.duration;
        mediaItem.add(_mediaItem(track, actualDuration: duration.value));
        _loading.value = false;
      } catch (_) {
        if (!_closed && current.playbackToken == state.value.playbackToken) {
          _loading.value = false;
          _handleAudioError(current.playbackToken);
        }
        return;
      }
    }
    if (_closed || revision != _revision) return;
    final pendingSeek = _pendingSeek;
    if (pendingSeek != null &&
        _pendingSeekToken == state.value.playbackToken) {
      await _player.seek(pendingSeek);
      if (pendingSeek == _pendingSeek) {
        _pendingSeek = null;
        _pendingSeekToken = null;
      }
      if (_closed || revision != _revision) return;
    }
    if (state.value.isPlaying && !_interrupted) {
      final active = await _session.setActive(true);
      if (_closed || revision != _revision) return;
      if (!active) {
        error.value = 'Audio sedang digunakan aplikasi lain. Coba putar lagi.';
        unawaited(_replace(QueueReducer.pause(state.value)));
        return;
      }
      final token = state.value.playbackToken;
      // just_audio's play future lasts until pause/completion; awaiting it here
      // would block Pause, Next, and Android media controls.
      unawaited(
        _player.play().catchError((Object failure, StackTrace stackTrace) {
          if (!_closed) _handleAudioError(token);
        }),
      );
    } else {
      await _player.pause();
      if (_closed || revision != _revision) return;
      if (!_retainInterruptedFocus) await _session.setActive(false);
    }
    _publishPlayback();
  }

  void _handleAudioError(int token) {
    if (_closed || token != state.value.playbackToken) return;
    final track = state.value.currentTrack;
    if (track == null) return;
    _loadedToken = null;
    _loading.value = false;
    // Remove each failed entry from this queue. Even Repeat All/One therefore
    // tries no more than its finite number of entries instead of looping.
    final next = QueueReducer.remove(state.value, track.id);
    error.value =
        'Tidak dapat memutar “${track.title}”. Berkas tidak dapat diakses '
        'atau format tidak didukung. '
        '${next.currentTrack == null ? 'Antrean dihentikan.' : 'Melanjutkan ke lagu berikutnya.'}';
    unawaited(_replace(next));
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (_closed) return;
    if (event.begin) {
      if (event.type == AudioInterruptionType.duck) {
        unawaited(_player.setVolume(0.2));
        return;
      }
      _interrupted = true;
      _resumeAfterInterruption =
          event.type == AudioInterruptionType.pause && state.value.isPlaying;
      _resumeIntent = _userIntent;
      unawaited(_replace(QueueReducer.pause(state.value)));
    } else {
      unawaited(_player.setVolume(1));
      if (event.type == AudioInterruptionType.duck) return;
      _interrupted = false;
      final resume =
          event.type == AudioInterruptionType.pause &&
          _resumeAfterInterruption &&
          _resumeIntent == _userIntent;
      _resumeAfterInterruption = false;
      if (resume) unawaited(_replace(QueueReducer.play(state.value)));
    }
  }

  bool get _retainInterruptedFocus =>
      _interrupted &&
      _resumeAfterInterruption &&
      _resumeIntent == _userIntent;

  MediaItem _mediaItem(Track track, {Duration? actualDuration}) {
    final art = track.artworkUri == null
        ? null
        : Uri.tryParse(track.artworkUri!);
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration:
          actualDuration ?? (track.durationMs > 0 ? track.duration : null),
      artUri: art != null && {'file', 'content'}.contains(art.scheme) ? art : null,
      extras: {'uri': track.uri},
    );
  }

  List<Track> get _mediaQueue => [
    if (state.value.currentTrack != null) state.value.currentTrack!,
    ...state.value.upcomingTracks,
  ];

  void _publishQueue() {
    queue.add(_mediaQueue.map(_mediaItem).toList());
    final current = state.value.currentTrack;
    mediaItem.add(
      current == null
          ? null
          : _mediaItem(
              current,
              actualDuration: duration.value > Duration.zero
                  ? duration.value
                  : null,
            ),
    );
  }

  void _publishPlayback() {
    if (_closed) return;
    final current = state.value;
    final processing = _loading.value
        ? AudioProcessingState.loading
        : current.hasEnded
        ? AudioProcessingState.completed
        : _loadedToken == null
        ? AudioProcessingState.idle
        : switch (_player.processingState) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          };
    final index = _mediaQueue.indexWhere(
      (track) => track.id == current.currentId,
    );
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (current.isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: current.isPlaying && !_interrupted,
        updatePosition: position.value,
        bufferedPosition: _player.bufferedPosition,
        speed: 1,
        queueIndex: index < 0 ? null : index,
        repeatMode: switch (current.repeatMode) {
          RepeatMode.off => AudioServiceRepeatMode.none,
          RepeatMode.one => AudioServiceRepeatMode.one,
          RepeatMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: current.shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  void _assertOpen() {
    if (_closed) throw StateError('The audio handler has been closed.');
  }

  Future<void> close() async {
    if (_closed) return;
    await stop();
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    state.dispose();
    position.dispose();
    duration.dispose();
    error.dispose();
    _loading.dispose();
  }
}
