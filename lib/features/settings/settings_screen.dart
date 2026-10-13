import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/platform_library.dart';
import '../library/library_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller, required this.onAction});
  final AppController controller;
  final AppAction onAction;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<StorageInfo> _storage;

  @override
  void initState() { super.initState(); _storage = widget.controller.platform.storageInfo(); }

  String _bytes(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Text('Audio dan penyimpanan', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    const Text('Impor lagu pilihan menggunakan pemilih berkas sistem. Pilih folder musikmu, '
      'lalu tandai lagu yang ingin disimpan di koleksi privat aplikasi.'),
    const SizedBox(height: 12),
    Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(onPressed: widget.controller.busy ? null : () => widget.onAction(widget.controller.pickAudio),
        icon: const Icon(Icons.audio_file), label: const Text('Tambah berkas')),
    ]),
    const SizedBox(height: 24),
    FutureBuilder<StorageInfo>(future: _storage, builder: (context, snapshot) => Card(child: Padding(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Penyimpanan', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (snapshot.hasData) ...[
          Text('${_bytes(snapshot.data!.bytesAvailable)} tersedia dari ${_bytes(snapshot.data!.bytesTotal)}'),
          Text('Berkas impor: ${_bytes(snapshot.data!.importedBytes)}'),
        ] else Text(snapshot.hasError ? 'Informasi penyimpanan belum dapat dibaca.' : 'Memeriksa penyimpanan…'),
        TextButton(onPressed: () => setState(() {
          _storage = widget.controller.platform.storageInfo();
        }), child: const Text('Perbarui')),
      ]),
    ))),
    const SizedBox(height: 24),
    Text('Tentang Spomaxxing', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    const Text('Koleksi, pencarian, tag, radio, dan pemutaran berkas lokal bekerja offline. '
      'Tidak ada akun, iklan, atau analitik. Impor tautan dan unduhan memerlukan internet.'),
    const SizedBox(height: 12),
    const Text('Unduhan berjalan selama aplikasi terbuka. Jika aplikasi ditutup atau koneksi '
      'terputus, pekerjaan dapat dicoba lagi dari tab Impor. Audio yang sudah selesai tetap tersedia offline.'),
    const SizedBox(height: 12),
    const Text('Spotify dibaca sebagai metadata publik secara eksperimental. Pilih hasil pencarian '
      'YouTube untuk sumber audionya. Video privat/dibatasi dan playlist personal mungkin tidak tersedia.'),
    TextButton(onPressed: () => showLicensePage(context: context,
      applicationName: 'Spomaxxing', applicationVersion: '0.2.0'), child: const Text('Lisensi perangkat lunak')),
    const SizedBox(height: 12),
    const Text('Audio berproteksi DRM dan cache aplikasi musik lain tidak dapat diimpor. '
      'Dukungan format mengikuti codec Android pada perangkat.'),
  ]);
}
