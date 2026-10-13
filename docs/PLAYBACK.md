# Pemutar lokal

`OfflineAudioHandler` adalah sumber antrean tunggal bagi UI, notifikasi Android,
lock screen, dan headset. `PlayerController` menyediakan `ChangeNotifier` bagi
UI dan callback simpan snapshot ke database lokal.

Inisialisasi dilakukan sekali setelah `WidgetsFlutterBinding.ensureInitialized()`:

```dart
final localHandler = await OfflineAudioHandler.create();
final handler = await AudioService.init<OfflineAudioHandler>(
  builder: () => localHandler,
  config: const AudioServiceConfig(
    androidNotificationChannelId: 'dev.spomaxxing.playback',
    androidNotificationChannelName: 'Pemutaran Spomaxxing',
    androidStopForegroundOnPause: true,
  ),
);
final player = PlayerController(
  handler: handler,
  onSnapshot: repository.savePlayerSnapshot,
);
await player.restoreSnapshot(savedSnapshot, localCatalogue);
```

`restoreSnapshot` memulihkan identitas lagu, posisi, urutan shuffle, riwayat,
dan mode repeat, serta membuang lagu yang tidak tersedia. Pemulihan selalu
berstatus jeda; audio baru dibuka ketika pengguna menekan Putar. Snapshot
berisi ID koleksi sehingga metadata dan referensi berkas tetap dikelola database.
Posisi tersimpan setiap lima detik ketika berubah, dan perubahan antrean/status
transport disimpan segera. Panggil `flushSnapshot()` ketika lifecycle aplikasi
meninggalkan foreground. Widget boleh melepas controller tanpa mematikan handler.

URI audio dan sampul hanya boleh `content:` atau `file:`. Pemutar tidak memuat
audio, gambar, atau metadata dari URL daring. Android harus menyediakan
`AudioServiceActivity`, service media playback, dan receiver kontrol media sesuai
manifest aplikasi.

Aturan antrean diterapkan sinkron oleh `QueueReducer`. Perintah ke `just_audio`
diserialkan dengan revisi: hasil load lama tidak bisa memulai audio setelah
pengguna mengganti lagu atau menekan Jeda. Future `play()` tidak ditunggu di
jalur perintah, sehingga Jeda/Next tetap dapat diproses. Completion membawa
token sumber audio untuk membuang event usang; Next dalam 150 ms setelah
completion otomatis dianggap kontrol pada batas lagu yang sama.

Audio yang gagal diakses atau didekode dilewati dengan pesan dan dihapus dari
antrean pemutaran saat itu. Koleksi tidak dihapus. Karena setiap kegagalan
mengurangi antrean, repeat tidak menyebabkan siklus error tanpa akhir. Antrean
berhenti jika tidak memiliki lagu berikutnya.

Audio session memakai konfigurasi musik. Interupsi pause menyimpan niat putar
sebelumnya, duck menurunkan volume sementara, dan headset yang terlepas menjeda.
Resume setelah interupsi pause hanya terjadi jika sebelumnya sedang diputar dan
pengguna tidak melakukan kontrol transport saat interupsi. Interupsi unknown
tidak menyebabkan resume otomatis.

Validasi perangkat masih diperlukan untuk URI MediaStore, format audio, layar
mati, notifikasi, headset, audio focus, dan batasan baterai/vendor Android.
Pemeriksaan statis atau unit test tidak membuktikan perilaku perangkat tersebut.
