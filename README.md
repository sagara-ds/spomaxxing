# Spomaxxing

Pemutar musik Android pribadi berbasis Flutter. Koleksi lokal + impor Spotify untuk didengar offline.

## Cara pakai

1. Buka tab **Impor**, tempel tautan Spotify (lagu/playlist), centang izin, tekan **Pratinjau tautan**.
2. Kalau diminta, selesaikan verifikasi Spotdown di WebView (cukup sekali per sesi).
3. Pilih lagu → **Unduh** → putar dari **Koleksi** tanpa internet.

Unduhan berjalan selama aplikasi terbuka. Lagu gagal bisa diulang lewat **Coba lagi**; yang sudah tersimpan tidak ikut diunduh ulang.

## Sumber audio

- **Utama:** Spotdown (metadata + MP3). Token sesi hanya di memori, tidak disimpan.
- **Cadangan:** ekstraksi YouTube lokal di perangkat, dipakai otomatis kalau Spotdown gagal untuk lagu tertentu.

Spotdown adalah layanan pihak ketiga yang bisa berubah sewaktu-waktu; kalau endpoint-nya berubah, perbaikannya cukup di `lib/features/imports/spotdown_source.dart`.

## Build & tes

Butuh Flutter 3.47.2+ (Dart ^3.10.0).

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug   # atau --release
```

Detail arsitektur ada di `docs/` (`PLAN.md`, `PLAYLIST_IMPORT.md`, `YOUTUBE_DOWNLOADER.md`, `BUILD.md`).
