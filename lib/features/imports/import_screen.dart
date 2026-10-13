import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import 'import_models.dart';
import 'youtube_source.dart';

/// The network entry point: every preview or transfer requires a user action.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.controller,
    required this.onAction,
  });

  final AppController controller;
  final Future<void> Function(Future<void> Function()) onAction;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _urlController = TextEditingController();
  final _selectedIds = <String>{};
  ImportPreview? _preview;
  bool _hasPermission = false;
  bool _requestBusy = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) =>
      widget.onAction(() async {
        if (!mounted || _requestBusy) return;
        setState(() => _requestBusy = true);
        try {
          await action();
        } finally {
          if (mounted) setState(() => _requestBusy = false);
        }
      });

  Future<void> _previewLink() {
    final link = _urlController.text.trim();
    final permission = _hasPermission;
    return _run(() async {
      final preview = await widget.controller.previewImport(
        link,
        permission: permission,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _selectedIds
          ..clear()
          ..addAll(preview.tracks.map((track) => track.id));
      });
    });
  }

  Future<void> _downloadSelected() {
    final preview = _preview;
    if (preview == null || _selectedIds.isEmpty) return Future<void>.value();
    final selected = Set<String>.of(_selectedIds);
    if (!_hasPermission && preview.tracks.any((track) => track.provider != 'direct')) {
      return widget.onAction(() async { throw const ImportException('Konfirmasikan izin mengunduh audio pilihan.'); });
    }
    return _run(() => widget.controller.downloadImport(preview, ids: selected));
  }

  Future<void> _chooseSource(ImportCandidate candidate) => _run(() async {
    final selected = await showDialog<YoutubeResult>(context: context,
      builder: (context) => _YoutubePicker(candidate: candidate, controller: widget.controller));
    if (selected == null || !mounted || _preview == null) return;
    if (!_hasPermission) throw const ImportException('Centang izin unduh, lalu pilih sumber YouTube.');
    setState(() => _preview = ImportPreview(sourceUrl: _preview!.sourceUrl,
      name: _preview!.name, isPlaylist: _preview!.isPlaylist,
      tracks: _preview!.tracks.map((track) => track.id == candidate.id ? selected.forTrack(candidate) : track).toList()));
  });

  Future<void> _searchManual() => _run(() async {
    final input = _urlController.text.trim();
    final query = input.startsWith('https://') ? '' : input;
    final seed = ImportCandidate(id: 'manual', title: query, artist: '',
      url: Uri.https('www.youtube.com', '/'), license: 'pending', source: 'Pencarian manual');
    final selected = await showDialog<YoutubeResult>(context: context,
      builder: (context) => _YoutubePicker(candidate: seed, controller: widget.controller));
    if (selected == null || !mounted) return;
    if (!_hasPermission) throw const ImportException('Konfirmasikan izin unduh sebelum memilih audio.');
    final candidate = ImportCandidate(id: 'youtube:${selected.id}', title: selected.title,
      artist: selected.channel, durationMs: selected.durationMs, url: selected.url,
      provider: 'youtube', license: 'Izin unduh dikonfirmasi pengguna', source: selected.url.toString());
    setState(() {
      _preview = ImportPreview(sourceUrl: selected.url.toString(), name: selected.title,
        tracks: [candidate], isPlaylist: false);
      _selectedIds..clear()..add(candidate.id);
    });
  });

  Future<void> _retry(ImportJob job) => _run(() async {
    await widget.controller.importer.retry(job);
    await widget.controller.reload();
  });

  Future<void> _cancel() => widget.onAction(() async {
    widget.controller.importer.cancel();
  });

  void _invalidatePreview() {
    setState(() {
      _preview = null;
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ImportJob>(
    stream: widget.controller.importer.changes,
    builder: (context, snapshot) {
      final jobs = widget.controller.importer.jobs;
      final hasActiveJob = jobs.any((job) => job.isActive);
      final busy = _requestBusy || hasActiveJob;
      final preview = _preview;
      final theme = Theme.of(context);
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Impor musik', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Unduh audio yang diizinkan, lalu putar dari koleksi tanpa internet.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _urlController,
                    enabled: !busy,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Tautan audio atau playlist',
                      hintText: 'https://contoh.com/lagu.mp3',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                      helperText: 'Spotify, YouTube, berkas audio HTTPS, atau playlist .json',
                      helperMaxLines: 2,
                    ),
                    onChanged: (_) => _invalidatePreview(),
                    onSubmitted: (_) {
                      if (!busy && _urlController.text.trim().isNotEmpty) {
                        _previewLink();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _hasPermission,
                    title: const Text('Saya memiliki izin mengunduh audio ini'),
                    subtitle: const Text('Diperlukan sebelum mengunduh audio langsung atau sumber YouTube pilihan.'),
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() => _hasPermission = value ?? false);
                          },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: busy || _urlController.text.trim().isEmpty
                        ? null
                        : _previewLink,
                    icon: _requestBusy && !hasActiveJob
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.preview_outlined),
                    label: const Text('Pratinjau tautan'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(onPressed: busy ? null : _searchManual,
                    icon: const Icon(Icons.search), label: const Text('Cari judul di YouTube')),
                  Text(
                    'Format audio: MP3, M4A, AAC, WAV, FLAC, OGG, OPUS, dan MP4. '
                    'Playlist JSON menyertakan judul, artis, sumber, dan lisensi setiap lagu.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Spotify dibaca sebagai metadata publik (eksperimental). Pilih sumber YouTube per lagu; hasil tidak diganti otomatis dengan cover/remix.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: 24),
            _buildPreview(context, preview, busy),
          ],
          const SizedBox(height: 24),
          Text('Unduhan', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Biarkan aplikasi tetap terbuka selama unduhan. Jika terputus, '
            'coba lagi untuk mengunduh ulang lagu yang belum selesai. '
            'Lagu yang sudah tersimpan tetap tersedia offline.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.download_outlined),
                    SizedBox(width: 16),
                    Expanded(child: Text('Belum ada unduhan. Tempel tautan untuk mulai.')),
                  ],
                ),
              ),
            ),
          for (final job in jobs) ...[
            _ImportJobCard(
              key: ValueKey(job.id),
              job: job,
              canRetry: !busy,
              onRetry: () => _retry(job),
              onCancel: _cancel,
            ),
            const SizedBox(height: 12),
          ],
        ],
      );
    },
  );

  Widget _buildPreview(BuildContext context, ImportPreview preview, bool busy) {
    final theme = Theme.of(context);
    final allSelected = _selectedIds.length == preview.tracks.length;
    final ready = preview.tracks.where((track) => _selectedIds.contains(track.id))
      .every((track) => track.provider != 'spotify');
    final needsPermission = preview.tracks.any((track) => track.provider != 'direct');
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pratinjau', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(preview.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('${_selectedIds.length} dari ${preview.tracks.length} lagu dipilih'),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _selectedIds.clear();
                          if (!allSelected) {
                            _selectedIds.addAll(preview.tracks.map((track) => track.id));
                          }
                        }),
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                  label: Text(allSelected ? 'Batal pilih semua' : 'Pilih semua'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(height: 400, child: ListView.builder(
            itemCount: preview.tracks.length, itemBuilder: (context, index) {
              final candidate = preview.tracks[index];
              return CheckboxListTile(
              value: _selectedIds.contains(candidate.id),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(candidate.title),
              isThreeLine: true,
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.artist),
                  const SizedBox(height: 4),
                  Text('Lisensi: ${candidate.license}'),
                  Text('Sumber: ${candidate.source}'),
                  if (candidate.provider == 'spotify' || candidate.provider == 'youtube')
                    TextButton.icon(onPressed: busy ? null : () => _chooseSource(candidate),
                      icon: const Icon(Icons.search), label: Text(candidate.provider == 'spotify'
                        ? 'Pilih hasil YouTube' : 'Ganti sumber YouTube')),
                ],
              ),
              onChanged: busy
                  ? null
                  : (selected) => setState(() {
                      if (selected ?? false) {
                        _selectedIds.add(candidate.id);
                      } else {
                        _selectedIds.remove(candidate.id);
                      }
                    }),
            ); })),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: busy || _selectedIds.isEmpty || !ready || (needsPermission && !_hasPermission) ? null : _downloadSelected,
              icon: const Icon(Icons.download),
              label: Text('Unduh ${_selectedIds.length} lagu terpilih'),
            ),
          ),
          if (!ready) const Padding(padding: EdgeInsets.all(16),
            child: Text('Pilih sumber YouTube untuk lagu terpilih, atau batalkan pilihan lagu yang belum memiliki sumber.')),
        ],
      ),
    );
  }
}

