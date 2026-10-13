# Build dan validasi Spomaxxing

## Toolchain

| Komponen | Versi |
| --- | --- |
| Flutter | 3.35.4 stable, revision d693b4b9dbac2acd4477aea4555ca6dcbea44ba2 |
| Dart | 3.9.2, bawaan Flutter |
| JDK CI | Temurin 17 |
| Android Gradle Plugin | 8.9.1 |
| Gradle | 8.12 |
| Kotlin | 2.1.0 |
| compileSdk / targetSdk / minSdk | 36 / 35 / 26 |
| Android NDK | 27.0.12077973, bawaan konfigurasi Flutter |

Dependensi langsung memakai versi persis di `pubspec.yaml`, dan `pubspec.lock` mengunci dependensi transitif dari resolusi CI yang berhasil. Workflow memakai `flutter pub get --enforce-lockfile` dan menyimpan salinan lockfile sebagai artifact `dependency-lock`.

Pasang Flutter 3.35.4, JDK 17, Android SDK platform 36/build tools, lalu setujui lisensi SDK. Flutter menulis lokasi mesin ke `android/local.properties`; file itu tidak dikomit.

```sh
flutter doctor -v
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --release
flutter install --release
```

APK debug berada di `build/app/outputs/flutter-apk/app-debug.apk`. Workflow GitHub menjalankan analisis, tes, dan build, kemudian menyimpan artifact `spomaxxing-debug-apk`. Ini APK pengembangan. Konfigurasi release saat ini juga memakai signing debug; distribusi store membutuhkan keystore dan konfigurasi signing di luar repository.

## Hasil CI terverifikasi

[CI versi 0.1.1](https://github.com/sagara-ds/spomaxxing/actions/runs/38432386519) berhasil pada 13 Oktober 2026 untuk source commit `11bce14430c08244a839d3854ecad12c55d3b29e`:

- `flutter pub get --enforce-lockfile`: berhasil.
- `flutter analyze`: `No issues found`.
- `flutter test`: **62 tes lulus**, termasuk koleksi lazy 10.000 lagu.
- `flutter build apk --debug` dan `flutter build apk --release`: berhasil.
- Artifact release ZIP 24.270.624 byte, berisi `app-release.apk` sebesar 51.492.698 byte.
- Manifest APK diperiksa: versi 0.1.1+2, minSdk26/targetSdk35, tanpa READ_MEDIA_AUDIO atau READ_EXTERNAL_STORAGE.

[Unduh APK release](https://github.com/sagara-ds/spomaxxing/actions/runs/38432386519/artifacts/11831178715). Retensi artifact berakhir 27 Oktober 2026. SHA-256 ZIP: `e2a76d75fb2c28c0ea3b292c77bc625cb2caf28e4b7f2273c38fa0a82ee03dbd`. SHA-256 APK: `4bd117557763e486d7c3f8846a79c17938b81f869d78e47453775bed30ed7026`.

APK adalah build pengembangan, bukan rilis store. Source aplikasi yang diuji tidak berubah pada commit dokumentasi hasil CI ini. Pengujian perangkat berikut tetap diperlukan.

## Pemeriksaan yang telah dilakukan

- Source Flutter 3.35.4 dan scaffold Android diperiksa dari template resmi.
- Seluruh versi dependensi langsung ditemukan di pub.dev, dengan batas SDK yang kompatibel.
- Dua file Kotlin dikompilasi dengan Kotlin 2.1.0, JVM 11, dan Android platform 36 resmi. Flutter/AudioService memakai stub pada pemeriksaan mandiri; detail di `NATIVE_BRIDGE.md`.
- Skema SQLite dibuat serta diuji untuk entry playlist yang belum tersedia dan penghapusan berantai menggunakan SQLite lokal.
- `git diff --check` tidak menemukan whitespace error.
- Parser tree-sitter Dart memeriksa 25 file Dart tanpa kesalahan sintaks; seluruh XML Android dapat diparse. Ini belum pemeriksaan tipe/lint Dart.
- Flutter lokal belum dapat dijalankan: proxy menolak host `storage.googleapis.com` saat bootstrap Dart SDK dengan HTTP 403. Tidak ada sertifikat atau pengaturan proxy yang dinonaktifkan. Analisis Flutter, tes, dan build APK telah berhasil dijalankan melalui CI di atas.

Tes mencakup identitas URI lokal, queue token, shuffle/repeat/riwayat, radio/tag/alias, database nyata, rescan, rollback, pencarian, pemulihan, channel Android, UI empty/unavailable state, dan importer dengan transport uji deterministik. Transport uji tidak membuktikan unduhan atau decoder di Android.

## Uji Android yang masih diperlukan

1. Pasang APK di Android 8/API 26 dan perangkat Android terbaru; aktifkan mode pesawat sebelum pembukaan pertama.
2. Buka folder musik lewat pemilih berkas; pilih MP3, AAC/M4A, FLAC, WAV, dan Ogg buatan sendiri atau berlisensi jelas. Pastikan hanya lagu pilihan masuk koleksi, tanpa permintaan izin scan perangkat.
3. Cari lagu/artis/album, tandai favorit dan suasana, simpan radio, lalu buka kembali aplikasi. Periksa antrean pulih dalam keadaan jeda.
4. Putar dengan layar mati; uji notifikasi, lock screen, headset terlepas, audio focus/interupsi, seek, auto-next, repeat, shuffle, dan berkas yang dihapus.
5. Impor satu URL HTTPS audio yang diizinkan dan manifest uji. Putuskan koneksi; pekerjaan harus dijeda dan file `.part` tidak muncul sebagai lagu siap putar. Retry mengulang hanya lagu belum selesai.
6. Aktifkan mode pesawat setelah impor; putar lagu/playlist parsial. Menekan unduh saat offline harus menampilkan alert tanpa menghentikan playback lokal.

Pemeriksaan cloud dan APK yang berhasil dibangun belum membuktikan semua perilaku Android/vendor atau codec perangkat.

Untuk menguji kelancaran, gunakan APK release. Catatan perubahan dan risiko penggantian signing key development ada di [PERFORMANCE.md](PERFORMANCE.md).
