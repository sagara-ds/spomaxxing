import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/app/spomaxxing_app.dart';
import 'package:spomaxxing/core/models/track.dart';
import 'package:spomaxxing/features/library/library_screen.dart';

void main() {
  testWidgets('empty collection explains how to add real audio', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: spomaxxingTheme(), home: Scaffold(
      body: LibraryView(tracks: const [], onPlay: (_) {}),
    )));
    expect(find.text('Belum ada lagu. Pindai perangkat atau tambahkan berkas audio.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('missing audio cannot be played; available selection uses index', (tester) async {
    int? selected;
    final tracks = [
      Track(id: 'missing', uri: 'file:///missing.wav', title: 'Hilang', isAvailable: false),
      Track(id: 'local', uri: 'file:///local.wav', title: 'Lokal', tags: {'fokus'}),
    ];
    await tester.pumpWidget(MaterialApp(theme: spomaxxingTheme(), home: Scaffold(
      body: LibraryView(tracks: tracks, onPlay: (index) => selected = index),
    )));
    await tester.tap(find.text('Hilang'));
    expect(selected, isNull);
    await tester.tap(find.text('Lokal'));
    expect(selected, 1);
    expect(find.textContaining('Berkas tidak tersedia'), findsOneWidget);
    expect(find.textContaining('fokus'), findsOneWidget);
  });

  testWidgets('collection list fits large accessibility text', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: spomaxxingTheme(), home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2)),
      child: Scaffold(body: SingleChildScrollView(child: LibraryView(
        tracks: [Track(id: 'long', uri: 'file:///long.wav',
          title: 'Judul lagu yang cukup panjang untuk layar kecil', artist: 'Artis dengan nama panjang')],
        onPlay: (_) {}, onEditTags: (_) {},
      ))),
    )));
    expect(tester.takeException(), isNull);
  });
}
