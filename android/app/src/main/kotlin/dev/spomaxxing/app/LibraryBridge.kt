package dev.spomaxxing.app

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** Local-only MediaStore, SAF imports, decoder verification, and storage information. */
internal class LibraryBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "dev.spomaxxing/library")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val disposed = AtomicBoolean(false)
    private val replies = mutableSetOf<Reply>()
    private var permissionReply: Reply? = null
    private var pickerReply: Reply? = null
    private val importDirectory get() = File(context.filesDir, "imports")

    init {
        channel.setMethodCallHandler(this)
        worker.execute {
            // Only our unfinished SAF copies use this prefix; downloaded files are untouched.
            importDirectory.listFiles()?.filter {
                it.isFile && it.name.startsWith(".local-") && it.extension == "part"
            }?.forEach { it.delete() }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed.get()) {
            result.error("activity_unavailable", "Aktivitas tidak tersedia. Buka kembali aplikasi.", null)
            return
        }
        when (call.method) {
            "requestAudioPermission" -> requestAudioPermission(Reply(result))
            "scanAudio" -> execute(Reply(result)) { scanAudio() }
            "pickAudio" -> pickAudio(Reply(result))
            "validateAudio" -> {
                val value = call.argument<String>("uri")
                if (value.isNullOrBlank()) {
                    result.error("invalid_argument", "URI audio diperlukan.", null)
                } else {
                    execute(Reply(result)) { readMetadata(parseLocalUri(value)) }
                }
            }
            "hasConnection" -> execute(Reply(result)) { hasConnection() }
            "storageInfo" -> execute(Reply(result)) { storageInfo() }
            else -> result.notImplemented()
        }
    }

    private fun audioPermission(): String = if (Build.VERSION.SDK_INT >= 33) {
        Manifest.permission.READ_MEDIA_AUDIO
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

    private fun hasAudioPermission(): Boolean =
        context.checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    private fun requestAudioPermission(reply: Reply) {
        if (hasAudioPermission()) {
            reply.success(true)
        } else if (permissionReply != null) {
            reply.error("busy", "Permintaan izin audio sedang berlangsung.")
        } else {
            permissionReply = reply
            try {
                activity.requestPermissions(arrayOf(audioPermission()), PERMISSION_REQUEST)
            } catch (error: Exception) {
                permissionReply = null
                reply.error("permission_error", error.message ?: "Izin audio tidak dapat diminta.")
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val reply = permissionReply ?: return
        permissionReply = null
        reply.success(grantResults.isNotEmpty() && hasAudioPermission())
    }

    private fun pickAudio(reply: Reply) {
        if (pickerReply != null) {
            reply.error("busy", "Pemilih berkas audio sedang terbuka.")
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "application/ogg"))
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pickerReply = reply
        try {
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (error: Exception) {
            pickerReply = null
            reply.error("picker_unavailable", "Pemilih berkas tidak tersedia: ${error.message.orEmpty()}")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_REQUEST) return
        val reply = pickerReply ?: return
        pickerReply = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            reply.success(mapOf("tracks" to emptyList<Any>(), "errors" to emptyList<String>()))
            return
        }
        val uris = linkedSetOf<Uri>()
        data.data?.let(uris::add)
        data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) uris.add(clip.getItemAt(index).uri)
        }
        execute(reply) {
            val tracks = mutableListOf<Map<String, Any?>>()
            val errors = mutableListOf<String>()
            for (uri in uris) {
                ensureActive()
                try {
                    tracks.add(importAudio(uri))
                } catch (error: Exception) {
                    ensureActive()
                    errors.add("${displayName(uri)}: ${error.message ?: "Berkas tidak dapat diimpor."}")
                }
            }
            mapOf("tracks" to tracks, "errors" to errors)
        }
    }

    private fun scanAudio(): List<Map<String, Any?>> {
        if (!hasAudioPermission()) {
            throw BridgeFailure("permission_denied", "Izinkan akses audio untuk memindai musik perangkat.")
        }
        val tracks = mutableListOf<Map<String, Any?>>()
        val volumes = if (Build.VERSION.SDK_INT >= 29) {
            MediaStore.getExternalVolumeNames(context).sorted()
        } else {
            listOf("external")
        }
        for (volume in volumes) {
            ensureActive()
            val collection = MediaStore.Audio.Media.getContentUri(volume)
            val projection = mutableListOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.DURATION,
            )
            if (Build.VERSION.SDK_INT >= 30) projection.add(MediaStore.Audio.Media.GENRE)
            val selection = if (Build.VERSION.SDK_INT >= 29) {
                "${MediaStore.Audio.Media.IS_PENDING} = 0"
            } else {
                null
            }
            context.contentResolver.query(
                collection, projection.toTypedArray(), selection, null,
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    ensureActive()
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID))
                    val uri = ContentUris.withAppendedId(collection, id)
                    fun value(column: String): String? {
                        val columnIndex = cursor.getColumnIndex(column)
                        return if (columnIndex < 0 || cursor.isNull(columnIndex)) null else cursor.getString(columnIndex)
                    }
                    val fallback = value(MediaStore.Audio.Media.DISPLAY_NAME)?.substringBeforeLast('.') ?: "Audio"
                    val duration = value(MediaStore.Audio.Media.DURATION)?.toLongOrNull() ?: 0L
                    if (duration <= 0) continue
                    val accessible = try {
                        context.contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false
                    } catch (_: IOException) {
                        false
                    } catch (_: SecurityException) {
                        false
                    }
                    tracks.add(
                        mapOf(
                            "id" to "media:$volume:$id",
                            "uri" to uri.toString(),
                            "title" to cleanMetadata(value(MediaStore.Audio.Media.TITLE), fallback),
                            "artist" to cleanMetadata(value(MediaStore.Audio.Media.ARTIST), "Artis tidak diketahui"),
                            "album" to cleanMetadata(value(MediaStore.Audio.Media.ALBUM), "Album tidak diketahui"),
                            "durationMs" to duration,
                            "genre" to if (Build.VERSION.SDK_INT >= 30) value(MediaStore.Audio.Media.GENRE) else null,
                            "isAvailable" to accessible,
                        ),
                    )
                }
            }
        }
        return tracks
    }

    private fun displayName(uri: Uri): String = try {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment ?: "Audio"
    } catch (_: Exception) {
        uri.lastPathSegment ?: "Audio"
    }

    private fun importAudio(uri: Uri): Map<String, Any?> {
        if (uri.scheme != "content") throw BridgeFailure("invalid_audio", "Pilih berkas melalui pemilih sistem.")
        val name = displayName(uri)
        val advertisedSize = context.contentResolver.query(
            uri, arrayOf(OpenableColumns.SIZE), null, null, null,
        )?.use {
            if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
        }
        if (advertisedSize != null && advertisedSize > MAX_FILE_BYTES) {
            throw BridgeFailure("file_too_large", "Ukuran berkas melebihi batas 256 MiB.")
        }
        val directory = importDirectory
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Folder impor tidak dapat dibuat.")
        if (StatFs(directory.absolutePath).availableBytes < (advertisedSize ?: 0L).coerceAtLeast(0L) + SPACE_RESERVE_BYTES) {
            throw BridgeFailure("storage_full", "Ruang penyimpanan tidak cukup untuk mengimpor berkas.")
        }
        val identifier = UUID.randomUUID().toString()
        val partial = File(directory, ".local-$identifier.part")
        var destination: File? = null
        try {
            val input = context.contentResolver.openInputStream(uri)
                ?: throw IOException("Berkas tidak dapat dibuka.")
            var copied = 0L
            input.use { source ->
                FileOutputStream(partial).use { target ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        ensureActive()
                        val count = source.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > MAX_FILE_BYTES) throw BridgeFailure("file_too_large", "Ukuran berkas melebihi batas 256 MiB.")
                        if (copied % SPACE_RESERVE_BYTES < count &&
                            StatFs(directory.absolutePath).availableBytes < SPACE_RESERVE_BYTES
                        ) {
                            throw BridgeFailure("storage_full", "Ruang penyimpanan tidak cukup untuk mengimpor berkas.")
                        }
                        target.write(buffer, 0, count)
                    }
                    target.fd.sync()
                }
            }
            if (copied == 0L) throw BridgeFailure("invalid_audio", "Berkas audio kosong.")
            if (advertisedSize != null && advertisedSize >= 0 && copied != advertisedSize) {
                throw BridgeFailure("incomplete_audio", "Salinan audio tidak lengkap. Unduh berkas lokal terlebih dahulu.")
            }
            val metadata = readMetadata(Uri.fromFile(partial), name.substringBeforeLast('.').ifBlank { "Audio" })
            ensureActive()
            val extension = name.substringAfterLast('.', "audio").lowercase().takeIf {
                it in setOf("mp3", "aac", "m4a", "flac", "wav", "ogg", "oga", "opus")
            } ?: "audio"
            destination = File(directory, "$identifier.$extension")
            if (!partial.renameTo(destination)) throw IOException("Berkas impor tidak dapat disimpan.")
            ensureActive()
            return metadata + mapOf(
                "id" to "import:$identifier",
                "uri" to Uri.fromFile(destination).toString(),
                "genre" to null,
                "isAvailable" to true,
            )
        } catch (error: Exception) {
            destination?.delete()
            throw error
        } finally {
            partial.delete()
        }
    }

    private fun parseLocalUri(value: String): Uri {
        val uri = Uri.parse(value)
        if (uri.scheme !in setOf("content", "file")) {
            throw BridgeFailure("invalid_audio", "Validasi hanya mendukung berkas audio lokal.")
        }
        return uri
    }

    private fun readMetadata(uri: Uri, fallbackTitle: String = displayName(uri)): Map<String, Any?> {
        ensureActive()
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?: throw BridgeFailure("invalid_audio", "Durasi audio tidak dapat dibaca.")
            if (duration <= 0) throw BridgeFailure("invalid_audio", "Berkas tidak berisi audio yang dapat diputar.")
            verifyDecoder(uri)
            return mapOf(
                "durationMs" to duration,
                "title" to cleanMetadata(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE), fallbackTitle),
                "artist" to cleanMetadata(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST), "Artis tidak diketahui"),
                "album" to cleanMetadata(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM), "Album tidak diketahui"),
            )
        } catch (error: BridgeFailure) {
            throw error
        } catch (error: Exception) {
            throw BridgeFailure("invalid_audio", "Berkas rusak, tidak dapat diakses, atau format audio tidak didukung.")
        } finally {
            retriever.release()
        }
    }

    /** Decode a sample before publishing a copied file; extensions alone are insufficient. */
    private fun verifyDecoder(uri: Uri) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var started = false
        try {
            extractor.setDataSource(context, uri, null)
            if (extractor.drmInitData != null) throw BridgeFailure("protected_audio", "Audio berproteksi DRM tidak dapat diimpor.")
            var audioTrack = -1
            for (index in 0 until extractor.trackCount) {
                if (extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    audioTrack = index
                    break
                }
            }
            if (audioTrack < 0) throw BridgeFailure("invalid_audio", "Berkas tidak memiliki track audio.")
            extractor.selectTrack(audioTrack)
            val format = extractor.getTrackFormat(audioTrack)
            if (format.getString(MediaFormat.KEY_MIME) == "audio/raw") {
                if (extractor.readSampleData(ByteBuffer.allocate(1024 * 1024), 0) <= 0) {
                    throw BridgeFailure("invalid_audio", "Data audio kosong atau rusak.")
                }
                return
            }
            val decoder = MediaCodecList(MediaCodecList.REGULAR_CODECS).findDecoderForFormat(format)
                ?: throw BridgeFailure("unsupported_audio", "Codec audio tidak didukung perangkat ini.")
            val activeCodec = MediaCodec.createByCodecName(decoder)
            codec = activeCodec
            activeCodec.configure(format, null, null, 0)
            activeCodec.start()
            started = true
            val info = MediaCodec.BufferInfo()
            val deadline = SystemClock.elapsedRealtime() + 5_000L
            var inputEnded = false
            while (SystemClock.elapsedRealtime() < deadline) {
                ensureActive()
                if (!inputEnded) {
                    val inputIndex = activeCodec.dequeueInputBuffer(10_000L)
                    if (inputIndex >= 0) {
                        val buffer = activeCodec.getInputBuffer(inputIndex)
                            ?: throw BridgeFailure("invalid_audio", "Buffer decoder tidak tersedia.")
                        buffer.clear()
                        if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED != 0) {
                            throw BridgeFailure("protected_audio", "Audio berproteksi DRM tidak dapat diimpor.")
                        }
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) {
                            activeCodec.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            activeCodec.queueInputBuffer(inputIndex, 0, count, extractor.sampleTime.coerceAtLeast(0), 0)
                            extractor.advance()
                        }
                    }
                }
                val outputIndex = activeCodec.dequeueOutputBuffer(info, 10_000L)
                if (outputIndex >= 0) {
                    val hasAudio = info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                    activeCodec.releaseOutputBuffer(outputIndex, false)
                    if (hasAudio) return
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            throw BridgeFailure("invalid_audio", "Decoder tidak dapat membaca sampel audio.")
        } finally {
            try {
                if (started) codec?.stop()
            } catch (_: Exception) {
                // A failing decoder still needs to be released.
            }
            try {
                codec?.release()
            } finally {
                extractor.release()
            }
        }
    }

    private fun cleanMetadata(value: String?, fallback: String): String =
        value?.trim()?.takeIf { it.isNotEmpty() && it != "<unknown>" } ?: fallback

    private fun hasConnection(): Boolean {
        val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivity.activeNetwork ?: return false
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun storageInfo(): Map<String, Long> {
        val storage = StatFs(context.filesDir.absolutePath)
        val imported = importDirectory.listFiles()?.filter { it.isFile && it.extension != "part" }
            ?.sumOf { it.length() } ?: 0L
        return mapOf(
            "freeBytes" to storage.availableBytes,
            "importedBytes" to imported,
            "bytesAvailable" to storage.availableBytes,
            "bytesTotal" to storage.totalBytes,
        )
    }

    private fun ensureActive() {
        if (disposed.get() || Thread.currentThread().isInterrupted) {
            throw BridgeFailure("activity_unavailable", "Operasi dibatalkan karena aktivitas ditutup.")
        }
    }

    private fun execute(reply: Reply, operation: () -> Any?) {
        try {
            worker.execute {
                try {
                    ensureActive()
                    reply.success(operation())
                } catch (error: BridgeFailure) {
                    reply.error(error.code, error.message ?: "Operasi tidak dapat diselesaikan.")
                } catch (_: SecurityException) {
                    reply.error("permission_denied", "Akses berkas ditolak. Berikan izin audio atau pilih ulang berkas.")
                } catch (error: Exception) {
                    reply.error("library_error", error.message ?: "Operasi koleksi gagal.")
                }
            }
        } catch (_: RejectedExecutionException) {
            reply.error("activity_unavailable", "Aktivitas ditutup. Coba lagi saat aplikasi terbuka.")
        }
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        permissionReply = null
        pickerReply = null
        worker.shutdownNow()
        val pending = synchronized(replies) { replies.toList() }
        pending.forEach { it.error("activity_unavailable", "Aktivitas ditutup. Coba lagi saat aplikasi terbuka.") }
    }

    private inner class Reply(private val result: MethodChannel.Result) {
        private val finished = AtomicBoolean(false)

        init {
            synchronized(replies) { replies.add(this) }
        }

        fun success(value: Any?) = complete { result.success(value) }

        fun error(code: String, message: String) = complete { result.error(code, message, null) }

        private fun complete(callback: () -> Unit) {
            if (!finished.compareAndSet(false, true)) return
            synchronized(replies) { replies.remove(this) }
            main.post { callback() }
        }
    }

    private class BridgeFailure(val code: String, message: String) : Exception(message)

    private companion object {
        const val PERMISSION_REQUEST = 5810
        const val PICK_REQUEST = 5811
        const val MAX_FILE_BYTES = 256L * 1024 * 1024
        const val SPACE_RESERVE_BYTES = 4L * 1024 * 1024
    }
}
