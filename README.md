# Spomaxxing

Pemutar musik Android berbasis Flutter, Dart, dan Kotlin. Versi awal menyediakan koleksi lokal, pencarian, tag suasana, radio mix, playlist, serta impor audio yang dapat diputar offline. Antarmuka memakai palet hijau dan hitam dengan identitas Spomaxxing sendiri.

## Keputusan awal

- Platform pertama: Android.
- Sumber musik: berkas audio perangkat dan unduhan dari sumber yang mengizinkan pengunduhan.
- Pencarian suasana: kata kunci dan tag lokal, seperti santai, fokus, sedih, dan semangat.
- Fitur utama: koleksi lokal, pencarian, radio mix, shuffle, perpindahan lagu otomatis, dan pemutaran latar belakang.
- Internet digunakan saat pengguna mengimpor tautan atau mengunduh audio. Playback, pencarian koleksi, dan radio lokal tetap berjalan tanpa internet.
- Saat pengguna mencoba mengunduh tanpa koneksi, tampilkan alert. Lagu yang sudah tersimpan tetap dapat diputar.

"Semua lagu" berarti audio yang dipilih untuk diimpor atau selesai diunduh ke koleksi aplikasi. Ketersediaan lagu bergantung pada berkas yang dimiliki pengguna; aplikasi tidak menyediakan katalog atau audio Spotify.

## Status

Kode versi awal sudah tersedia:

- Impor audio pilihan lewat pemilih berkas multiberkas, dengan salinan privat. Buka folder musik lalu pilih lagu yang diinginkan; aplikasi tidak memindai seluruh perangkat.
- SQLite untuk koleksi, tag, favorit, playlist, antrean, posisi, dan pekerjaan impor. Koleksi lama dari pemindaian tidak ditampilkan, tetapi rekornya tidak dihapus dan berkas asli tidak disentuh.
- Pemutar lokal `just_audio`/`audio_service`, seek, riwayat, shuffle, repeat, auto-next, kontrol media, dan pemulihan posisi tanpa autoplay.
- Radio dari tag lokal dengan alias suasana, variasi artis, hingga 25 lagu unik, dan penyimpanan mix sebagai playlist.
- Unduh HTTPS audio langsung dan manifest JSON berlisensi, pilihan per lagu, checksum opsional, validasi decoder, status per lagu, playlist parsial, pembatalan, retry, dan alert offline.
- Mesin unduhan YouTube langsung di APK: pencarian judul, preview video/playlist, audio-only, dan pilihan sumber per lagu dari metadata Spotify publik eksperimental. Jalur live Spotify/YouTube belum dibuktikan dari cloud; detail di [YOUTUBE_DOWNLOADER.md](docs/YOUTUBE_DOWNLOADER.md).
- Layar Beranda, Cari, Koleksi, Impor, Pengaturan, pemutar, antrean, dan editor tag massal.

Pada 14 Oktober 2026 (Asia/Jakarta), [CI 0.2.0 berhasil](https://github.com/sagara-ds/spomaxxing/actions/runs/38437247110): analisis bersih, **69 tes lulus**, serta APK debug dan release terbangun. [Unduh APK release 0.2.0](https://github.com/sagara-ds/spomaxxing/actions/runs/38437247110/artifacts/11834325586), lalu ekstrak `app-release.apk`. Pengujian live Spotify/YouTube belum dilakukan karena akses diblokir jaringan cloud; parser Spotify publik tetap eksperimental.

Unduhan berlangsung selama aplikasi terbuka. Pekerjaan terputus dipulihkan sebagai dijeda; retry mengulang lagu yang belum selesai dari awal. Integrasi API resmi Spotify/SpotMate, WorkManager/background download, ekstraksi sampul, dan pagination koleksi besar belum tersedia.

Lihat [petunjuk build dan pengujian](docs/BUILD.md), [kontrak bridge Android](docs/NATIVE_BRIDGE.md), dan [pemutar](docs/PLAYBACK.md).

Versi 0.1.1 memperbaiki pembaruan posisi playback yang sebelumnya menyalin antrean dan membangun ulang seluruh tab. Daftar lagu sekarang dibuat secara lazy. Lihat [catatan performa](docs/PERFORMANCE.md); kelancaran pada perangkat tetap perlu diuji menggunakan APK release.

Lihat [rencana implementasi](docs/PLAN.md) untuk arsitektur, fitur, urutan pekerjaan, dan kriteria penerimaan.

Lihat [format impor](docs/IMPORT_FORMAT.md) dan [mesin unduhan YouTube](docs/YOUTUBE_DOWNLOADER.md). [Rencana impor](docs/PLAYLIST_IMPORT.md) mencatat arah fitur dan riset sebelumnya; dukungan API resmi Spotify serta SpotMate belum dikonfigurasi.
