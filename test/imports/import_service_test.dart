import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/features/imports/import_service.dart';

final _audioUrl = Uri.parse('https://media.example.com/music/test.mp3');
final _manifestUrl = Uri.parse('https://media.example.com/playlist.json');

Map<String, dynamic> _entry(String id, {String? checksum}) => {
  'id': id,
  'title': 'Judul $id',
  'artist': 'Artis',
  'url': 'https://media.example.com/$id.mp3',
  'license': 'CC BY 4.0',
  'source': 'https://artist.example.com/releases/$id',
  'sha256': ?checksum,
};

String _manifest(List<Map<String, dynamic>> tracks) => jsonEncode({'version': 1, 'name': 'Playlist contoh', 'tracks': tracks});

ImportResponse _response(Uri uri, List<int> bytes, {int status = 200, String type = 'audio/mpeg', int? declaredSize}) => ImportResponse(
  statusCode: status, body: Stream.value(bytes), finalUri: uri,
  contentType: type, contentLength: declaredSize ?? bytes.length,
);

class _Transport implements ImportTransport {
  final Map<String, Future<ImportResponse> Function()> responses = {};
  final List<Uri> requested = [];
  @override
  Future<ImportResponse> get(Uri uri) {
    requested.add(uri);
    final callback = responses[uri.toString()];
    if (callback == null) throw StateError('No fake response for $uri');
    return callback();
  }
  @override
  void close() {}
}

/// A valid virtual byte list lets the boundary test avoid a 256 MiB allocation.
class _RepeatedByteChunk extends ListBase<int> {
  _RepeatedByteChunk(this.length);
  @override
  int length;
  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return 7;
  }
  @override
  void operator []=(int index, int value) => throw UnsupportedError('Immutable');
}

class _Harness {
  _Harness(this.directory);
  final Directory directory;
  final _Transport transport = _Transport();
  final List<ImportJob> savedJobs = [];
  final List<ImportedAudio> savedAudio = [];
  final List<List<String>> playlists = [];
  List<ImportJob> restoredJobs = [];
  bool connected = true;
  int connectionChecks = 0;
  int decoderChecks = 0;
  Future<Map<String, dynamic>> Function(Uri)? decoder;

  late final service = ImportService(
    transport: transport,
    hasConnection: () async { connectionChecks++; return connected; },
    storageDirectory: () async => directory,
    validateAudio: (uri) async {
      decoderChecks++;
      expect(uri.scheme, 'file');
      expect(await File.fromUri(uri).exists(), isTrue);
      return decoder == null ? {'durationMs': 120000} : await decoder!(uri);
    },
    saveLocalTrack: (audio) async {
      expect(await File.fromUri(audio.fileUri).exists(), isTrue);
      expect(audio.fileUri.path, isNot(endsWith('.part')));
      savedAudio.add(audio);
      return 'import:sha256:${audio.sha256}';
    },
    savePlaylist: (id, name, trackIds) async => playlists.add(List.of(trackIds)),
    loadJobs: () async => restoredJobs,
    saveJob: (job) async => savedJobs.add(job),
    now: () => DateTime.utc(2026, 10, 13),
  );

  void audio(Uri uri, List<int> bytes, {int status = 200, String type = 'audio/mpeg', int? declaredSize}) {
    transport.responses[uri.toString()] = () async => _response(uri, bytes, status: status, type: type, declaredSize: declaredSize);
  }
}

