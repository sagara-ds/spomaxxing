import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/core/models/track.dart';
import 'package:spomaxxing/core/queue/queue.dart';

List<Track> tracks([int count = 5]) => List.generate(
  count,
  (index) => Track(
    id: '$index',
    uri: 'file:///music/$index.mp3',
    title: 'Song $index',
    durationMs: 10000,
  ),
);

void main() {
  test('media selection preserves pending order and actual playback history', () {
    final state = QueueReducer.start(tracks(4));
    final selected = QueueReducer.select(state, '3');
    expect(selected.currentId, '3');
    expect(selected.historyIds, ['0']);
    expect(selected.upcomingIds, ['1', '2']);
    expect(selected.playbackToken, greaterThan(state.playbackToken));
    expect(QueueReducer.finished(selected, playbackToken: state.playbackToken), same(selected));
    expect(QueueReducer.previous(selected).currentId, '0');
  });
  test('repeat off finishes finite queue and remains paused after restore', () {
    var state = QueueReducer.start(tracks(2));
    state = QueueReducer.finished(state, playbackToken: state.playbackToken);
    expect(state.currentId, '1');
    state = QueueReducer.finished(state, playbackToken: state.playbackToken);
    expect(state.hasEnded, isTrue);
    expect(state.isPlaying, isFalse);
    expect(state.positionMs, 10000);
    final restored = QueueState.fromJson(state.toJson(), tracks: tracks(2));
    expect(restored.isPlaying, isFalse);
    expect(restored.hasEnded, isTrue);
    state = QueueReducer.play(restored);
    expect(state.currentId, '1');
    expect(state.positionMs, 0);
    expect(state.isPlaying, isTrue);
  });

  test('next and stale completion cannot accidentally advance twice', () {
    var state = QueueReducer.start(tracks());
    final completedToken = state.playbackToken;
    state = QueueReducer.next(state);
    final afterNext = state;
    state = QueueReducer.finished(state, playbackToken: completedToken);
    expect(state, same(afterNext));
    expect(state.currentId, '1');
    state = QueueReducer.finished(state, playbackToken: state.playbackToken);
    final afterFinished = state;
    state = QueueReducer.finished(state, playbackToken: afterNext.playbackToken);
    expect(state, same(afterFinished));
    expect(state.currentId, '2');
  });

  test('repeat one restarts naturally but manual next skips it', () {
    var state = QueueReducer.start(tracks(), repeatMode: RepeatMode.one);
    state = QueueReducer.seek(state, 9999);
    final firstToken = state.playbackToken;
    state = QueueReducer.finished(state, playbackToken: firstToken);
    expect(state.currentId, '0');
    expect(state.positionMs, 0);
    expect(state.playbackToken, greaterThan(firstToken));
    state = QueueReducer.finished(state, playbackToken: firstToken);
    expect(state.currentId, '0');
    state = QueueReducer.next(state);
    expect(state.currentId, '1');
  });

  test('shuffle preserves current and actual history; previous reverses playback', () {
    var state = QueueReducer.start(tracks(12));
    state = QueueReducer.next(state);
    state = QueueReducer.next(state);
    final shuffled = QueueReducer.setShuffle(state, true, seed: 27);
    expect(shuffled.currentId, '2');
    expect(shuffled.historyIds, ['0', '1']);
    expect(shuffled.upcomingIds.toSet(), state.upcomingIds.toSet());
    expect(
      shuffled.upcomingIds,
      QueueReducer.setShuffle(state, true, seed: 27).upcomingIds,
    );
    state = QueueReducer.next(shuffled);
    final actualNext = state.currentId;
    state = QueueReducer.previous(state);
    expect(state.currentId, '2');
    expect(state.historyIds, ['0', '1']);
    expect(state.upcomingIds.first, actualNext);
    final unshuffled = QueueReducer.setShuffle(state, false);
    expect(unshuffled.historyIds, state.historyIds);
    expect(unshuffled.currentId, state.currentId);
    expect(unshuffled.upcomingIds, orderedEquals(['3','4','5','6','7','8','9','10','11']));
  });

  test('shuffle plays each track once before repeat-all starts a new cycle', () {
    var state = QueueReducer.start(
      tracks(20),
      shuffle: true,
      seed: 9,
      repeatMode: RepeatMode.all,
    );
    final visited = <String>[];
    for (var i = 0; i < 20; i++) {
      visited.add(state.currentId!);
      state = QueueReducer.finished(state, playbackToken: state.playbackToken);
    }
    expect(visited.toSet().length, 20);
    expect(state.isPlaying, isTrue);
    expect(state.upcomingIds.length, 19);
    expect(state.currentId, isNot(visited.last));
  });

  test('previous restarts beyond threshold, then follows actual history', () {
    var state = QueueReducer.next(QueueReducer.start(tracks()));
    state = QueueReducer.seek(state, 4000);
    state = QueueReducer.previous(state);
    expect(state.currentId, '1');
    expect(state.positionMs, 0);
    state = QueueReducer.previous(state);
    expect(state.currentId, '0');
    expect(state.upcomingIds.first, '1');
  });

  test('restore preserves shuffle, prunes missing files and never auto-plays', () {
    var state = QueueReducer.start(tracks(), shuffle: true, seed: 44);
    state = QueueReducer.seek(state, 1200);
    final restored = QueueState.fromJson(state.toJson(), tracks: tracks());
    expect(restored.currentId, state.currentId);
    expect(restored.upcomingIds, state.upcomingIds);
    expect(restored.positionMs, 1200);
    expect(restored.shuffleEnabled, isTrue);
    expect(restored.isPlaying, isFalse);
    final withoutCurrent = tracks().where((track) => track.id != state.currentId);
    final pruned = QueueState.fromJson(state.toJson(), tracks: withoutCurrent);
    expect(pruned.currentId, state.upcomingIds.first);
    expect(pruned.positionMs, 0);
    expect(pruned.tracks.any((track) => track.id == state.currentId), isFalse);
  });

  test('remove and reorder affect only intended queue entries', () {
    var state = QueueReducer.start(tracks());
    state = QueueReducer.reorder(state, oldIndex: 0, newIndex: 4);
    expect(state.upcomingIds, ['2', '3', '4', '1']);
    state = QueueReducer.remove(state, '3');
    expect(state.upcomingIds, ['2', '4', '1']);
    state = QueueReducer.remove(state, '0');
    expect(state.currentId, '2');
    expect(state.upcomingIds, ['4', '1']);
    expect(state.tracks.map((track) => track.id), ['1', '2', '4']);
  });
}
