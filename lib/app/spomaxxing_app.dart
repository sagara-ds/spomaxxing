import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/imports/import_models.dart';
import '../features/imports/import_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/player_screen.dart';
import '../features/radio/home_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'app_controller.dart';

ThemeData spomaxxingTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF121212),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1DB954), brightness: Brightness.dark,
  ).copyWith(primary: const Color(0xFF1DB954), onPrimary: Colors.black),
  appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF121212)),
);

class SpomaxxingApp extends StatefulWidget {
  const SpomaxxingApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<SpomaxxingApp> createState() => _SpomaxxingAppState();
}

class _SpomaxxingAppState extends State<SpomaxxingApp> {
  final _navigator = GlobalKey<NavigatorState>();
  int _tab = 0;

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } on ImportOfflineException catch (error) {
      final context = _navigator.currentContext;
      if (context == null || !context.mounted) {
        return;
      }
      final retry = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Tidak ada internet'),
        content: Text(error.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tutup')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Coba lagi')),
        ],
      ));
      if (retry == true && mounted) await _action(action);
    } catch (error) {
      final context = _navigator.currentContext;
      if (context == null || !context.mounted) {
        return;
      }
      final message = switch (error) {
        ImportException exception => exception.message,
        PlatformException exception => exception.message ?? 'Operasi audio belum dapat diselesaikan.',
        _ => 'Operasi belum dapat diselesaikan. Coba lagi.',
      };
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Belum berhasil'), content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ));
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Spomaxxing', debugShowCheckedModeBanner: false,
    navigatorKey: _navigator, theme: spomaxxingTheme(),
    home: AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.controller.player]),
      builder: (context, _) {
        final controller = widget.controller;
        final message = controller.error ?? controller.player.error;
        return Scaffold(
          appBar: AppBar(title: const Text('Spomaxxing')),
          body: SafeArea(child: Column(children: [
            if (message != null) MaterialBanner(
              content: Text(message), leading: const Icon(Icons.info_outline),
              actions: [TextButton(onPressed: () => _action(controller.scan),
                child: const Text('Pindai ulang'))],
            ),
            Expanded(child: IndexedStack(index: _tab, children: [
              HomeScreen(controller: controller, onAction: _action),
              SearchScreen(controller: controller, onAction: _action),
              LibraryScreen(controller: controller, onAction: _action),
              ImportScreen(controller: controller, onAction: _action),
              SettingsScreen(controller: controller, onAction: _action),
            ])),
            MiniPlayer(controller: controller, onAction: _action),
          ])),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab, onDestinationSelected: (index) => setState(() => _tab = index),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
              NavigationDestination(icon: Icon(Icons.search), label: 'Cari'),
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Koleksi'),
              NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Impor'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Pengaturan'),
            ],
          ),
        );
      },
    ),
  );
}
