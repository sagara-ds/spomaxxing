import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/features/imports/import_service.dart';
import 'package:spomaxxing/features/imports/youtube_source.dart';

const id = '0123456789012345678901';
String embed(Map<String, dynamic> entity) => '<script id="__NEXT_DATA__" type="application/json">${jsonEncode({
  'props': {'pageProps': {'state': {'data': {'entity': entity}}}},
})}</script>';

void main() {
  test('recognizes supported YouTube video and playlist URLs', () {
    for (final link in ['https://youtu.be/abcdefghijk', 'https://www.youtube.com/watch?v=abcdefghijk&list=PL0123456789',
      'https://music.youtube.com/watch?v=abcdefghijk', 'https://www.youtube.com/shorts/abcdefghijk']) {
      final parsed = parseImportLink(link);
      expect(parsed.kind, ImportLinkKind.youtubeVideo);
      expect(parsed.resourceId, 'abcdefghijk');
    }
    expect(parseImportLink('https://www.youtube.com/playlist?list=PL0123456789').kind, ImportLinkKind.youtubePlaylist);
    expect(() => parseImportLink('https://youtube.com.evil.test/watch?v=abcdefghijk'), throwsA(isA<ImportException>()));
    expect(() => parseImportLink('https://youtube.com/watch?v=bad'), throwsA(isA<ImportException>()));
  });

  test('public Spotify metadata preserves ordered repeated tracks without claiming audio', () {
    final link = parseImportLink('https://open.spotify.com/playlist/$id');
    final track = {'uri': 'spotify:track:$id', 'title': 'Judul', 'subtitle': 'Artis', 'duration': 120000};
    final preview = parseSpotifyEmbed(embed({'name': 'Daftar', 'trackList': [track, track]}), link);
    expect(preview.isPlaylist, isTrue);
    expect(preview.name, 'Daftar');
    expect(preview.tracks.map((t) => t.id), ['spotify:$id:0', 'spotify:$id:1']);
    expect(preview.tracks.every((t) => t.provider == 'spotify'), isTrue);
    expect(preview.tracks.first.durationMs, 120000);
  });

  test('single Spotify metadata requires a track identity and artist', () {
    final link = parseImportLink('https://open.spotify.com/track/$id');
    final entity = {'uri': 'spotify:track:$id', 'name': 'Lagu', 'artists': [{'name': 'Artis'}], 'duration': 10000};
    final preview = parseSpotifyEmbed(embed(entity), link);
    expect(preview.isPlaylist, isFalse);
    expect(preview.tracks.single.artist, 'Artis');
    expect(() => parseSpotifyEmbed(embed({...entity, 'artists': []}), link), throwsA(isA<ImportException>()));
  });

  test('missing, empty, oversized and changed metadata never creates completed playlist', () {
    final link = parseImportLink('https://open.spotify.com/playlist/$id');
    for (final html in ['', '<script id="__NEXT_DATA__">{bad}</script>', embed({'name': 'Privat', 'trackList': []}),
      embed({'trackList': List.filled(101, {})})]) {
      expect(() => parseSpotifyEmbed(html, link), throwsA(isA<ImportException>()));
    }
  });

  test('explicit YouTube selection preserves Spotify identity and provenance', () {
    final original = ImportCandidate(id: 'spotify:$id:0', title: 'Asal', artist: 'Artis asal',
      url: Uri.parse('https://open.spotify.com/track/$id'), provider: 'spotify',
      durationMs: 123000, license: 'pending', source: 'Spotify asal');
    final selected = const YoutubeResult(id: 'abcdefghijk', title: 'Versi yang dipilih', channel: 'Kanal', durationMs: 124000).forTrack(original);
    expect(selected.id, original.id);
    expect(selected.title, original.title);
    expect(selected.provider, 'youtube');
    expect(selected.url.toString(), 'https://www.youtube.com/watch?v=abcdefghijk');
    expect(selected.source, contains('Versi yang dipilih'));
    final restored = ImportCandidate.fromJson(selected.toJson());
    expect(restored.provider, 'youtube');
    expect(restored.durationMs, 123000);
  });
}
