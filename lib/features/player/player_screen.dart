import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/queue/queue.dart';
import '../library/library_screen.dart';

String formatPlaybackTime(int milliseconds) {
  final seconds = max(0, milliseconds) ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller, required this.onAction});
  final AppController controller;
  final AppAction onAction;

  @override
  Widget build(BuildContext context) {
    final player = controller.player;
    final track = player.state.currentTrack;
    if (track == null) return const SizedBox.shrink();
    return Material(color: Theme.of(context).colorScheme.surfaceContainer, child: ListTile(
      leading: TrackCover(track: track),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
        PlayerScreen(controller: controller, onAction: onAction))),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: player.state.isPlaying ? 'Jeda' : 'Putar',
          icon: Icon(player.state.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () => onAction(player.playPause)),
        IconButton(tooltip: 'Lagu berikutnya', icon: const Icon(Icons.skip_next),
          onPressed: () => onAction(player.next)),
      ]),
    ));
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.controller, required this.onAction});
  final AppController controller;
  final AppAction onAction;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.controller.player]),
    builder: (context, _) {
      final controller = widget.controller;
      final player = controller.player;
      final state = player.state;
      final queued = state.currentTrack;
      final track = queued == null ? null : controller.tracks
          .where((track) => track.id == queued.id).firstOrNull ?? queued;
      final total = player.duration.inMilliseconds > 0
          ? player.duration.inMilliseconds : track?.durationMs ?? 0;
      final position = (_dragMs ?? state.positionMs.toDouble())
          .clamp(0, max(1, total)).toDouble();
      return Scaffold(
        appBar: AppBar(title: const Text('Sedang diputar'), actions: [
          IconButton(tooltip: 'Lihat antrean', icon: const Icon(Icons.queue_music),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
              QueueScreen(controller: controller, onAction: widget.onAction)))),
        ]),
        body: track == null
            ? const Center(child: Text('Pilih lagu dari Koleksi untuk mulai memutar.'))
            : ListView(padding: const EdgeInsets.all(24), children: [
                Center(child: TrackCover(track: track,
                  size: min(280, MediaQuery.sizeOf(context).width - 48))),
                const SizedBox(height: 24),
                Text(track.title, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(track.artist, textAlign: TextAlign.center),
                if (track.album.isNotEmpty)
                  Text(track.album, textAlign: TextAlign.center),
                if (player.isLoading) const Padding(padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(semanticsLabel: 'Menyiapkan audio lokal')),
                if (player.error != null) Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(player.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 16),
                Slider(value: position, max: max(1, total).toDouble(),
                  label: formatPlaybackTime(position.toInt()),
                  semanticFormatterCallback: (value) => formatPlaybackTime(value.toInt()),
                  onChanged: total == 0 ? null : (value) => setState(() => _dragMs = value),
                  onChangeEnd: total == 0 ? null : (value) => widget.onAction(() async {
                    await player.seek(Duration(milliseconds: value.toInt()));
                    if (mounted) setState(() => _dragMs = null);
                  })),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(formatPlaybackTime(position.toInt())),
                  Text(formatPlaybackTime(total)),
                ]),
                const SizedBox(height: 16),
                Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
                  IconButton(tooltip: state.shuffleEnabled ? 'Matikan shuffle' : 'Aktifkan shuffle',
                    isSelected: state.shuffleEnabled, icon: const Icon(Icons.shuffle),
                    onPressed: () => widget.onAction(player.toggleShuffle)),
                  IconButton(tooltip: 'Lagu sebelumnya', icon: const Icon(Icons.skip_previous),
                    onPressed: () => widget.onAction(player.previous)),
                  FilledButton.tonalIcon(onPressed: () => widget.onAction(player.playPause),
                    icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(state.isPlaying ? 'Jeda' : 'Putar')),
                  IconButton(tooltip: 'Lagu berikutnya', icon: const Icon(Icons.skip_next),
                    onPressed: () => widget.onAction(player.next)),
                  IconButton(tooltip: switch (state.repeatMode) {
                    RepeatMode.off => 'Repeat mati. Aktifkan repeat satu lagu',
                    RepeatMode.one => 'Repeat satu lagu. Aktifkan repeat antrean',
                    RepeatMode.all => 'Repeat antrean. Matikan repeat',
                  }, isSelected: state.repeatMode != RepeatMode.off,
                    icon: Icon(state.repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat),
                    onPressed: () => widget.onAction(player.cycleRepeat)),
                ]),
                const SizedBox(height: 16),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(icon: Icon(track.isFavorite ? Icons.favorite : Icons.favorite_border),
                    label: Text(track.isFavorite ? 'Favorit' : 'Tambah favorit'),
                    onPressed: () => widget.onAction(() => controller.toggleFavorite(track))),
                  OutlinedButton.icon(icon: const Icon(Icons.label_outline), label: const Text('Edit tag'),
                    onPressed: () => editTrackTags(context, controller, [track], widget.onAction)),
                ]),
              ]),
      );
    },
  );
}

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key, required this.controller, required this.onAction});
  final AppController controller;
  final AppAction onAction;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller.player,
    builder: (context, _) {
      final state = controller.player.state;
      final upcoming = state.upcomingTracks;
      return Scaffold(appBar: AppBar(title: const Text('Antrean')),
        body: ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (state.currentTrack != null) ...[
              const Padding(padding: EdgeInsets.all(16), child: Text('Sedang diputar')),
              ListTile(leading: TrackCover(track: state.currentTrack!),
                title: Text(state.currentTrack!.title), subtitle: Text(state.currentTrack!.artist),
                trailing: IconButton(tooltip: 'Hapus lagu saat ini dari antrean',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onAction(() => controller.player.remove(state.currentId!)))),
            ],
            Padding(padding: const EdgeInsets.all(16), child: Text(upcoming.isEmpty
              ? 'Tidak ada lagu berikutnya.' : 'Berikutnya · tahan dan geser untuk mengatur urutan')),
          ]),
          itemCount: upcoming.length,
          onReorder: (oldIndex, newIndex) => onAction(() => controller.player.reorder(oldIndex, newIndex)),
          itemBuilder: (context, index) => ListTile(key: ValueKey(upcoming[index].id),
            leading: TrackCover(track: upcoming[index]), title: Text(upcoming[index].title),
            subtitle: Text(upcoming[index].artist),
            trailing: Padding(padding: const EdgeInsets.only(right: 24),
              child: IconButton(tooltip: 'Hapus ${upcoming[index].title} dari antrean',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => onAction(() => controller.player.remove(upcoming[index].id))))),
        ));
    },
  );
}
