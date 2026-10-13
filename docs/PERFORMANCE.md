# Perbaikan performa 0.1.1

Laporan pengguna: pemindaian perangkat membuat freeze dan playback membuat UI tersendat. Ini bukan perilaku yang diterima sebagai normal.

Sumber beban yang ditemukan dalam kode:

- Posisi playback sebelumnya diperbarui melalui QueueReducer; setiap tick membangun ulang daftar dan indeks seluruh antrean.
- PlayerController meneruskan tick sebagai perubahan umum; root aplikasi mendengarkan perubahan itu sehingga semua tab dibangun ulang.
- LibraryView membuat seluruh ListTile dalam Column, termasuk koleksi besar.

Perbaikan:

- Posisi memiliki ValueNotifier tersendiri dengan periode 250–500 ms; tick tidak membuat QueueState baru.
- Notifikasi transport dipisahkan dari posisi. Root/tab tidak mendengarkan tick; progres di layar pemutar tetap bergerak.
- Snapshot memakai posisi live, disimpan maksimal setiap lima detik. Kontrol Previous tetap memeriksa posisi live.
- Koleksi dan hasil pencarian memakai SliverList/ListView.builder. Tes 10.000 lagu memastikan hanya baris yang terlihat dibuat.
- Progres unduhan memakai stream pada tab Impor dan tidak memicu rebuild global.
- Pemindaian perangkat tidak tersedia di alur UI; izin READ_MEDIA_AUDIO/READ_EXTERNAL_STORAGE dihapus. Pemilih berkas sistem menyalin hanya audio yang dipilih.
- Koleksi dibaca dengan filter sumber impor di SQL, sehingga hasil pemindaian lama tidak ikut dimuat atau dicampurkan. Rekor lama dan file asli tetap disimpan.
- Workflow membuat APK release dengan kompilasi AOT untuk pengujian performa. Signing tetap development/debug, bukan signing produksi store.

[CI 0.1.1](https://github.com/sagara-ds/spomaxxing/actions/runs/38432386519) berhasil: analisis tanpa isu, 62 tes lulus, APK debug dan release terbangun. [APK release](https://github.com/sagara-ds/spomaxxing/actions/runs/38432386519/artifacts/11831178715) berukuran 51.492.698 byte (ZIP unduhan 24.270.624 byte). SHA-256 APK: `4bd117557763e486d7c3f8846a79c17938b81f869d78e47453775bed30ed7026`.

Manifest APK akhir telah diperiksa: package `dev.spomaxxing.app`, versi `0.1.1`, versionCode `2`, minSdk 26, targetSdk 35; tidak ada izin READ_MEDIA_AUDIO atau READ_EXTERNAL_STORAGE. Media playback service tetap ada.

Belum ada pengukuran FPS/profiling di ponsel pengguna. Analisis dan tes tidak membuktikan hilangnya seluruh jank pada perangkat; uji release dengan jumlah lagu yang sama, playback layar aktif/mati, seek, dan perpindahan tab.

Untuk folder khusus, pindahkan berkas asli ke folder musik pilihan pengguna, tekan Impor lagu pilihan, buka folder tersebut di pemilih berkas, lalu pilih satu/beberapa audio. Ini bukan pemantauan folder otomatis.

Tautan Spotify tidak berisi audio untuk diunduh. Mengganti Flutter dengan Kotlin atau membuat downloader Python tidak menghilangkan kebutuhan akses metadata dan sumber audio. Versi ini tetap mendukung audio HTTPS langsung dan manifest JSON yang diizinkan; playlist Spotify yang dilaporkan belum bisa diunduh langsung.

APK pengembangan dari runner berbeda bisa memakai signing key berbeda. Jika Android menolak update karena tanda tangan, uninstall akan menghapus koleksi privat, playlist, dan tag. Simpan berkas asli di folder pengguna sebelum melakukan uninstall; jangan mengandalkan penyimpanan privat aplikasi sebagai satu-satunya salinan.
