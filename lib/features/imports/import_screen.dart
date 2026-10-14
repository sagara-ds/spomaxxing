import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/app_controller.dart';
import 'import_models.dart';
import 'import_service.dart' show parseImportLink;
import 'spotdown_source.dart';
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
  int _previewGeneration = 0;
  bool _autoSearchRunning = false;
  int _autoSearchFinished = 0;
  int _autoSearchTotal = 0;
  final Map<String, _AutoSourceStatus> _autoSourceStatus = {};

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
    final generation = ++_previewGeneration;
    _autoSourceStatus.clear();
    _autoSearchRunning = false;
    _autoSearchFinished = 0;
    _autoSearchTotal = 0;
    return _run(() async {
      final parsed = parseImportLink(link);
      if ((parsed.kind == ImportLinkKind.spotifyTrack ||
              parsed.kind == ImportLinkKind.spotifyPlaylist) &&
          !widget.controller.spotdown.session.isValid) {
        final authenticated = await _authenticateSpotdown();
        if (!authenticated) return;
      }
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
      unawaited(_autoSelectTopSources(preview, generation));
    });
  }

  Future<void> _autoSelectTopSources(
    ImportPreview preview,
    int generation,
  ) async {
    final candidates = preview.tracks
        .where((track) => track.provider == 'spotify')
        .toList();
    if (candidates.isEmpty || !mounted || generation != _previewGeneration)
      return;
    setState(() {
      _autoSearchRunning = true;
      _autoSearchFinished = 0;
      _autoSearchTotal = candidates.length;
      _autoSourceStatus
        ..clear()
        ..addEntries(
          candidates.map(
            (track) => MapEntry(track.id, _AutoSourceStatus.searching),
          ),
        );
    });

    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < candidates.length &&
          mounted &&
          generation == _previewGeneration) {
        final candidate = candidates[nextIndex++];
        try {
          final results = await widget.controller.searchYoutube(
            '${candidate.title} ${candidate.artist}',
          );
          if (results.isNotEmpty) {
            _replaceAutomaticSource(
              preview,
              generation,
              candidate,
              results.first,
            );
          } else {
            _setAutomaticSourceStatus(
              preview,
              generation,
              candidate.id,
              _AutoSourceStatus.noResult,
            );
          }
        } catch (_) {
          _setAutomaticSourceStatus(
            preview,
            generation,
            candidate.id,
            _AutoSourceStatus.searchFailed,
          );
        } finally {
          if (mounted && generation == _previewGeneration) {
            setState(() => _autoSearchFinished++);
          }
        }
      }
    }

    final workerCount = candidates.length < 2 ? candidates.length : 2;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    if (mounted && generation == _previewGeneration) {
      setState(() => _autoSearchRunning = false);
    }
  }

  void _replaceAutomaticSource(
    ImportPreview original,
    int generation,
    ImportCandidate candidate,
    YoutubeResult result,
  ) {
    if (!mounted || generation != _previewGeneration) return;
    final preview = _preview;
    if (preview == null || preview.sourceUrl != original.sourceUrl) return;
    final matches = preview.tracks.where((track) => track.id == candidate.id);
    if (matches.isEmpty || matches.first.provider != 'spotify') return;
    setState(() {
      _preview = ImportPreview(
        sourceUrl: preview.sourceUrl,
        name: preview.name,
        isPlaylist: preview.isPlaylist,
        tracks: preview.tracks
            .map(
              (track) =>
                  track.id == candidate.id ? result.forTrack(candidate) : track,
            )
            .toList(),
      );
      _autoSourceStatus[candidate.id] = _AutoSourceStatus.automaticSelected;
    });
  }

  void _setAutomaticSourceStatus(
    ImportPreview original,
    int generation,
    String candidateId,
    _AutoSourceStatus status,
  ) {
    if (!mounted || generation != _previewGeneration) return;
    final preview = _preview;
    if (preview == null || preview.sourceUrl != original.sourceUrl) return;
    final matches = preview.tracks.where((track) => track.id == candidateId);
    if (matches.isEmpty || matches.first.provider != 'spotify') return;
    setState(() => _autoSourceStatus[candidateId] = status);
  }

  Future<void> _downloadSelected() {
    final preview = _preview;
    if (preview == null || _selectedIds.isEmpty) return Future<void>.value();
    final selected = Set<String>.of(_selectedIds);
    print(
      '[DEBUG-7F31] download button invoked selected=${selected.length} permission=$_hasPermission',
    );
    if (!_hasPermission &&
        preview.tracks.any((track) => track.provider != 'direct')) {
      return widget.onAction(() async {
        throw const ImportException(
          'Konfirmasikan izin mengunduh audio pilihan.',
        );
      });
    }
    return _run(() async {
      if (preview.tracks.any(
            (track) =>
                selected.contains(track.id) && track.provider == 'spotdown',
          ) &&
          !widget.controller.spotdown.session.isValid) {
        final authenticated = await _authenticateSpotdown();
        if (!authenticated) return;
      }
      await widget.controller.downloadImport(preview, ids: selected);
    });
  }

  Future<void> _chooseSource(ImportCandidate candidate) => _run(() async {
    final selected = await showDialog<YoutubeResult>(
      context: context,
      builder: (context) =>
          _YoutubePicker(candidate: candidate, controller: widget.controller),
    );
    if (selected == null || !mounted || _preview == null) return;
    if (!_hasPermission)
      throw const ImportException(
        'Centang izin unduh, lalu pilih sumber YouTube.',
      );
    setState(() {
      _preview = ImportPreview(
        sourceUrl: _preview!.sourceUrl,
        name: _preview!.name,
        isPlaylist: _preview!.isPlaylist,
        tracks: _preview!.tracks
            .map(
              (track) => track.id == candidate.id
                  ? selected.forTrack(candidate)
                  : track,
            )
            .toList(),
      );
      _autoSourceStatus[candidate.id] = _AutoSourceStatus.manuallySelected;
    });
  });

  Future<void> _searchManual() => _run(() async {
    final input = _urlController.text.trim();
    final query = input.startsWith('https://') ? '' : input;
    final seed = ImportCandidate(
      id: 'manual',
      title: query,
      artist: '',
      url: Uri.https('www.youtube.com', '/'),
      license: 'pending',
      source: 'Pencarian manual',
    );
    final selected = await showDialog<YoutubeResult>(
      context: context,
      builder: (context) =>
          _YoutubePicker(candidate: seed, controller: widget.controller),
    );
    if (selected == null || !mounted) return;
    if (!_hasPermission)
      throw const ImportException(
        'Konfirmasikan izin unduh sebelum memilih audio.',
      );
    ++_previewGeneration;
    final candidate = ImportCandidate(
      id: 'youtube:${selected.id}',
      title: selected.title,
      artist: selected.channel,
      durationMs: selected.durationMs,
      url: selected.url,
      provider: 'youtube',
      license: 'Izin unduh dikonfirmasi pengguna',
      source: selected.url.toString(),
    );
    setState(() {
      _preview = ImportPreview(
        sourceUrl: selected.url.toString(),
        name: selected.title,
        tracks: [candidate],
        isPlaylist: false,
      );
      _selectedIds
        ..clear()
        ..add(candidate.id);
      _autoSourceStatus.clear();
      _autoSearchRunning = false;
      _autoSearchFinished = 0;
      _autoSearchTotal = 0;
    });
  });

  Future<void> _retry(ImportJob job) => _run(() async {
    if (job.tracks.any((track) => track.candidate.provider == 'spotdown') &&
        !widget.controller.spotdown.session.isValid) {
      final authenticated = await _authenticateSpotdown();
      if (!authenticated) return;
    }
    await widget.controller.importer.retry(job);
    await widget.controller.reload();
  });

  Future<void> _cancel() => widget.onAction(() async {
    widget.controller.importer.cancel();
  });

  void _invalidatePreview() {
    ++_previewGeneration;
    setState(() {
      _preview = null;
      _selectedIds.clear();
      _autoSourceStatus.clear();
      _autoSearchRunning = false;
      _autoSearchFinished = 0;
      _autoSearchTotal = 0;
    });
  }

  Future<bool> _authenticateSpotdown() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _SpotdownAuthenticationDialog(source: widget.controller.spotdown),
    );
    return result ?? false;
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
                      helperText:
                          'Spotify, YouTube, berkas audio HTTPS, atau playlist .json',
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
                    subtitle: const Text(
                      'Diperlukan sebelum mengunduh audio langsung atau sumber YouTube pilihan.',
                    ),
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
                  OutlinedButton.icon(
                    onPressed: busy ? null : _searchManual,
                    icon: const Icon(Icons.search),
                    label: const Text('Cari judul di YouTube'),
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
                    Expanded(
                      child: Text(
                        'Belum ada unduhan. Tempel tautan untuk mulai.',
                      ),
                    ),
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
    final ready = preview.tracks
        .where((track) => _selectedIds.contains(track.id))
        .every((track) => track.provider != 'spotify');
    final needsPermission = preview.tracks.any(
      (track) => track.provider != 'direct',
    );
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
                Text(
                  '${_selectedIds.length} dari ${preview.tracks.length} lagu dipilih',
                ),
                if (_autoSearchTotal > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    _autoSearchRunning
                        ? 'Memilih hasil teratas YouTube: $_autoSearchFinished/$_autoSearchTotal lagu'
                        : 'Pencarian otomatis selesai untuk $_autoSearchFinished/$_autoSearchTotal lagu',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _autoSearchTotal == 0
                        ? null
                        : _autoSearchFinished / _autoSearchTotal,
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _selectedIds.clear();
                          if (!allSelected) {
                            _selectedIds.addAll(
                              preview.tracks.map((track) => track.id),
                            );
                          }
                        }),
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                  label: Text(
                    allSelected ? 'Batal pilih semua' : 'Pilih semua',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 400,
            child: ListView.builder(
              itemCount: preview.tracks.length,
              itemBuilder: (context, index) {
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
                      if (_autoSourceStatus[candidate.id] != null)
                        Text(
                          _autoSourceLabel(_autoSourceStatus[candidate.id]!),
                        ),
                      if (candidate.provider == 'spotify' ||
                          candidate.provider == 'youtube')
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => _chooseSource(candidate),
                          icon: const Icon(Icons.search),
                          label: Text(
                            candidate.provider == 'spotify'
                                ? 'Pilih hasil YouTube'
                                : 'Ganti sumber YouTube',
                          ),
                        ),
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
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed:
                  busy ||
                      _selectedIds.isEmpty ||
                      !ready ||
                      (needsPermission && !_hasPermission)
                  ? null
                  : _downloadSelected,
              icon: const Icon(Icons.download),
              label: Text('Unduh ${_selectedIds.length} lagu terpilih'),
            ),
          ),
          if (!ready)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pilih sumber YouTube untuk lagu terpilih, atau batalkan pilihan lagu yang belum memiliki sumber.',
              ),
            ),
        ],
      ),
    );
  }
}

