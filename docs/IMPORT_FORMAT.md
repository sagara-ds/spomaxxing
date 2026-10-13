# Impor versi awal

Tab Impor mendukung URL HTTPS langsung berkas MP3/M4A/AAC/WAV/FLAC/Ogg/Opus/MP4, URL HTTPS manifest `.json`, serta tautan video/playlist YouTube. Metadata Spotify publik dibaca secara eksperimental, lalu pengguna memilih sumber YouTube per lagu. Lihat [mesin unduhan](YOUTUBE_DOWNLOADER.md) untuk alur dan batas verifikasi. Format akhir mengikuti decoder perangkat; halaman web lain dan URL pendek Spotify belum didukung.

Untuk URL audio langsung, pengguna mengonfirmasi izin unduh. Manifest membutuhkan `source` dan `license` untuk setiap rekaman. Jangan memakai URL contoh di bawah sebagai sumber audio; unggah berkas uji milik sendiri pada host HTTPS yang Anda kendalikan.

```json
{
  "version": 1,
  "name": "Playlist uji saya",
  "tracks": [
    {
      "id": "tone-01",
      "title": "Nada buatan sendiri",
      "artist": "Pembuat audio uji",
      "url": "https://example.com/audio/tone.wav",
      "source": "Rekaman yang saya buat sendiri",
      "license": "Diizinkan untuk diunduh dan disimpan",
      "sha256": "CHECKSUM_HEKSADESIMAL_64_DIGIT"
    }
  ]
}
```

`sha256` opsional; hapus field itu atau ganti placeholder dengan SHA-256 audio sebenarnya. ID harus unik dalam manifest. Manifest dibatasi 1 MiB dan 100 lagu, audio 256 MiB per berkas. Redirect tetap harus HTTPS. HTML, status HTTP gagal, transfer tidak lengkap, checksum salah, atau audio yang tidak dapat didekode ditolak.

Audio ditulis ke `.part`, diverifikasi, lalu di-rename sebelum masuk koleksi. Sumber/lisensi/checksum dan status per lagu disimpan pada pekerjaan impor. Identitas audio unduhan berdasarkan hash konten; impor ulang mempertahankan tag serta favorit. Playlist menyimpan urutan lagu dan placeholder untuk yang belum berhasil, dengan jumlah audio tersedia offline ditampilkan di Koleksi.

Unduhan berjalan serial selama aplikasi terbuka. Setelah koneksi terputus atau proses dimulai kembali, pilih **Coba lagi** pada pekerjaan dijeda. Lagu yang sudah selesai tidak diunduh ulang; lagu belum selesai dimulai dari byte nol. Tidak ada klaim resume byte atau transfer background yang dijamin. Pemutaran hanya membaca URI lokal.
