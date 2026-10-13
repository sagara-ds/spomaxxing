import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/models/track.dart';
import '../../core/radio/radio_mixer.dart';

typedef AppAction = Future<void> Function(Future<void> Function());

class TrackCover extends StatelessWidget {
  const TrackCover({super.key, required this.track, this.size = 48});
  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: size * .5),
    );
    final uri = Uri.tryParse(track.artworkUri ?? '');
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: uri?.scheme == 'file'
            ? Image.file(File.fromUri(uri!), fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback)
            : fallback,
      ),
    );
  }
}

/// A platform-independent list, also used by search and radio previews.
class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.tracks,
    required this.onPlay,
    this.onFavorite,
    this.onEditTags,
    this.onRadio,
    this.selectedIds,
    this.onSelection,
    this.explanations = const {},
    this.emptyMessage = 'Belum ada lagu. Pindai perangkat atau tambahkan berkas audio.',
  });

  final List<Track> tracks;
  final ValueChanged<int> onPlay;
  final ValueChanged<Track>? onFavorite;
  final ValueChanged<Track>? onEditTags;
  final ValueChanged<Track>? onRadio;
  final Set<String>? selectedIds;
  final ValueChanged<Track>? onSelection;
  final Map<String, String> explanations;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(emptyMessage, textAlign: TextAlign.center),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < tracks.length; index++)
          ListTile(
            key: ValueKey('track:${tracks[index].id}'),
            leading: selectedIds == null
                ? TrackCover(track: tracks[index])
                : Checkbox(
                    value: selectedIds!.contains(tracks[index].id),
                    onChanged: (_) => onSelection?.call(tracks[index]),
                    semanticLabel: 'Pilih ${tracks[index].title}',
                  ),
            title: Text(tracks[index].title),
            subtitle: Text([
              tracks[index].artist,
              if (tracks[index].album.isNotEmpty) tracks[index].album,
              if (!tracks[index].isAvailable) 'Berkas tidak tersedia · pindai ulang',
              if (explanations[tracks[index].id]?.isNotEmpty ?? false)
                explanations[tracks[index].id]!,
              if (tracks[index].tags.isNotEmpty)
                tracks[index].tags.join(' · '),
            ].join('\n')),
            isThreeLine: false,
            onTap: selectedIds != null
                ? () => onSelection?.call(tracks[index])
                : tracks[index].isAvailable ? () => onPlay(index) : null,
            onLongPress: onSelection == null ? null : () => onSelection!(tracks[index]),
            trailing: onFavorite == null && onEditTags == null && onRadio == null
                ? null
                : PopupMenuButton<String>(
                    tooltip: 'Pilihan ${tracks[index].title}',
                    onSelected: (value) {
                      if (value == 'favorite') onFavorite?.call(tracks[index]);
                      if (value == 'tags') onEditTags?.call(tracks[index]);
                      if (value == 'radio') onRadio?.call(tracks[index]);
                    },
                    itemBuilder: (_) => [
                      if (onFavorite != null)
                        PopupMenuItem(value: 'favorite', child: Text(
                          tracks[index].isFavorite ? 'Hapus dari favorit' : 'Tambah favorit')),
                      if (onEditTags != null)
                        const PopupMenuItem(value: 'tags', child: Text('Edit tag suasana')),
                      if (onRadio != null && tracks[index].tags.isNotEmpty && tracks[index].isAvailable)
                        const PopupMenuItem(value: 'radio', child: Text('Radio dari lagu ini')),
                    ],
                  ),
          ),
      ],
    );
  }
}

