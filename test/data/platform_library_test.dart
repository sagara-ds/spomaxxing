import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/data/platform_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.spomaxxing/library');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late PlatformLibrary library;
  late List<MethodCall> calls;

  Map<String, Object?> nativeTrack({String id = 'media:external:42'}) => {
    'id': id,
    'uri': 'content://media/external/audio/media/42',
    'title': 'Lagu lokal',
    'artist': 'Artis lokal',
    'album': 'Album lokal',
    'durationMs': 120000,
    'genre': 'Pop',
    'isAvailable': true,
  };

  void replyWith(Object? response) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  }

  setUp(() {
    library = PlatformLibrary(channel: channel);
    calls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('requests permission through the injected channel', () async {
    replyWith(true);

    expect(await library.requestAudioPermission(), isTrue);
    expect(calls.single.method, 'requestAudioPermission');
    expect(calls.single.arguments, isNull);
  });

  test('permission denial remains false', () async {
    replyWith(false);

    expect(await library.requestAudioPermission(), isFalse);
  });

  test('rejects malformed boolean responses', () async {
    replyWith('true');

    await expectLater(library.requestAudioPermission(), throwsFormatException);
    await expectLater(library.hasConnection(), throwsFormatException);
  });

  test('maps scanned native audio into tracks', () async {
    replyWith([nativeTrack()]);

    final tracks = await library.scanAudio();

    expect(tracks.single.id, 'media:external:42');
    expect(tracks.single.title, 'Lagu lokal');
    expect(tracks.single.durationMs, 120000);
    expect(tracks.single.isAvailable, isTrue);
    expect(calls.single.method, 'scanAudio');
    expect(() => tracks.clear(), throwsUnsupportedError);
  });

  test('rejects malformed scan payloads with explicit format errors', () async {
    for (final response in <Object?>[
      null,
      'audio',
      [42],
      [nativeTrack()..['durationMs'] = '120000'],
      [nativeTrack()..['durationMs'] = -1],
      [nativeTrack()..['uri'] = 'https://example.com/audio.mp3'],
      [nativeTrack()..['tags'] = ['pop', 42]],
    ]) {
      replyWith(response);
      await expectLater(library.scanAudio(), throwsFormatException);
    }
  });

  test('picker preserves successes and individual import errors', () async {
    replyWith({
      'tracks': [nativeTrack(id: 'import:local-id')],
      'errors': ['broken.mp3: Audio cannot be opened'],
    });

    final picked = await library.pickAudio();

    expect(picked.tracks.single.id, 'import:local-id');
    expect(picked.errors, ['broken.mp3: Audio cannot be opened']);
    expect(calls.single.method, 'pickAudio');
    expect(() => picked.errors.clear(), throwsUnsupportedError);
  });

  test('picker cancellation returns empty tracks and errors', () async {
    replyWith({'tracks': [], 'errors': []});

    final picked = await library.pickAudio();

    expect(picked.tracks, isEmpty);
    expect(picked.errors, isEmpty);
  });

  test('picker rejects malformed errors and missing tracks', () async {
    for (final response in <Object?>[
      null,
      {'tracks': [], 'errors': [42]},
      {'tracks': [], 'errors': 'Import failed'},
      {'errors': []},
    ]) {
      replyWith(response);
      await expectLater(library.pickAudio(), throwsFormatException);
    }
  });

  test('platform errors retain their original code and details', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'permission_denied',
        message: 'Permission is required',
        details: {'uri': 'content://audio/42'},
      );
    });

    await expectLater(
      library.scanAudio(),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'permission_denied')
            .having((error) => error.details, 'details', {
              'uri': 'content://audio/42',
            }),
      ),
    );
  });

  test('validateAudio sends URI and returns native metadata', () async {
    replyWith({
      'durationMs': 4500,
      'title': 'Audio terpilih',
      'artist': 'Artis',
      'album': '',
    });

    final metadata = await library.validateAudio('file:///private/audio.mp3');

    expect(metadata['durationMs'], 4500);
    expect(metadata['title'], 'Audio terpilih');
    expect(calls.single.method, 'validateAudio');
    expect(calls.single.arguments, {'uri': 'file:///private/audio.mp3'});
  });

  test('validateAudio rejects values without string-keyed metadata', () async {
    for (final response in <Object?>[null, [], {42: 'title'}]) {
      replyWith(response);
      await expectLater(
        library.validateAudio('content://audio/42'),
        throwsFormatException,
      );
    }
  });

  test('reads current connection status', () async {
    replyWith(false);

    expect(await library.hasConnection(), isFalse);
    expect(calls.single.method, 'hasConnection');
  });

  test('maps storage capacity and imported audio size', () async {
    replyWith({
      'bytesAvailable': 600,
      'bytesTotal': 1000,
      'importedBytes': 75,
    });

    final storage = await library.storageInfo();

    expect(storage.bytesAvailable, 600);
    expect(storage.freeBytes, 600);
    expect(storage.bytesTotal, 1000);
    expect(storage.importedBytes, 75);
    expect(calls.single.method, 'storageInfo');
  });

  test('accepts native freeBytes and totalBytes storage aliases', () async {
    replyWith({'freeBytes': 600, 'totalBytes': 1000});

    final storage = await library.storageInfo();

    expect(storage.bytesAvailable, 600);
    expect(storage.bytesTotal, 1000);
    expect(storage.importedBytes, 0);
  });

  test('rejects malformed or impossible storage capacity', () async {
    for (final response in <Object?>[
      {'bytesAvailable': -1, 'bytesTotal': 1000},
      {'bytesAvailable': '600', 'bytesTotal': 1000},
      {'bytesAvailable': 600, 'bytesTotal': 500},
      {'bytesAvailable': 600, 'bytesTotal': 1000, 'importedBytes': -1},
      {'bytesAvailable': 600},
    ]) {
      replyWith(response);
      await expectLater(library.storageInfo(), throwsFormatException);
    }
  });
}
