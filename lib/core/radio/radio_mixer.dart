import 'dart:math';

import '../models/track.dart';

/// Aliases are applied to user-supplied tags, never inferred from metadata.
abstract final class MoodCatalog {
  static const moods = ['santai', 'fokus', 'sedih', 'semangat', 'bahagia', 'tidur'];

  static const aliases = <String, String>{
    'santai': 'santai',
    'tenang': 'santai',
    'chill': 'santai',
    'relax': 'santai',
    'relaxed': 'santai',
    'fokus': 'fokus',
    'focus': 'fokus',
    'konsentrasi': 'fokus',
    'sedih': 'sedih',
    'sad': 'sedih',
    'melankolis': 'sedih',
    'semangat': 'semangat',
    'energi': 'semangat',
    'energetic': 'semangat',
    'workout': 'semangat',
    'bahagia': 'bahagia',
    'senang': 'bahagia',
    'happy': 'bahagia',
    'tidur': 'tidur',
    'sleep': 'tidur',
    'sleepy': 'tidur',
  };

  static String normalize(String tag) {
    final value = tag.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return aliases[value] ?? value;
  }

  static bool isMood(String query) => moods.contains(normalize(query));

  static Set<String> normalizeTags(Iterable<String> tags) => tags
      .map(normalize)
      .where((tag) => tag.isNotEmpty)
      .toSet();
}

class RadioMix {
  RadioMix._({
    required Iterable<Track> tracks,
    required Iterable<String> requestedTags,
    required Map<String, List<String>> reasons,
    required this.candidateCount,
    required this.targetSize,
  }) : tracks = List.unmodifiable(tracks),
       requestedTags = Set.unmodifiable(requestedTags),
       reasons = Map.unmodifiable({
         for (final entry in reasons.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });

  final List<Track> tracks;
  final Set<String> requestedTags;
  final Map<String, List<String>> reasons;
  final int candidateCount;
  final int targetSize;

  bool get isEmpty => tracks.isEmpty;
  bool get hasFewerThanTarget => candidateCount < targetSize;

  String explanationFor(String trackId) {
    final tags = reasons[trackId];
    return tags == null || tags.isEmpty ? '' : 'Tag: ${tags.join(', ')}';
  }
}

abstract final class RadioMixer {
  /// Builds one finite mix from accessible local files with explicit tags.
  static RadioMix create(
    Iterable<Track> tracks, {
    String? mood,
    Track? seedTrack,
    int seed = 0,
    int limit = 25,
  }) {
    if (limit < 1) throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    final targetSize = min(limit, 25);
    final catalogue = {for (final track in tracks) track.id: track};
    // Prefer the current catalogue over a potentially stale UI selection.
    final initialTrack = seedTrack == null
        ? null
        : catalogue[seedTrack.id] ?? seedTrack;
    final seedTags = initialTrack == null
        ? <String>{}
        : MoodCatalog.normalizeTags(initialTrack.tags);
    final primary = mood == null ? null : MoodCatalog.normalize(mood);
    final requested = <String>{
      if (primary != null && primary.isNotEmpty) primary,
      ...seedTags,
    };
    RadioMix empty() => RadioMix._(
      tracks: [],
      requestedTags: requested,
      reasons: {},
      candidateCount: 0,
      targetSize: targetSize,
    );
    if (requested.isEmpty) return empty();
    if (initialTrack != null &&
        (!initialTrack.isAvailable || seedTags.isEmpty)) {
      return empty();
    }
    if (initialTrack != null) catalogue[initialTrack.id] = initialTrack;

    final random = Random(seed);
    final candidates = <_Candidate>[];
    for (final track in catalogue.values) {
      if (!track.isAvailable) continue;
      final tags = MoodCatalog.normalizeTags(track.tags);
      if (primary != null && primary.isNotEmpty && !tags.contains(primary)) {
        // The seed always leads a track-based mix, even with an extra mood filter.
        if (track.id != initialTrack?.id) continue;
      }
      final matches = tags.intersection(requested).toList()..sort();
      if (matches.isEmpty) continue;
      candidates.add(
        _Candidate(
          track,
          matches,
          matches.length + (primary != null && tags.contains(primary) ? 100 : 0),
          random.nextDouble(),
        ),
      );
    }
    candidates.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final shuffled = a.tieBreaker.compareTo(b.tieBreaker);
      return shuffled != 0 ? shuffled : a.track.id.compareTo(b.track.id);
    });

    final count = candidates.length;
    final selected = <_Candidate>[];
    if (initialTrack != null) {
      final index = candidates.indexWhere((item) => item.track.id == initialTrack.id);
      if (index >= 0) selected.add(candidates.removeAt(index));
    }
    while (selected.length < targetSize && candidates.isNotEmpty) {
      final lastArtist = selected.isEmpty
          ? null
          : selected.last.track.artist.toLowerCase().trim();
      // Keep relevance groups ordered; prefer a different artist within a group.
      final bestScore = candidates.first.score;
      final artistCounts = <String, int>{};
      for (final item in candidates.where((item) => item.score == bestScore)) {
        final artist = item.track.artist.toLowerCase().trim();
        artistCounts.update(artist, (count) => count + 1, ifAbsent: () => 1);
      }
      var index = -1;
      var largestCount = 0;
      for (var i = 0; i < candidates.length; i++) {
        final item = candidates[i];
        if (item.score != bestScore) break;
        final artist = item.track.artist.toLowerCase().trim();
        final count = artistCounts[artist]!;
        if (artist != lastArtist && count > largestCount) {
          index = i;
          largestCount = count;
        }
      }
      if (index < 0) index = 0;
      selected.add(candidates.removeAt(index));
    }
    return RadioMix._(
      tracks: selected.map((item) => item.track),
      requestedTags: requested,
      reasons: {for (final item in selected) item.track.id: item.matches},
      candidateCount: count,
      targetSize: targetSize,
    );
  }
}

class _Candidate {
  const _Candidate(this.track, this.matches, this.score, this.tieBreaker);

  final Track track;
  final List<String> matches;
  final int score;
  final double tieBreaker;
}
