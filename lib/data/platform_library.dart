import 'package:flutter/services.dart';

import '../core/models/track.dart';

/// The result of importing audio, including failures for individual selections.
class PickAudioResult {
  PickAudioResult({required List<Track> tracks, required List<String> errors})
    : tracks = List.unmodifiable(tracks),
      errors = List.unmodifiable(errors);

  final List<Track> tracks;
  final List<String> errors;
}

class StorageInfo {
  const StorageInfo({
    required this.bytesAvailable,
    required this.bytesTotal,
    this.importedBytes = 0,
  });

  final int bytesAvailable;
  final int bytesTotal;
  final int importedBytes;

  int get freeBytes => bytesAvailable;
}

/// Typed boundary for the Android audio library bridge.
///
/// Platform exceptions retain their original codes and details. Invalid native
/// payloads fail with a [FormatException] naming the affected operation.
class PlatformLibrary {
  const PlatformLibrary({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.spomaxxing/library');

  final MethodChannel _channel;

  Future<bool> requestAudioPermission() async => _boolean(
    await _channel.invokeMethod<Object?>('requestAudioPermission'),
    'requestAudioPermission',
  );

  Future<List<Track>> scanAudio() async => _tracks(
    await _channel.invokeMethod<Object?>('scanAudio'),
    'scanAudio',
  );

  Future<PickAudioResult> pickAudio() async {
    final result = _stringKeyedMap(
      await _channel.invokeMethod<Object?>('pickAudio'),
      'pickAudio',
    );
    final errors = result['errors'];
    if (errors is! List || errors.any((error) => error is! String)) {
      throw const FormatException('pickAudio.errors must be a list of strings.');
    }
    return PickAudioResult(
      tracks: _tracks(result['tracks'], 'pickAudio.tracks'),
      errors: errors.cast<String>(),
    );
  }

  Future<Map<String, dynamic>> validateAudio(String uri) async =>
      Map.unmodifiable(
        _stringKeyedMap(
          await _channel.invokeMethod<Object?>('validateAudio', {'uri': uri}),
          'validateAudio',
        ),
      );

  Future<bool> hasConnection() async => _boolean(
    await _channel.invokeMethod<Object?>('hasConnection'),
    'hasConnection',
  );

  Future<StorageInfo> storageInfo() async {
    final result = _stringKeyedMap(
      await _channel.invokeMethod<Object?>('storageInfo'),
      'storageInfo',
    );
    final available = _nonnegativeInteger(
      result['bytesAvailable'] ?? result['freeBytes'],
      'storageInfo.bytesAvailable',
    );
    final total = _nonnegativeInteger(
      result['bytesTotal'] ?? result['totalBytes'],
      'storageInfo.bytesTotal',
    );
    final imported = _nonnegativeInteger(
      result['importedBytes'] ?? 0,
      'storageInfo.importedBytes',
    );
    if (available > total) {
      throw const FormatException(
        'storageInfo.bytesAvailable cannot exceed bytesTotal.',
      );
    }
    return StorageInfo(
      bytesAvailable: available,
      bytesTotal: total,
      importedBytes: imported,
    );
  }

  static bool _boolean(Object? value, String context) {
    if (value is! bool) {
      throw FormatException('$context must return a boolean.');
    }
    return value;
  }

  static int _nonnegativeInteger(Object? value, String context) {
    if (value is! int || value < 0) {
      throw FormatException('$context must be a nonnegative integer.');
    }
    return value;
  }

  static Map<String, dynamic> _stringKeyedMap(Object? value, String context) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw FormatException('$context must return a map with string keys.');
    }
    return Map<String, dynamic>.from(value);
  }

  static List<Track> _tracks(Object? value, String context) {
    if (value is! List) {
      throw FormatException('$context must return a list of tracks.');
    }
    return List.unmodifiable([
      for (var index = 0; index < value.length; index++)
        _track(value[index], '$context[$index]'),
    ]);
  }

  static Track _track(Object? value, String context) {
    final json = _stringKeyedMap(value, context);
    for (final field in ['id', 'uri']) {
      if (json[field] is! String) {
        throw FormatException('$context.$field must be a string.');
      }
    }
    for (final field in [
      'title',
      'artist',
      'album',
      'genre',
      'artworkUri',
    ]) {
      if (json[field] != null && json[field] is! String) {
        throw FormatException('$context.$field must be a string or null.');
      }
    }
    if (json['durationMs'] != null) {
      _nonnegativeInteger(json['durationMs'], '$context.durationMs');
    }
    for (final field in ['isFavorite', 'isAvailable']) {
      if (json[field] != null && json[field] is! bool) {
        throw FormatException('$context.$field must be a boolean or null.');
      }
    }
    final tags = json['tags'];
    if (tags != null && (tags is! List || tags.any((tag) => tag is! String))) {
      throw FormatException('$context.tags must be a list of strings or null.');
    }
    try {
      return Track.fromJson(json);
    } on ArgumentError catch (error) {
      throw FormatException('$context contains invalid audio: ${error.message}');
    }
  }
}
