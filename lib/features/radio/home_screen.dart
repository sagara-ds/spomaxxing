import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/models/track.dart';
import '../../core/radio/radio_mixer.dart';
import '../../data/library_repository.dart';
import '../library/library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, required this.onAction});
  final AppController controller;
  final AppAction onAction;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _mood = 'santai';
  RadioMix? _mix;
  List<Track>? _catalogue;

  void _refresh() {
    _catalogue = widget.controller.tracks;
    _mix = widget.controller.radio(_mood);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!identical(_catalogue, controller.tracks)) _refresh();
    final mix = _mix!;
    final seen = <String>{};
    final recent = controller.player.state.historyTracks.reversed
        .where((track) => seen.add(track.id)).take(5).toList();
    final favorites = controller.tracks.where((track) => track.isFavorite).take(5).toList();
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Musik untuk suasanamu', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Koleksi dan radio lokal siap diputar tanpa internet.'),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final mood in MoodCatalog.moods)
              ChoiceChip(label: Text(mood), selected: mood == _mood,
                onSelected: (_) => setState(() { _mood = mood; _refresh(); })),
          ]),
          const SizedBox(height: 20),
          Text('Radio $_mood', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(mix.isEmpty
            ? 'Belum ada lagu dengan tag $_mood. Tambahkan tag melalui Koleksi untuk membuat mix.'
            : '${mix.tracks.length} lagu unik tersedia offline'
              '${mix.hasFewerThanTarget ? '. Mix memakai seluruh kandidat yang tersedia.' : '.'}'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: mix.isEmpty ? null : () => widget.onAction(
              () => controller.playTracks(mix.tracks)),
              icon: const Icon(Icons.play_arrow), label: const Text('Putar mix')),
            OutlinedButton.icon(onPressed: () => setState(_refresh),
              icon: const Icon(Icons.shuffle), label: const Text('Mix baru')),
            OutlinedButton.icon(onPressed: mix.isEmpty ? null : () => widget.onAction(() async {
              await controller.repository.savePlaylist(LocalPlaylist(
                id: 'playlist:mix:${DateTime.now().microsecondsSinceEpoch}',
                name: 'Mix $_mood', trackIds: mix.tracks.map((track) => track.id).toList()));
              await controller.reload();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mix tersimpan di Koleksi.')));
              }
            }), icon: const Icon(Icons.playlist_add), label: const Text('Simpan mix')),
          ]),
        ],
      )),
      if (!mix.isEmpty)
        ExpansionTile(title: const Text('Lagu dalam mix'), children: [
          SizedBox(height: min(400.0, mix.tracks.length * 100.0), child: LibraryView(tracks: mix.tracks,
            explanations: {for (final track in mix.tracks) track.id: mix.explanationFor(track.id)},
            onPlay: (index) => widget.onAction(() => controller.playTracks(mix.tracks, startIndex: index)))),
        ]),
      if (recent.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.all(16), child: Text('Terakhir diputar')),
        SizedBox(height: min(400.0, recent.length * 100.0), child: LibraryView(tracks: recent, onPlay: (index) => widget.onAction(
          () => controller.playTracks(recent, startIndex: index)))),
      ],
      if (favorites.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.all(16), child: Text('Favorit')),
        SizedBox(height: min(400.0, favorites.length * 100.0), child: LibraryView(tracks: favorites, onPlay: (index) => widget.onAction(
          () => controller.playTracks(favorites, startIndex: index)))),
      ],
      if (controller.playlists.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.all(16), child: Text('Playlist tersimpan')),
        for (final playlist in controller.playlists.take(5))
          ListTile(leading: const Icon(Icons.queue_music), title: Text(playlist.name),
            subtitle: Text('${playlist.trackIds.length} lagu'),
            onTap: () => widget.onAction(() => controller.playPlaylist(playlist))),
      ],
    ]);
  }
}