class _SpotdownAuthenticationDialog extends StatefulWidget {
  const _SpotdownAuthenticationDialog({required this.source});

  final SpotdownSource source;

  @override
  State<_SpotdownAuthenticationDialog> createState() =>
      _SpotdownAuthenticationDialogState();
}

class _SpotdownAuthenticationDialogState
    extends State<_SpotdownAuthenticationDialog> {
  late final WebViewController _controller;
  Timer? _sessionPoll;
  Future<bool>? _sessionCheck;
  bool _finished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _startSessionPolling(),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(
                () =>
                    _error = 'Halaman Spotdown gagal dimuat. Periksa koneksi.',
              );
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final isSpotdown =
                uri?.scheme == 'https' &&
                (uri?.host == 'spotdown.org' ||
                    uri?.host.endsWith('.spotdown.org') == true);
            return request.isMainFrame && !isSpotdown
                ? NavigationDecision.prevent
                : uri?.scheme == 'https'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(SpotdownSource.authenticationUri);
  }

  void _startSessionPolling() {
    _sessionPoll ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_checkSession()),
    );
    unawaited(_checkSession());
  }

  Future<bool> _checkSession() {
    if (_finished || !mounted) return Future<bool>.value(false);
    final active = _sessionCheck;
    if (active != null) return active;
    final check = _readSession();
    _sessionCheck = check;
    return check.whenComplete(() {
      if (identical(_sessionCheck, check)) _sessionCheck = null;
    });
  }

  Future<bool> _readSession() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "sessionStorage.getItem('_st') || ''",
      );
      final raw = _javaScriptString(result);
      if (raw.isEmpty) return false;
      widget.source.session.updateFromStorage(raw);
      if (!mounted || _finished) return true;
      _finished = true;
      _sessionPoll?.cancel();
      Navigator.of(context).pop(true);
      return true;
    } on ImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } catch (_) {
      // The page can replace its JavaScript context while Turnstile completes.
      return false;
    }
  }

  String _javaScriptString(Object result) {
    if (result is! String || result.isEmpty) return '';
    if (result.startsWith('"') && result.endsWith('"')) {
      try {
        final decoded = jsonDecode(result);
        if (decoded is String) return decoded;
      } on FormatException {
        return '';
      }
    }
    return result;
  }

  Future<void> _close() async {
    if (await _checkSession() || !mounted || _finished) return;
    _finished = true;
    _sessionPoll?.cancel();
    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _sessionPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: SafeArea(
      child: Column(
        children: [
          AppBar(
            title: const Text('Verifikasi Spotdown'),
            leading: IconButton(
              onPressed: _close,
              icon: const Icon(Icons.close),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Selesaikan pemeriksaan keamanan pada halaman resmi Spotdown. '
              'Token sesi hanya disimpan selama aplikasi terbuka.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    ),
  );
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
        leading: Icon(
          job.status == ImportJobStatus.completed
              ? Icons.offline_pin_outlined
              : Icons.download_outlined,
        ),
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
    final resolving = track.status == ImportTrackStatus.resolving;
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
                if (resolving || downloading || verifying) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: resolving || verifying ? null : progress,
                    semanticsLabel:
                        '${_trackStatus(track.status)} ${track.candidate.title}',
                    semanticsValue: progress == null || resolving || verifying
                        ? null
                        : '${(progress * 100).round()} persen',
                  ),
                  if (!resolving) ...[
                    const SizedBox(height: 4),
                    Text(
                      total == null
                          ? '${_bytes(track.receivedBytes)} diterima'
                          : '${_bytes(track.receivedBytes)} / ${_bytes(total)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
                if (track.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    track.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
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
  ImportTrackStatus.resolving => 'Mencari stream audio YouTube',
  ImportTrackStatus.downloading => 'Mengunduh',
  ImportTrackStatus.verifying => 'Memeriksa audio',
  ImportTrackStatus.completed => 'Tersimpan offline',
  ImportTrackStatus.failed => 'Gagal',
  ImportTrackStatus.paused => 'Dijeda',
  ImportTrackStatus.cancelled => 'Dibatalkan',
};

IconData _trackIcon(ImportTrackStatus status) => switch (status) {
  ImportTrackStatus.queued => Icons.schedule,
  ImportTrackStatus.resolving => Icons.travel_explore,
  ImportTrackStatus.downloading => Icons.downloading,
  ImportTrackStatus.verifying => Icons.fact_check_outlined,
  ImportTrackStatus.completed => Icons.offline_pin_outlined,
  ImportTrackStatus.failed => Icons.error_outline,
  ImportTrackStatus.paused => Icons.pause_circle_outline,
  ImportTrackStatus.cancelled => Icons.cancel_outlined,
};

enum _AutoSourceStatus {
  searching,
  automaticSelected,
  manuallySelected,
  noResult,
  searchFailed,
}

String _autoSourceLabel(_AutoSourceStatus status) => switch (status) {
  _AutoSourceStatus.searching => 'Mencari hasil teratas…',
  _AutoSourceStatus.automaticSelected =>
    'Hasil teratas dipilih otomatis — periksa sebelum unduh',
  _AutoSourceStatus.manuallySelected => 'Sumber YouTube dipilih manual',
  _AutoSourceStatus.noResult => 'Tidak ada hasil; pilih sumber secara manual',
  _AutoSourceStatus.searchFailed =>
    'Pencarian gagal; pilih sumber manual atau coba lagi',
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
    _query = TextEditingController(
      text: '${widget.candidate.title} ${widget.candidate.artist}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _query.text.trim().isNotEmpty) _search();
    });
  }

  Future<void> _search() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.controller.searchYoutube(_query.text);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ImportException
              ? error.message
              : 'YouTube belum dapat diakses. Coba lagi nanti.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _duration(int ms) =>
      '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Pilih sumber YouTube'),
    content: SizedBox(
      width: double.maxFinite,
      height: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.candidate.title} — ${widget.candidate.artist}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.candidate.durationMs > 0)
            Text('Durasi asal: ${_duration(widget.candidate.durationMs)}'),
          TextField(
            controller: _query,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Cari judul dan artis',
            ),
            onSubmitted: (_) => _search(),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _search,
            icon: const Icon(Icons.search),
            label: const Text('Cari YouTube'),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? SingleChildScrollView(child: Text(_error!))
                : _results.isEmpty
                ? const Center(
                    child: Text('Belum ada hasil. Coba kata pencarian lain.'),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return ListTile(
                        title: Text(result.title),
                        subtitle: Text(
                          '${result.channel}\nDurasi ${_duration(result.durationMs)}',
                        ),
                        onTap: _busy
                            ? null
                            : () => Navigator.pop(context, result),
                      );
                    },
                  ),
          ),
          const Text(
            'Periksa judul, kanal, durasi, dan versi rekaman sebelum memilih.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
    ],
  );
}
