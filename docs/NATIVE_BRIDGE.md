# Bridge Android untuk koleksi lokal

`MainActivity` mewarisi `AudioServiceActivity`. Integrasi pada channel
`dev.spomaxxing/library` berada di `LibraryBridge.kt`; query, salinan berkas,
validasi decoder, dan informasi penyimpanan berjalan pada executor tunggal.
Pemutaran tetap ditangani oleh `just_audio` dan `audio_service`.

## Kontrak channel

| Metode | Argumen | Hasil |
| --- | --- | --- |
| `requestAudioPermission` | tidak ada | `bool`, termasuk `false` ketika izin ditolak/dibatalkan |
| `scanAudio` | tidak ada | `List<Map>` audio MediaStore dengan durasi positif |
| `pickAudio` | tidak ada | `{tracks: List<Map>, errors: List<String>}`; pembatalan menghasilkan dua daftar kosong |
| `validateAudio` | `{uri: String}` | `{durationMs: int, title: String, artist: String, album: String}` |
| `hasConnection` | tidak ada | `bool`: jaringan aktif memiliki kemampuan internet dan validasi Android |
| `storageInfo` | tidak ada | `{freeBytes: int, importedBytes: int, bytesAvailable: int, bytesTotal: int}` |

Track memiliki `id`, `uri`, `title`, `artist`, `album`, `durationMs`, `genre`
(dapat `null`), serta `isAvailable`. Identitas MediaStore berbentuk
`media:<volume>:<id>` dan memakai URI `content://`, tanpa membaca kolom path
mentah. Metadata genre dibaca pada API 30 ke atas. Pemindaian menguji apakah URI
dapat dibuka; decoding seluruh koleksi dilakukan saat pemutaran, bukan saat scan.

Track yang disalin dari pemilih sistem memiliki identitas `import:<UUID>` dan
URI `file://` ke `context.filesDir/imports`. Direktori itu sama dengan
`getApplicationSupportDirectory()/imports` di Flutter. `bytesAvailable` merupakan
alias `freeBytes`; `importedBytes` menghitung berkas lengkap dalam direktori impor
dan mengecualikan `.part`.

## Izin dan kegagalan

Android 13 ke atas memakai `READ_MEDIA_AUDIO`; Android 8–12 memakai
`READ_EXTERNAL_STORAGE`. Scan yang tidak memiliki izin mengembalikan
`PlatformException` dengan kode `permission_denied`. SAF tidak memerlukan izin
scan, sehingga pengguna tetap dapat memasukkan berkas setelah menolak izin.
Manifest juga membutuhkan `ACCESS_NETWORK_STATE` untuk pemeriksaan koneksi.

Pemilih `ACTION_OPEN_DOCUMENT` mendukung beberapa berkas dan meminta
`EXTRA_LOCAL_ONLY`; pengguna harus menyiapkan berkas provider cloud secara lokal.
Setiap berkas diproses terpisah: kegagalan masuk ke `errors`, sedangkan berkas lain
yang berhasil tetap dikembalikan. Picker dan permintaan izin kedua yang tumpang
tindih menghasilkan `busy`.

Salinan dibatasi 256 MiB per berkas, memakai nama privat acak, memeriksa ruang
tersedia dan jumlah byte, menjalankan `fsync`, lalu membaca metadata dan sampel
audio dengan decoder Android. Audio DRM, berkas kosong, transfer tidak lengkap,
dan codec yang tidak tersedia ditolak. Berkas `.local-<UUID>.part` dihapus saat
gagal atau saat bridge berikutnya dibuat. Rename dilakukan di direktori yang sama
setelah validasi, sehingga berkas sementara tidak dikembalikan sebagai track.

`validateAudio` menerima URI `content://` dan `file://` lokal; URL jaringan ditolak.
Kode kegagalan mencakup `invalid_audio`, `unsupported_audio`, `protected_audio`,
`file_too_large`, `incomplete_audio`, `storage_full`, dan `activity_unavailable`.
Pesan picker menyertakan nama berkas. Metadata kosong memakai nama berkas serta
artis/album bawaan.

Operasi menunggu diselesaikan sekali ketika Activity/engine dilepas. Executor
dibatalkan dan kode `activity_unavailable` memungkinkan Dart mencoba kembali.
Bridge ini tidak menyediakan transfer background atau pekerjaan yang bertahan
setelah proses dihentikan. File yang sudah disalin tetapi belum dicatat ke SQLite
ketika proses mati perlu rekonsiliasi oleh lapisan koleksi.

## Pemeriksaan yang sudah dijalankan

Pada 13 Oktober 2026, kedua file Kotlin berhasil dikompilasi menggunakan compiler
Kotlin 2.1.0, target JVM 11, dan `android.jar` dari Android SDK Platform 36 revision
2 resmi. SHA-1 arsip platform sesuai metadata Google:
`2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576`.

Pemeriksaan mandiri memakai stub sementara untuk `FlutterEngine`,
`BinaryMessenger`, `MethodCall`, `MethodChannel`, dan `AudioServiceActivity`;
signatur Flutter diperiksa terhadap source Flutter 3.35.4. Artifact validasi
berada di `/workspace/work/native-check`, di luar repository. Pemeriksaan ini
membuktikan sintaks Kotlin dan referensi API Android, tetapi belum membuktikan
build APK, integrasi plugin, perilaku izin/picker, atau playback di perangkat.

Sesudah pemeriksaan mandiri tersebut, [CI Android #2](https://github.com/sagara-ds/spomaxxing/actions/runs/38424252024) berhasil membangun APK debug dengan dependensi Flutter/AudioService sebenarnya. Kompilasi integrasi plugin kini terverifikasi; pengujian izin, picker, decoder, dan playback pada perangkat tetap belum dilakukan.

Validasi decoder membaca sampel awal dan metadata, bukan seluruh durasi berkas;
kerusakan pada bagian akhir tetap dapat muncul sebagai error saat playback.
Ketersediaan codec, kontrol media/background, dan impor MP3/AAC/M4A/FLAC/WAV/Ogg
perlu pengujian Android 8 dan Android terbaru sebelum format dinyatakan didukung
end-to-end. Pemeriksaan koneksi tervalidasi juga tidak menjamin endpoint provider
dapat diakses; importer tetap menangani error HTTP sebenarnya.
