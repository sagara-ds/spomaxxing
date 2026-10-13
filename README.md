# Spomaxxing

Pemutar musik Android berbasis Flutter, Dart, dan Kotlin. Versi awal menyediakan koleksi lokal, pencarian, tag suasana, radio mix, playlist, serta impor audio yang dapat diputar offline. Antarmuka memakai palet hijau dan hitam dengan identitas Spomaxxing sendiri.

## Keputusan awal

- Platform pertama: Android.
- Sumber musik: berkas audio perangkat dan unduhan dari sumber yang mengizinkan pengunduhan.
- Pencarian suasana: kata kunci dan tag lokal, seperti santai, fokus, sedih, dan semangat.
- Fitur utama: koleksi lokal, pencarian, radio mix, shuffle, perpindahan lagu otomatis, dan pemutaran latar belakang.
- Internet digunakan saat pengguna mengimpor tautan atau mengunduh audio. Playback, pencarian koleksi, dan radio lokal tetap berjalan tanpa internet.
- Saat pengguna mencoba mengunduh tanpa koneksi, tampilkan alert. Lagu yang sudah tersimpan tetap dapat diputar.

"Semua lagu" berarti seluruh berkas audio yang dapat diakses aplikasi dalam koleksi pengguna. Ketersediaan lagu bergantung pada berkas yang dimiliki pengguna; aplikasi tidak menyediakan katalog atau audio Spotify.

## Status

Kode versi awal sudah tersedia:

- Pemindaian MediaStore dengan izin Android yang sesuai serta pemilih audio lokal multiberkas dengan salinan privat.
- SQLite untuk koleksi, tag, favorit, playlist, antrean, posisi, dan pekerjaan impor. Pindai ulang mempertahankan perubahan pengguna.
- Pemutar lokal `just_audio`/`audio_service`, seek, riwayat, shuffle, repeat, auto-next, kontrol media, dan pemulihan posisi tanpa autoplay.
- Radio dari tag lokal dengan alias suasana, variasi artis, hingga 25 lagu unik, dan penyimpanan mix sebagai playlist.
- Unduh HTTPS audio langsung dan manifest JSON berlisensi, pilihan per lagu, checksum opsional, validasi decoder, status per lagu, playlist parsial, pembatalan, retry, dan alert offline.
- Layar Beranda, Cari, Koleksi, Impor, Pengaturan, pemutar, antrean, dan editor tag massal.

Pada 13 Oktober 2026, [CI Android berhasil](https://github.com/sagara-ds/spomaxxing/actions/runs/38424252024): `flutter analyze` bersih, **61 tes lulus**, dan APK debug berhasil dibangun dengan plugin Flutter serta Kotlin sebenarnya. [Unduh artifact APK debug](https://github.com/sagara-ds/spomaxxing/actions/runs/38424252024/artifacts/11828062742), lalu ekstrak `app-debug.apk` untuk pengujian. Pengujian playback, izin, format audio, serta kontrol background pada perangkat Android masih diperlukan.

Unduhan versi awal berlangsung selama aplikasi terbuka. Pekerjaan terputus dipulihkan sebagai dijeda; retry mengulang lagu yang belum selesai dari awal. Integrasi provider Spotify/SpotMate, WorkManager/background download, ekstraksi sampul, dan pagination koleksi besar belum tersedia.

Lihat [petunjuk build dan pengujian](docs/BUILD.md), [kontrak bridge Android](docs/NATIVE_BRIDGE.md), dan [pemutar](docs/PLAYBACK.md).

Lihat [rencana implementasi](docs/PLAN.md) untuk arsitektur, fitur, urutan pekerjaan, dan kriteria penerimaan.

Lihat [format impor yang didukung](docs/IMPORT_FORMAT.md) untuk manifest playlist versi awal. [Rencana impor lagu/playlist dan unduhan](docs/PLAYLIST_IMPORT.md) mencatat arah fitur dan evaluasi Spotify, spotify-dl, serta SpotMate. Akses provider Spotify/SpotMate belum dikonfigurasi atau terverifikasi; tautannya dikenali dan diberi penjelasan.
