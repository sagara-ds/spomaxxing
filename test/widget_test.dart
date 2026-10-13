import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spomaxxing/app/spomaxxing_app.dart';
import 'package:spomaxxing/core/models/track.dart';
import 'package:spomaxxing/features/library/library_screen.dart';

void main() {
  testWidgets('large collection builds only visible rows', (tester) async {
    final tracks = List.generate(10000, (index) => Track(
      id: '$index', uri: 'file:///music/$index.wav', title: 'Lagu $index'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LibraryView(
      tracks: tracks, onPlay: (_) {},
    ))));
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    expect(find.byKey(const ValueKey('track:9999')), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty collection explains how to add real audio', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: spomaxxingTheme(), home: Scaffold(
      body: LibraryView(tracks: const [], onPlay: (_) {}),
    )));
    expect(find.text('Belum ada lagu. Impor berkas audio pilihanmu.'), findsOneWidget);
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
      child: Scaffold(body: LibraryView(
        tracks: [Track(id: 'long', uri: 'file:///long.wav',
          title: 'Judul lagu yang cukup panjang untuk layar kecil', artist: 'Artis dengan nama panjang')],
        onPlay: (_) {}, onEditTags: (_) {},
      )),
    )));
    expect(tester.takeException(), isNull);
  });
}
