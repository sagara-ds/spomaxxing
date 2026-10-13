import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/core/models/track.dart';
import 'package:spomaxxing/core/radio/radio_mixer.dart';

Track track(String id, {Set<String> tags = const {}, String artist = 'Artist', bool available = true}) => Track(
  id: id,
  uri: 'file:///music/$id.mp3',
  title: 'Happy focus chill $id',
  artist: artist,
  tags: tags,
  isAvailable: available,
);

void main() {
  test('aliases match explicit tags without guessing from titles', () {
    final mix = RadioMixer.create([
      track('tagged', tags: {'tenang'}),
      track('metadata-only'),
      track('unavailable', tags: {'santai'}, available: false),
    ], mood: ' CHILL ');
    expect(mix.tracks.map((item) => item.id), ['tagged']);
    expect(mix.explanationFor('tagged'), 'Tag: santai');
    expect(mix.hasFewerThanTarget, isTrue);
    expect(MoodCatalog.normalize('sleep'), 'tidur');
    expect(MoodCatalog.isMood('konsentrasi'), isTrue);
  });

  test('empty, untagged and inaccessible collections produce empty mixes', () {
    expect(RadioMixer.create([], mood: 'fokus').isEmpty, isTrue);
    expect(RadioMixer.create([track('one')], mood: 'fokus').isEmpty, isTrue);
    final unavailable = track('one', tags: {'fokus'}, available: false);
    expect(RadioMixer.create([unavailable], seedTrack: unavailable).isEmpty, isTrue);
    final untagged = track('one');
    expect(RadioMixer.create([untagged], seedTrack: untagged).isEmpty, isTrue);
  });

  test('mix is deterministic, capped at 25 unique accessible tracks', () {
    final library = List.generate(40, (i) => track('$i', tags: {'fokus'}, artist: 'Artist ${i % 5}'));
    final first = RadioMixer.create([...library, library.first], mood: 'focus', seed: 99);
    final second = RadioMixer.create(library, mood: 'fokus', seed: 99);
    expect(first.tracks.length, 25);
    expect(first.tracks.map((item) => item.id).toSet().length, 25);
    expect(first.candidateCount, 40);
    expect(first.tracks.map((item) => item.id), second.tracks.map((item) => item.id));
    expect(RadioMixer.create(library, mood: 'fokus', limit: 100).tracks.length, 25);
  });

  test('artists alternate where the candidate distribution permits it', () {
    final library = List.generate(12, (i) => track('$i', tags: {'semangat'}, artist: 'Artist ${i % 3}'));
    final mix = RadioMixer.create(library, mood: 'semangat', seed: 8);
    for (var i = 1; i < mix.tracks.length; i++) {
      expect(mix.tracks[i].artist, isNot(mix.tracks[i - 1].artist));
    }
  });

  test('track seed leads and additional explicit tag overlap ranks candidates', () {
    final initial = track('seed', tags: {'fokus', 'santai'});
    final mix = RadioMixer.create([
      track('unrelated', tags: {'bahagia'}),
      track('partial', tags: {'fokus'}),
      initial,
      track('complete', tags: {'focus', 'chill'}),
    ], seedTrack: initial);
    expect(mix.tracks.map((item) => item.id), ['seed', 'complete', 'partial']);
    expect(mix.candidateCount, 3);
    expect(mix.reasons['complete'], ['fokus', 'santai']);
  });
}
