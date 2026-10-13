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
- Layar Beranda, Cari, Koleksi, Impor, Pengaturan, pemutar, antrean, dan editor tag massal.

Pada 13 Oktober 2026, [CI versi 0.1.1 berhasil](https://github.com/sagara-ds/spomaxxing/actions/runs/38432386519): `flutter analyze` bersih, **62 tes lulus**, serta APK debug dan release berhasil dibangun. [Unduh APK release 0.1.1](https://github.com/sagara-ds/spomaxxing/actions/runs/38432386519/artifacts/11831178715), lalu ekstrak `app-release.apk`. Gunakan build release untuk menguji performa; kelancaran playback dan kontrol background di perangkat masih perlu diperiksa.

Unduhan versi awal berlangsung selama aplikasi terbuka. Pekerjaan terputus dipulihkan sebagai dijeda; retry mengulang lagu yang belum selesai dari awal. Integrasi provider Spotify/SpotMate, WorkManager/background download, ekstraksi sampul, dan pagination koleksi besar belum tersedia.

Lihat [petunjuk build dan pengujian](docs/BUILD.md), [kontrak bridge Android](docs/NATIVE_BRIDGE.md), dan [pemutar](docs/PLAYBACK.md).

Versi 0.1.1 memperbaiki pembaruan posisi playback yang sebelumnya menyalin antrean dan membangun ulang seluruh tab. Daftar lagu sekarang dibuat secara lazy. Lihat [catatan performa](docs/PERFORMANCE.md); kelancaran pada perangkat tetap perlu diuji menggunakan APK release.

Lihat [rencana implementasi](docs/PLAN.md) untuk arsitektur, fitur, urutan pekerjaan, dan kriteria penerimaan.

Lihat [format impor yang didukung](docs/IMPORT_FORMAT.md) untuk manifest playlist versi awal. [Rencana impor lagu/playlist dan unduhan](docs/PLAYLIST_IMPORT.md) mencatat arah fitur dan evaluasi Spotify, spotify-dl, serta SpotMate. Akses provider Spotify/SpotMate belum dikonfigurasi atau terverifikasi; tautannya dikenali dan diberi penjelasan.