void main() {
  group('URL policy and manifest parsing', () {
    test('recognizes structured Spotify identifiers and ignores sharing query', () {
      final track = parseImportLink('https://open.spotify.com/track/0123456789abcdefghijkl?si=share');
      expect(track.kind, ImportLinkKind.spotifyTrack);
      expect(track.resourceId, '0123456789abcdefghijkl');
      expect(parseImportLink('https://open.spotify.com/intl-id/playlist/0123456789abcdefghijkl').kind, ImportLinkKind.spotifyPlaylist);
    });

    test('rejects cleartext, credentials, local hosts, IPs, and webpage inputs', () {
      for (final url in [
        'http://media.example.com/test.mp3',
        'https://user:secret@media.example.com/test.mp3',
        'https://localhost/test.mp3',
        'https://music.local/test.mp3',
        'https://127.0.0.1/test.mp3',
        'https://[::1]/test.mp3',
        'https://bad-.example.com/test.mp3',
        'https://open.spotify.com/artist/0123456789abcdefghijkl',
        'https://open.spotify.com/track/not-a-valid-id',
        'https://media.example.com/page',
        'https://media.example.com/test.mp3#fragment',
      ]) {
        expect(() => parseImportLink(url), throwsA(isA<ImportException>()), reason: url);
      }
    });

    test('keeps track order and provenance and rejects duplicate identity', () {
      final preview = parsePlaylistManifest(_manifest([_entry('second'), _entry('first')]), _manifestUrl);
      expect(preview.tracks.map((track) => track.id), ['second', 'first']);
      expect(preview.tracks.first.license, 'CC BY 4.0');
      expect(preview.tracks.first.source, contains('artist.example.com'));
      expect(() => parsePlaylistManifest(_manifest([_entry('same'), _entry('same')]), _manifestUrl), throwsA(isA<ImportException>()));
    });

    test('requires version, bounded entries, explicit source and license', () {
      for (final manifest in [
        jsonEncode({'version': 2, 'name': 'No', 'tracks': [_entry('one')]}),
        jsonEncode({'version': 1.0, 'name': 'No', 'tracks': [_entry('one')]}),
        _manifest([]),
        _manifest(List.generate(101, (index) => _entry('$index'))),
        _manifest([_entry('one')..remove('license')]),
        _manifest([_entry('one')..remove('source')]),
        _manifest([_entry('one')..['url'] = 'http://media.example.com/one.mp3']),
        _manifest([_entry('one', checksum: 'wrong')]),
        '{bad json',
      ]) {
        expect(() => parsePlaylistManifest(manifest, _manifestUrl), throwsA(isA<ImportException>()));
      }
    });
  });

  group('foreground importer', () {
    late Directory temporary;
    late _Harness harness;
    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('spomaxxing-import-test-');
      harness = _Harness(temporary);
    });
    tearDown(() async {
      await harness.service.dispose();
      await temporary.delete(recursive: true);
    });

    test('Spotify fails actionably without any network request', () async {
      await expectLater(harness.service.preview('https://open.spotify.com/track/0123456789abcdefghijkl'), throwsA(isA<ImportUnsupportedException>()));
      expect(harness.connectionChecks, 0);
      expect(harness.transport.requested, isEmpty);
    });

    test('direct URL requires permission and offline message is exact', () async {
      await expectLater(harness.service.preview(_audioUrl.toString()), throwsA(isA<ImportException>()));
      expect(harness.connectionChecks, 0);
      harness.connected = false;
      await expectLater(harness.service.preview(_audioUrl.toString(), directDownloadPermission: true), throwsA(isA<ImportOfflineException>().having((error) => error.message, 'alert', 'Tidak ada koneksi internet. Hubungkan ke internet untuk mengunduh lagu. Lagu yang sudah tersimpan tetap bisa diputar.')));
      expect(harness.transport.requested, isEmpty);
    });

    test('publishes a decoder-validated complete local file and stable hash', () async {
      final bytes = utf8.encode('synthetic permitted audio bytes');
      harness.audio(_audioUrl, bytes);
      final preview = await harness.service.preview(_audioUrl.toString(), directDownloadPermission: true);
      final job = await harness.service.download(preview);
      expect(job.status, ImportJobStatus.completed);
      expect(job.completedCount, 1);
      expect(harness.decoderChecks, 1);
      expect(harness.savedAudio.single.sha256, sha256.convert(bytes).toString());
      expect(await File.fromUri(harness.savedAudio.single.fileUri).readAsBytes(), bytes);
      expect(harness.playlists, isEmpty);
      expect(await temporary.list().where((file) => file.path.endsWith('.part')).isEmpty, isTrue);
    });

    test('partial playlist retains failures and source order', () async {
      final preview = parsePlaylistManifest(_manifest([_entry('first'), _entry('missing'), _entry('last')]), _manifestUrl);
      harness.audio(preview.tracks[0].url, [1, 2, 3]);
      harness.audio(preview.tracks[1].url, [], status: 404);
      harness.audio(preview.tracks[2].url, [4, 5, 6]);
      final job = await harness.service.download(preview);
      expect(job.status, ImportJobStatus.partial);
      expect(job.completedCount, 2);
      expect(job.tracks[1].status, ImportTrackStatus.failed);
      expect(job.tracks[1].error, contains('404'));
      expect(harness.playlists.last, [job.tracks[0].localTrackId, 'pending:${job.id}:missing', job.tracks[2].localTrackId]);
      expect(harness.playlists.last.length, 3);
      expect(harness.playlists.last.where((id) => id.startsWith('import:')).length, 2);
      expect(harness.savedJobs.last.toJson()['status'], 'partial');
      expect(ImportJob.fromJson(job.toJson()).tracks[1].error, contains('404'));
    });

    test('selecting a subset preserves manifest order', () async {
      final preview = parsePlaylistManifest(_manifest([_entry('first'), _entry('second'), _entry('third')]), _manifestUrl);
      harness.audio(preview.tracks[0].url, [1]);
      harness.audio(preview.tracks[2].url, [3]);
      final job = await harness.service.download(preview, selectedTrackIds: {'third', 'first'});
      expect(job.tracks.map((track) => track.candidate.id), ['first', 'third']);
      expect(harness.transport.requested, [preview.tracks[0].url, preview.tracks[2].url]);
    });

    test('rejects HTML, oversized responses, truncation and checksum mismatch before saving', () async {
      final previews = [
        parsePlaylistManifest(_manifest([_entry('html')]), _manifestUrl),
        parsePlaylistManifest(_manifest([_entry('big')]), _manifestUrl),
        parsePlaylistManifest(_manifest([_entry('short')]), _manifestUrl),
        parsePlaylistManifest(_manifest([_entry('checksum', checksum: List.filled(64, '0').join())]), _manifestUrl),
      ];
      harness.audio(previews[0].tracks.single.url, [1], type: 'text/html');
      harness.audio(previews[1].tracks.single.url, [1], declaredSize: maxAudioBytes + 1);
      harness.audio(previews[2].tracks.single.url, [1], declaredSize: 5);
      harness.audio(previews[3].tracks.single.url, [1]);
      for (final preview in previews) {
        final job = await harness.service.download(preview);
        expect(job.status, ImportJobStatus.failed);
      }
      expect(harness.savedAudio, isEmpty);
      expect(harness.decoderChecks, 0);
      expect(await temporary.list().isEmpty, isTrue);
    });

    test('enforces streamed size when Content-Length is absent', () async {
      final preview = parsePlaylistManifest(_manifest([_entry('chunked')]), _manifestUrl);
      harness.transport.responses[preview.tracks.single.url.toString()] = () async => ImportResponse(
        statusCode: 200, finalUri: preview.tracks.single.url, contentType: 'audio/mpeg',
        body: Stream.fromIterable([[1], _RepeatedByteChunk(maxAudioBytes)]),
      );
      final job = await harness.service.download(preview);
      expect(job.status, ImportJobStatus.failed);
      expect(job.tracks.single.error, contains('256 MiB'));
      expect(harness.savedAudio, isEmpty);
      expect(await temporary.list().isEmpty, isTrue);
    });

    test('never publishes an invalid decoder result', () async {
      harness.decoder = (_) async => {'durationMs': 0};
      harness.audio(_audioUrl, [1, 2]);
      final preview = await harness.service.preview(_audioUrl.toString(), directDownloadPermission: true);
      final job = await harness.service.download(preview);
      expect(job.status, ImportJobStatus.failed);
      expect(harness.savedAudio, isEmpty);
      expect(await temporary.list().isEmpty, isTrue);
    });

    test('rejects cleartext final URLs even from a fake transport', () async {
      harness.transport.responses[_audioUrl.toString()] = () async => _response(Uri.parse('http://media.example.com/test.mp3'), [1]);
      final preview = await harness.service.preview(_audioUrl.toString(), directDownloadPermission: true);
      expect((await harness.service.download(preview)).status, ImportJobStatus.failed);
      expect(harness.savedAudio, isEmpty);
    });

    test('disconnect pauses, removes partial bytes, and explicit retry starts fresh', () async {
      final preview = parsePlaylistManifest(_manifest([_entry('one'), _entry('two')]), _manifestUrl);
      harness.audio(preview.tracks[0].url, [1, 2]);
      harness.transport.responses[preview.tracks[1].url.toString()] = () async => ImportResponse(
        statusCode: 200, finalUri: preview.tracks[1].url, contentType: 'audio/mpeg',
        body: Stream<List<int>>.error(const SocketException('Disconnected')),
      );
      final paused = await harness.service.download(preview);
      expect(paused.status, ImportJobStatus.paused);
      expect(paused.tracks[0].status, ImportTrackStatus.completed);
      expect(paused.tracks[1].receivedBytes, 0);
      expect(harness.playlists.last, [paused.tracks[0].localTrackId, 'pending:${paused.id}:two']);
      expect(await temporary.list().where((file) => file.path.endsWith('.part')).isEmpty, isTrue);
      harness.audio(preview.tracks[1].url, [3, 4]);
      final retried = await harness.service.retry(paused);
      expect(retried.status, ImportJobStatus.completed);
      expect(harness.savedAudio.length, 2);
      expect(harness.transport.requested.where((uri) => uri == preview.tracks[0].url).length, 1);
      expect(harness.transport.requested.where((uri) => uri == preview.tracks[1].url).length, 2);
    });

    test('interrupted persisted jobs become paused without networking', () async {
      final preview = parsePlaylistManifest(_manifest([_entry('one')]), _manifestUrl);
      final now = DateTime.utc(2026, 10, 12);
      harness.restoredJobs = [ImportJob(
        id: 'interrupted', preview: preview, createdAt: now, updatedAt: now, status: ImportJobStatus.downloading,
        tracks: [ImportTrackProgress(candidate: preview.tracks.single, status: ImportTrackStatus.downloading, receivedBytes: 100, totalBytes: 200)],
      )];
      await harness.service.initialize();
      expect(harness.service.jobs.single.status, ImportJobStatus.paused);
      expect(harness.service.jobs.single.tracks.single.receivedBytes, 0);
      expect(harness.connectionChecks, 0);
      expect(harness.transport.requested, isEmpty);
    });

    test('cancellation during validation removes temporary file and preserves failure status', () async {
      harness.decoder = (_) async { harness.service.cancel(); return {'durationMs': 1}; };
      harness.audio(_audioUrl, [1, 2, 3]);
      final preview = await harness.service.preview(_audioUrl.toString(), directDownloadPermission: true);
      final job = await harness.service.download(preview);
      expect(job.status, ImportJobStatus.cancelled);
      expect(job.tracks.single.status, ImportTrackStatus.cancelled);
      expect(harness.savedAudio, isEmpty);
      expect(await temporary.list().isEmpty, isTrue);
    });
  });
}
