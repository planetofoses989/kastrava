package pp.ua.kastrava

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.util.concurrent.atomic.AtomicLong

/**
 * Session downloads, mirroring desktop: web-derived files stream into a
 * volatile per-session area (app cache), never straight into Downloads.
 * The file reaches the shared Downloads folder only via an explicit Save.
 * The session area is wiped on exit and at launch (crash leftovers).
 */
class SessionDownloads(private val context: Context) {

    data class Item(
        val id: Long,
        val url: String,
        val filename: String,
        val file: File,
        @Volatile var received: Long = 0,
        @Volatile var total: Long = -1,
        @Volatile var state: String = "downloading",
    )

    private val seq = AtomicLong(0)
    val items = mutableListOf<Item>()

    fun dir(): File = File(context.cacheDir, "volatile-dl").apply { mkdirs() }

    fun wipe() {
        try {
            dir().deleteRecursively()
        } catch (e: Exception) { }
        synchronized(items) { items.clear() }
    }

    fun add(url: String, filename: String): Item {
        val safe = filename.ifBlank { "download" }.replace('/', '_')
        val file = File(dir(), "${seq.incrementAndGet()}_$safe")
        val item = Item(seq.get(), url, safe, file)
        synchronized(items) { items.add(0, item) }
        return item
    }

    /** Explicit user Save -> shared Downloads folder. True on success. */
    fun saveToDownloads(item: Item): Boolean {
        return try {
            if (!item.file.exists()) return false
            if (Build.VERSION.SDK_INT >= 29) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, item.filename)
                    put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(
                    MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                    values,
                ) ?: return false
                resolver.openOutputStream(uri)?.use { out ->
                    item.file.inputStream().use { it.copyTo(out) }
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                true
            } else {
                @Suppress("DEPRECATION")
                val dest = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    item.filename,
                )
                item.file.copyTo(dest, overwrite = true)
                true
            }
        } catch (e: Exception) {
            false
        }
    }
}
