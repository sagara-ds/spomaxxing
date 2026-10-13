import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/core/models/track.dart';

void main() {
  test('local track round-trips tags, metadata, favorites and availability', () {
    final track = Track(
      id: Track.mediaStoreId('external_primary', 42),
      uri: 'content://media/external_primary/audio/media/42',
      title: 'Sore',
      artist: 'Artis',
      album: 'Album',
      durationMs: 125000,
      genre: 'Ambient',
      artworkUri: 'file:///storage/art.jpg',
      tags: {' Fokus ', 'fokus', 'santai'},
      isFavorite: true,
      isAvailable: false,
    );
    final restored = Track.fromJson(track.toJson());
    expect(restored.toJson(), track.toJson());
    expect(restored.tags, {'fokus', 'santai'});
    expect(() => restored.tags.add('sedih'), throwsUnsupportedError);
  });

  test('identity depends on storage source, not duplicate title', () {
    expect(
      Track.mediaStoreId('external', 42),
      isNot(Track.mediaStoreId('external_primary', 42)),
    );
    expect(Track.importId('42'), isNot(Track.mediaStoreId('external', 42)));
  });

  test('metadata falls back to filename and streaming URIs are rejected', () {
    final track = Track(
      id: 'import:one',
      uri: 'file:///music/Night%20song.flac',
      title: ' ',
      artist: '',
    );
    expect(track.title, 'Night song.flac');
    expect(track.artist, 'Artis tidak diketahui');
    expect(
      () => Track(id: 'remote', uri: 'https://example.com/audio.mp3', title: 'X'),
      throwsArgumentError,
    );
  });

  test('edits preserve identity and original metadata', () {
    final original = Track(
      id: 'import:1',
      uri: 'file:///one.mp3',
      title: 'One',
      tags: {'santai'},
    );
    final edited = original.copyWith(isFavorite: true, tags: {'fokus'});
    expect(edited.id, original.id);
    expect(edited.isFavorite, isTrue);
    expect(original.isFavorite, isFalse);
    expect(original.tags, {'santai'});
  });
}
