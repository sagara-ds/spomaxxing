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

Dependensi langsung memakai versi persis di `pubspec.yaml`. Workflow menyimpan lockfile hasil resolusi sebagai artifact `dependency-lock`. Setelah resolusi pertama berhasil, `pubspec.lock` perlu dikomit untuk mengunci dependensi transitif.

Pasang Flutter 3.35.4, JDK 17, Android SDK platform 36/build tools, lalu setujui lisensi SDK. Flutter menulis lokasi mesin ke `android/local.properties`; file itu tidak dikomit.

```sh
flutter doctor -v
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
flutter install
```

APK debug berada di `build/app/outputs/flutter-apk/app-debug.apk`. Workflow GitHub menjalankan analisis, tes, dan build, kemudian menyimpan artifact `spomaxxing-debug-apk`. Ini APK pengembangan. Konfigurasi release saat ini juga memakai signing debug; distribusi store membutuhkan keystore dan konfigurasi signing di luar repository.

## Pemeriksaan yang telah dilakukan

- Source Flutter 3.35.4 dan scaffold Android diperiksa dari template resmi.
- Seluruh versi dependensi langsung ditemukan di pub.dev, dengan batas SDK yang kompatibel.
- Dua file Kotlin dikompilasi dengan Kotlin 2.1.0, JVM 11, dan Android platform 36 resmi. Flutter/AudioService memakai stub pada pemeriksaan mandiri; detail di `NATIVE_BRIDGE.md`.
- Skema SQLite dibuat serta diuji untuk entry playlist yang belum tersedia dan penghapusan berantai menggunakan SQLite lokal.
- `git diff --check` tidak menemukan whitespace error.
- Flutter lokal belum dapat dijalankan: proxy menolak host `storage.googleapis.com` saat bootstrap Dart SDK dengan HTTP 403. Tidak ada sertifikat atau pengaturan proxy yang dinonaktifkan. Workflow CI menjadi jalur validasi Flutter; catat hasil run yang sesungguhnya.

Tes mencakup identitas URI lokal, queue token, shuffle/repeat/riwayat, radio/tag/alias, database nyata, rescan, rollback, pencarian, pemulihan, channel Android, UI empty/unavailable state, dan importer dengan transport uji deterministik. Transport uji tidak membuktikan unduhan atau decoder di Android.

## Uji Android yang masih diperlukan

1. Pasang APK di Android 8/API 26 dan perangkat Android terbaru; aktifkan mode pesawat sebelum pembukaan pertama.
2. Tolak izin scan; pastikan pemilih berkas tetap berfungsi. Berikan izin dan pindai MP3, AAC/M4A, FLAC, WAV, serta Ogg buatan sendiri atau berlisensi jelas.
3. Cari lagu/artis/album, tandai favorit dan suasana, simpan radio, lalu buka kembali aplikasi. Periksa antrean pulih dalam keadaan jeda.
4. Putar dengan layar mati; uji notifikasi, lock screen, headset terlepas, audio focus/interupsi, seek, auto-next, repeat, shuffle, dan berkas yang dihapus.
5. Impor satu URL HTTPS audio yang diizinkan dan manifest uji. Putuskan koneksi; pekerjaan harus dijeda dan file `.part` tidak muncul sebagai lagu siap putar. Retry mengulang hanya lagu belum selesai.
6. Aktifkan mode pesawat setelah impor; putar lagu/playlist parsial. Menekan unduh saat offline harus menampilkan alert tanpa menghentikan playback lokal.

Pemeriksaan cloud dan APK yang berhasil dibangun belum membuktikan semua perilaku Android/vendor atau codec perangkat.