Future<void> editTrackTags(
  BuildContext context, AppController controller, List<Track> tracks, AppAction onAction,
) async {
  if (tracks.isEmpty) return;
  final tags = tracks.first.tags.map(MoodCatalog.normalize).toSet();
  final custom = TextEditingController(text: tags
      .where((tag) => !MoodCatalog.moods.contains(tag)).join(', '));
  try {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
        title: Text(tracks.length == 1 ? 'Tag ${tracks.first.title}' : 'Tag ${tracks.length} lagu'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tracks.length > 1)
              const Text('Pilihan ini mengganti tag pada semua lagu terpilih.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final mood in MoodCatalog.moods)
                FilterChip(label: Text(mood), selected: tags.contains(mood),
                  onSelected: (selected) => setState(() {
                    if (selected) { tags.add(mood); } else { tags.remove(mood); }
                  })),
            ]),
            const SizedBox(height: 12),
            TextField(controller: custom, decoration: const InputDecoration(
              labelText: 'Tag lain', helperText: 'Pisahkan dengan koma')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, {
            ...tags.where(MoodCatalog.moods.contains),
            ...custom.text.split(',').map(MoodCatalog.normalize).where((tag) => tag.isNotEmpty),
          }), child: const Text('Simpan')),
        ],
      )),
    );
    if (result != null) await onAction(() => controller.setTags(tracks, result));
  } finally {
    custom.dispose();
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller, required this.onAction});
  final AppController controller;
  final AppAction onAction;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _filter = 'Lagu';
  bool _selecting = false;
  final _selected = <String>{};

  void _select(Track track) => setState(() {
    _selecting = true;
    if (!_selected.add(track.id)) _selected.remove(track.id);
  });

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tracks = _filter == 'Favorit'
        ? controller.tracks.where((track) => track.isFavorite).toList()
        : controller.tracks;
    final groups = <String, List<Track>>{};
    if (_filter == 'Album' || _filter == 'Artis') {
      for (final track in tracks) {
        final key = _filter == 'Artis' ? track.artist
            : track.album.isEmpty ? 'Album tidak diketahui' : track.album;
        groups.putIfAbsent(key, () => []).add(track);
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: controller.busy ? null : () => widget.onAction(controller.scan),
          icon: const Icon(Icons.refresh), label: const Text('Pindai perangkat')),
        OutlinedButton.icon(onPressed: controller.busy ? null : () => widget.onAction(controller.pickAudio),
          icon: const Icon(Icons.audio_file), label: const Text('Tambah berkas')),
      ])),
      if (controller.permissionDenied)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text(
          'Izin audio belum diberikan. Tekan Pindai perangkat untuk meminta izin lagi, '
          'atau gunakan Tambah berkas. Jika izin diblokir, aktifkan melalui pengaturan Android.')),
      if (controller.busy) const LinearProgressIndicator(semanticsLabel: 'Memuat koleksi'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, children: [
        for (final filter in ['Lagu', 'Favorit', 'Album', 'Artis', 'Playlist'])
          ChoiceChip(label: Text(filter), selected: _filter == filter,
            onSelected: (_) => setState(() { _filter = filter; _selecting = false; _selected.clear(); })),
      ])),
      if (_filter == 'Lagu' || _filter == 'Favorit')
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, children: [
          TextButton.icon(icon: Icon(_selecting ? Icons.close : Icons.checklist),
            label: Text(_selecting ? 'Selesai memilih' : 'Pilih lagu'),
            onPressed: () => setState(() { _selecting = !_selecting; _selected.clear(); })),
          if (_selecting)
            TextButton(onPressed: _selected.isEmpty ? null : () => editTrackTags(
              context, controller, controller.tracks.where((track) => _selected.contains(track.id)).toList(),
              widget.onAction), child: Text('Edit tag (${_selected.length})')),
        ])),
      if (_filter == 'Playlist') ...[
        if (controller.playlists.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('Belum ada playlist. Simpan radio mix dari Beranda.')),
        for (final playlist in controller.playlists)
          ListTile(leading: const Icon(Icons.queue_music), title: Text(playlist.name),
            subtitle: Text('${playlist.trackIds.length} lagu · '
              '${playlist.trackIds.where((id) => controller.tracks.any((track) => track.id == id && track.isAvailable)).length} tersedia offline'),
            onTap: () => widget.onAction(() => controller.playPlaylist(playlist)),
            trailing: IconButton(tooltip: 'Hapus playlist ${playlist.name}', icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final remove = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
                  title: const Text('Hapus playlist?'), content: Text(playlist.name), actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
                  ]));
                if (remove == true) await widget.onAction(() async {
                  await controller.repository.deletePlaylist(playlist.id); await controller.reload();
                });
              })),
      ] else if (groups.isNotEmpty) ...[
        for (final entry in groups.entries)
          ExpansionTile(title: Text(entry.key), subtitle: Text('${entry.value.length} lagu'),
            children: [LibraryView(tracks: entry.value,
              onPlay: (index) => widget.onAction(() => controller.playTracks(entry.value, startIndex: index)),
              onEditTags: (track) => editTrackTags(context, controller, [track], widget.onAction))]),
      ] else
        LibraryView(tracks: tracks,
          emptyMessage: _filter == 'Favorit' ? 'Belum ada lagu favorit.'
            : 'Belum ada lagu. Pindai perangkat atau tambahkan berkas audio.',
          selectedIds: _selecting ? _selected : null, onSelection: _select,
          onPlay: (index) => widget.onAction(() => controller.playTracks(tracks, startIndex: index)),
          onFavorite: (track) => widget.onAction(() => controller.toggleFavorite(track)),
          onRadio: (track) => widget.onAction(() async {
            await controller.playRadio(MoodCatalog.normalize(track.tags.first), seed: track);
          }),
          onEditTags: (track) => editTrackTags(context, controller, [track], widget.onAction)),
    ]);
  }
}
