import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/radio/radio_mixer.dart';
import '../library/library_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller, required this.onAction});
  final AppController controller;
  final AppAction onAction;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() { _query.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final query = _query.text.trim().toLowerCase();
    final mood = MoodCatalog.normalize(query);
    final tracks = controller.tracks.where((track) => query.isEmpty ||
      [track.title, track.artist, track.album].any((text) => text.toLowerCase().contains(query)) ||
      MoodCatalog.normalizeTags(track.tags).contains(mood)).toList();
    return CustomScrollView(slivers: [SliverToBoxAdapter(child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(
        controller: _query, onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: 'Cari lagu, artis, album, atau tag',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(tooltip: 'Hapus pencarian', icon: const Icon(Icons.clear),
            onPressed: () => setState(_query.clear))),
      )),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, children: [
        for (final mood in MoodCatalog.moods)
          ActionChip(label: Text(mood), onPressed: () => setState(() { _query.text = mood; })),
      ])),
      if (MoodCatalog.isMood(query))
        Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(
          onPressed: () => widget.onAction(() async {
            final mix = await controller.playRadio(query);
            if (mix.isEmpty && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Belum ada tag yang cocok. Edit tag di Koleksi.')));
            }
          }), icon: const Icon(Icons.radio), label: Text('Putar radio $mood'))),
      ])),
      LibraryView(sliver: true, tracks: tracks,
        emptyMessage: query.isEmpty ? 'Koleksi masih kosong. Tambahkan berkas melalui Koleksi.'
          : 'Tidak ada hasil untuk pencarian ini.',
        onPlay: (index) => widget.onAction(() => controller.playTracks(tracks, startIndex: index)),
        onFavorite: (track) => widget.onAction(() => controller.toggleFavorite(track)),
        onEditTags: (track) => editTrackTags(context, controller, [track], widget.onAction)),
    ]);
  }
}
