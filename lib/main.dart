import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/spomaxxing_app.dart';
import 'data/library_repository.dart';
import 'data/platform_library.dart';
import 'features/player/offline_audio_handler.dart';
import 'features/player/player_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> with WidgetsBindingObserver {
  late Future<AppController> _starting;
  AppController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _starting = _start();
  }

  Future<AppController> _start() async {
    final repository = await LibraryRepository.open();
    final platform = PlatformLibrary();
    final handler = await OfflineAudioHandler.create();
    await AudioService.init<OfflineAudioHandler>(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.spomaxxing.playback',
        androidNotificationChannelName: 'Pemutaran Spomaxxing',
        androidNotificationIcon: 'drawable/ic_stat_music',
        androidStopForegroundOnPause: true,
      ),
    );
    final player = PlayerController(handler: handler,
      onSnapshot: repository.savePlayerSnapshot);
    final controller = AppController(repository: repository, platform: platform,
      player: player, importer: await AppController.createImporter(repository, platform));
    await controller.init();
    _controller = controller;
    return controller;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      final player = _controller?.player;
      if (player != null) unawaited(player.flushSnapshot());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppController>(
    future: _starting,
    builder: (context, snapshot) {
      if (snapshot.hasData) return SpomaxxingApp(controller: snapshot.data!);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF1DB954)),
        home: Scaffold(body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: snapshot.hasError
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Koleksi belum dapat dibuka. Coba buka kembali aplikasi.'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => setState(() => _starting = _start()),
                    child: const Text('Coba lagi')),
                ])
              : const Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(), SizedBox(height: 16),
                  Text('Membuka Spomaxxing…'),
                ]),
        ))),
      );
    },
  );
}

