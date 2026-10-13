# Mesin unduhan 0.2.0

Mesin bekerja langsung di Android dengan Dart, memakai `youtube_explode_dart` 3.1.0 (BSD-3-Clause). Tidak ada server tambahan, API key pengguna, Python, FFmpeg, login YouTube, atau pengambilan cookie akun. Lisensi dependency dapat dibuka melalui Pengaturan.

## Alur pengguna

1. Buka Impor dan tempel tautan lagu/playlist Spotify atau YouTube. Alternatifnya, tekan Cari judul di YouTube dan masukkan judul/artis.
2. Untuk Spotify, aplikasi mencoba membaca metadata dari halaman embed publik. Ini jalur eksperimental, bukan integrasi Spotify Web API resmi. Playlist privat/radio personal, halaman tanpa daftar lengkap, dan perubahan format dapat gagal. Daftar kosong atau lebih dari 100 lagu ditolak, bukan dibuat seolah selesai.
3. Pilih hasil YouTube untuk setiap lagu Spotify yang ingin diunduh. Dialog menampilkan judul, kanal, dan durasi; pencarian bisa diedit. Tidak ada pencocokan/unduhan otomatis ke hasil pertama. Metadata asal dan sumber video pilihan disimpan terpisah melalui provenance pekerjaan.
4. Konfirmasikan izin unduh, pilih lagu yang sudah mempunyai sumber, kemudian tekan Unduh. Tautan video/playlist YouTube langsung menampilkan pratinjau sumber yang diberikan.
5. Mesin mengambil manifest stream terbaru per video dan memilih audio-only M4A bila tersedia, atau WebM. Tidak ada konversi ke MP3 atau klaim kualitas asli Spotify.
6. Transfer serial memakai batas 256 MiB, timeout, hash konten, berkas `.part`, validasi decoder Android, dan rename sebelum publikasi koleksi. Playlist parsial mempertahankan slot gagal dan urutan sumber.
7. Jika koneksi terputus, retry mengunduh lagu yang belum selesai dari awal. URL Googlevideo baru diambil saat retry; URL stream bertanda tangan/kedaluwarsa tidak disimpan sebagai identitas sumber. Berkas yang sudah selesai tetap offline dan pemutar tidak menggunakan URL YouTube.

Unduhan masih memerlukan aplikasi tetap terbuka. Codec mengikuti Android; bila decoder tidak mendukung container hasil ekstraksi, lagu ditandai gagal. Video privat, berbayar, dibatasi umur/login, siaran langsung, atau layanan yang menolak ekstraksi tidak dianggap didukung. Tidak ada solusi captcha, proxy untuk menghindari penolakan, atau autentikasi dengan akun pengguna.

## Implementasi

- `youtube_source.dart`: metadata embed Spotify eksperimental, pencarian/video/playlist YouTube, pilihan stream dan lifecycle HTTP client.
- `import_service.dart`: batas ukuran, antrean transfer, pembatalan, penyimpanan, retry, serta publikasi lokal. Provider diinjeksi supaya tes tidak membutuhkan internet.
- `import_screen.dart`: pilihan hasil per lagu, pencarian manual, preview lazy, status dan konfirmasi unduh.
- `ImportCandidate.provider`: `direct`, `spotify` (metadata belum memiliki sumber), atau `youtube` (video yang dipilih). Field baru opsional pada JSON lama; pekerjaan audio langsung sebelumnya tetap terbaca.

## Batas verifikasi

Jaringan lingkungan cloud menolak akses `open.spotify.com` dan `www.youtube.com` dengan HTTP 403 dari proxy. Parser metadata diuji memakai fixture sintetis; extractor diperiksa terhadap source package dan dikompilasi bersama aplikasi. Tes resolver menggunakan transport audio uji. Ini tidak membuktikan bahwa playlist Spotify tertentu dapat dibaca atau audio YouTube benar-benar berhasil diunduh pada saat ini.

Uji live yang diperlukan: buka playlist yang diberikan pengguna, periksa jumlah/judul/urutan metadata, pilih video yang diizinkan, unduh hingga selesai, aktifkan mode pesawat, lalu putar. Uji juga Spotify privat/tidak tersedia, YouTube ditolak, sumber berbeda versi, koneksi putus, retry dengan URL baru, pembatalan, dan restart proses. Perubahan Spotify/YouTube dapat membuat extractor berhenti bekerja sehingga pembaruan dependency diperlukan.

## Hasil build

[CI 0.2.0](https://github.com/sagara-ds/spomaxxing/actions/runs/38437247110) pada 14 Oktober 2026 (Asia/Jakarta) lulus analisis, 69 tes, serta build debug/release. [APK release](https://github.com/sagara-ds/spomaxxing/actions/runs/38437247110/artifacts/11834325586) terverifikasi versi 0.2.0+3, tanpa izin baca seluruh koleksi audio. Lisensi BSD extractor terdapat dalam NOTICES APK. Ini validasi kompilasi/unit, bukan verifikasi live provider.
