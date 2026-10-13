# Spomaxxing

Rencana aplikasi pemutar musik Android dengan pemutaran offline dan impor playlist daring, dibuat dengan Flutter, Dart, dan Kotlin. Antarmuka menggunakan palet hijau dan hitam dengan identitas Spomaxxing sendiri.

## Keputusan awal

- Platform pertama: Android.
- Sumber musik: berkas audio perangkat dan unduhan dari sumber yang mengizinkan pengunduhan.
- Pencarian suasana: kata kunci dan tag lokal, seperti santai, fokus, sedih, dan semangat.
- Fitur utama: koleksi lokal, pencarian, radio mix, shuffle, perpindahan lagu otomatis, dan pemutaran latar belakang.
- Internet digunakan saat pengguna mengimpor tautan atau mengunduh audio. Playback, pencarian koleksi, dan radio lokal tetap berjalan tanpa internet.
- Saat pengguna mencoba mengunduh tanpa koneksi, tampilkan alert. Lagu yang sudah tersimpan tetap dapat diputar.

"Semua lagu" berarti seluruh berkas audio yang dapat diakses aplikasi dalam koleksi pengguna. Ketersediaan lagu bergantung pada berkas yang dimiliki pengguna; aplikasi tidak menyediakan katalog atau audio Spotify.

## Status

Repositori saat ini berisi perencanaan. Kode aplikasi, dependensi Flutter, dan build APK belum dibuat atau diuji.

Lihat [rencana implementasi](docs/PLAN.md) untuk arsitektur, fitur, urutan pekerjaan, dan kriteria penerimaan.

Lihat [rencana impor tautan playlist dan unduhan](docs/PLAYLIST_IMPORT.md) untuk alur tempel tautan, status unduhan, alert offline, serta batas integrasi Spotify dan spotify-dl. Pengguna telah memilih impor langsung di Android dengan internet saat dibutuhkan.
