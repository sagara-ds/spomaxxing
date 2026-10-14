import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/features/imports/import_service.dart';
import 'package:spomaxxing/features/imports/spotdown_source.dart';

void main() {
  test('session accepts a live token and rejects an expired token', () {
    final session = SpotdownSession();
    session.updateFromStorage(
      jsonEncode({
        'token': 'session-token',
        'expires': DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      }),
    );
    expect(session.isValid, isTrue);
    expect(session.token, 'session-token');

    expect(
      () => session.updateFromStorage(
        jsonEncode({
          'token': 'expired',
          'expires': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        }),
      ),
      throwsA(isA<SpotdownAuthenticationRequired>()),
    );
  });

  test(
    'preview maps Spotdown songs without persisting the session token',
    () async {
      final session = SpotdownSession();
      session.updateFromStorage(
        jsonEncode({
          'token': 'secret-session-token',
          'expires': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        }),
      );
      final source = SpotdownSource(
        session: session,
        jsonRequest: (method, uri, body) async {
          expect(method, 'GET');
          expect(uri.path, '/apinew/song-details');
          return {
            'success': true,
            'contentType': 'playlist',
            'songs': [
              {
                'title': 'First song',
                'artist': 'Artist',
                'url': 'https://open.spotify.com/track/0123456789abcdefghijkl',
              },
              {
                'title': 'Second song',
                'artist': 'Artist',
                'url': 'https://open.spotify.com/track/abcdefghijkl0123456789',
              },
            ],
          };
        },
      );

      final link = parseImportLink(
        'https://open.spotify.com/playlist/0123456789abcdefghijkl',
      );
      final preview = await source.preview(link);
      expect(preview.isPlaylist, isTrue);
      expect(
        preview.tracks.map((track) => track.provider),
        everyElement('spotdown'),
      );
      expect(preview.tracks.map((track) => track.title), [
        'First song',
        'Second song',
      ]);
      expect(
        jsonEncode(preview.toJson()),
        isNot(contains('secret-session-token')),
      );
      source.close();
    },
  );

  test('download retries Spotdown server failures three times', () async {
    var attempts = 0;
    final source = SpotdownSource(
      jsonRequest: (method, uri, body) async {
        attempts++;
        throw const SpotdownServerException();
      },
    );
    final candidate = ImportCandidate(
      id: 'spotdown:test:0',
      title: 'Back N Forth',
      artist: 'Jack Murmin',
      url: Uri.parse('https://open.spotify.com/track/0123456789abcdefghijkl'),
      provider: 'spotdown',
      license: 'Izin pengguna',
      source: 'Spotify via Spotdown',
    );

    await expectLater(
      source.resolve(candidate),
      throwsA(isA<SpotdownServerException>()),
    );
    expect(attempts, 4);
    source.close();
  });
}