class _ImportJobCard extends StatelessWidget {
  const _ImportJobCard({
    super.key,
    required this.job,
    required this.canRetry,
    required this.onRetry,
    required this.onCancel,
  });

  final ImportJob job;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retryable = {
      ImportJobStatus.paused,
      ImportJobStatus.failed,
      ImportJobStatus.partial,
      ImportJobStatus.cancelled,
    }.contains(job.status);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: job.isActive || retryable,
        title: Text(job.preview.name),
        subtitle: Text(
          '${_jobStatus(job.status)} · ${job.completedCount}/${job.totalCount} lagu tersimpan',
        ),
        leading: Icon(job.status == ImportJobStatus.completed
            ? Icons.offline_pin_outlined
            : Icons.download_outlined),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (job.isActive) ...[
            LinearProgressIndicator(
              semanticsLabel: 'Mengunduh ${job.preview.name}',
            ),
            const SizedBox(height: 12),
          ],
          if (job.error != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(job.error!, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 12),
          ],
          for (final track in job.tracks) _ImportTrackRow(track: track),
          if (job.isActive || retryable) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: job.isActive
                  ? OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Batalkan unduhan'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: canRetry ? onRetry : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportTrackRow extends StatelessWidget {
  const _ImportTrackRow({required this.track});
  final ImportTrackProgress track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloading = track.status == ImportTrackStatus.downloading;
    final verifying = track.status == ImportTrackStatus.verifying;
    final total = track.totalBytes;
    final progress = total != null && total > 0
        ? (track.receivedBytes / total).clamp(0.0, 1.0).toDouble()
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_trackIcon(track.status), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.candidate.title, style: theme.textTheme.titleSmall),
                Text(track.candidate.artist, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(_trackStatus(track.status)),
                if (downloading || verifying) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: verifying ? null : progress,
                    semanticsLabel: '${_trackStatus(track.status)} ${track.candidate.title}',
                    semanticsValue: progress == null || verifying
                        ? null
                        : '${(progress * 100).round()} persen',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total == null
                        ? '${_bytes(track.receivedBytes)} diterima'
                        : '${_bytes(track.receivedBytes)} / ${_bytes(total)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (track.error != null) ...[
                  const SizedBox(height: 4),
                  Text(track.error!, style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _jobStatus(ImportJobStatus status) => switch (status) {
  ImportJobStatus.queued => 'Menunggu',
  ImportJobStatus.downloading => 'Mengunduh',
  ImportJobStatus.completed => 'Selesai',
  ImportJobStatus.partial => 'Selesai sebagian',
  ImportJobStatus.failed => 'Gagal',
  ImportJobStatus.paused => 'Dijeda',
  ImportJobStatus.cancelled => 'Dibatalkan',
};

String _trackStatus(ImportTrackStatus status) => switch (status) {
  ImportTrackStatus.queued => 'Menunggu',
  ImportTrackStatus.downloading => 'Mengunduh',
  ImportTrackStatus.verifying => 'Memeriksa audio',
  ImportTrackStatus.completed => 'Tersimpan offline',
  ImportTrackStatus.failed => 'Gagal',
  ImportTrackStatus.paused => 'Dijeda',
  ImportTrackStatus.cancelled => 'Dibatalkan',
};

IconData _trackIcon(ImportTrackStatus status) => switch (status) {
  ImportTrackStatus.queued => Icons.schedule,
  ImportTrackStatus.downloading => Icons.downloading,
  ImportTrackStatus.verifying => Icons.fact_check_outlined,
  ImportTrackStatus.completed => Icons.offline_pin_outlined,
  ImportTrackStatus.failed => Icons.error_outline,
  ImportTrackStatus.paused => Icons.pause_circle_outline,
  ImportTrackStatus.cancelled => Icons.cancel_outlined,
};

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

class _YoutubePicker extends StatefulWidget {
  const _YoutubePicker({required this.candidate, required this.controller});
  final ImportCandidate candidate;
  final AppController controller;
  @override
  State<_YoutubePicker> createState() => _YoutubePickerState();
}

class _YoutubePickerState extends State<_YoutubePicker> {
  late final TextEditingController _query;
  List<YoutubeResult> _results = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: '${widget.candidate.title} ${widget.candidate.artist}');
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _query.text.trim().isNotEmpty) _search(); });
  }

  Future<void> _search() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final results = await widget.controller.searchYoutube(_query.text);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = error is ImportException
        ? error.message : 'YouTube belum dapat diakses. Coba lagi nanti.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  String _duration(int ms) => '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() { _query.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Pilih sumber YouTube'),
    content: SizedBox(width: double.maxFinite, height: 440, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${widget.candidate.title} — ${widget.candidate.artist}', maxLines: 3, overflow: TextOverflow.ellipsis),
        if (widget.candidate.durationMs > 0) Text('Durasi asal: ${_duration(widget.candidate.durationMs)}'),
        TextField(controller: _query, enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Cari judul dan artis'),
          onSubmitted: (_) => _search()),
        TextButton.icon(onPressed: _busy ? null : _search,
          icon: const Icon(Icons.search), label: const Text('Cari YouTube')),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _error != null ? SingleChildScrollView(child: Text(_error!))
          : _results.isEmpty ? const Center(child: Text('Belum ada hasil. Coba kata pencarian lain.'))
          : ListView.builder(itemCount: _results.length, itemBuilder: (context, index) {
            final result = _results[index];
            return ListTile(title: Text(result.title),
              subtitle: Text('${result.channel}\nDurasi ${_duration(result.durationMs)}'),
              onTap: _busy ? null : () => Navigator.pop(context, result));
          })),
        const Text('Periksa judul, kanal, durasi, dan versi rekaman sebelum memilih.'),
      ],
    )),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal'))],
  );
}
