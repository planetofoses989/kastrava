package pp.ua.kastrava

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Tracker/ad blocker. Same sources as desktop src/adblock.js
 * (EasyList + EasyPrivacy + Fanboy Cookiemonster), reduced to the part that
 * ports cleanly to WebView.shouldInterceptRequest: "||domain" host rules.
 * Subdomains match (desktop regexes anchor the same way). Refreshed every
 * 24h; the last good copy is kept on failure.
 */
class FilterLists(private val context: Context) {

    companion object {
        private const val REFRESH_MS = 24L * 60 * 60 * 1000
        private val SOURCES = listOf(
            "https://easylist.to/easylist/easylist.txt",
            "https://easylist.to/easylist/easyprivacy.txt",
            "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt",
        )
    }

    @Volatile var hosts: Set<String> = emptySet()
        private set
    @Volatile var loaded: Boolean = false
        private set

    private fun cacheFile(i: Int) = File(context.cacheDir, "filters/list$i.txt")

    fun load() {
        val now = System.currentTimeMillis()
        val cached = SOURCES.indices.mapNotNull { i ->
            val f = cacheFile(i)
            if (f.exists()) f to f.lastModified() else null
        }
        val fresh = cached.size == SOURCES.size &&
            cached.all { (_, m) -> now - m < REFRESH_MS }
        if (!fresh) {
            SOURCES.forEachIndexed { i, url ->
                try {
                    download(url, cacheFile(i))
                } catch (e: Exception) {
                    // keep the stale copy on failure
                }
            }
        }
        val out = HashSet<String>()
        SOURCES.indices.forEach { i ->
            try {
                cacheFile(i).takeIf { it.exists() }?.forEachLine { line ->
                    extractHost(line)?.let { out.add(it) }
                }
            } catch (e: Exception) { }
        }
        hosts = out
        loaded = true
    }

    fun shouldBlock(host: String?): Boolean {
        if (!loaded || host.isNullOrEmpty()) return false
        var h = host.lowercase()
        while (true) {
            if (hosts.contains(h)) return true
            val dot = h.indexOf('.')
            if (dot < 0) return false
            h = h.substring(dot + 1)
        }
    }

    private fun extractHost(line: String): String? {
        var s = line.trim()
        if (s.isEmpty() || s[0] == '!' || s[0] == '[') return null
        if (s.startsWith("@@")) return null
        val opt = s.indexOf('$')
        if (opt >= 0) s = s.substring(0, opt)
        if (!s.startsWith("||")) return null
        s = s.substring(2)
        // strip path and anchors: take up to first /, ^, |, ?, #
        val end = s.indexOfFirst { it == '/' || it == '^' || it == '|' || it == '?' || it == '#' }
        if (end >= 0) s = s.substring(0, end)
        s = s.lowercase()
        if ('*' in s || '%' in s) return null
        if (!s.contains('.') || s.length < 4) return null
        return s
    }

    private fun download(url: String, dest: File) {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            setRequestProperty("User-Agent", "Kastrava/101")
            connectTimeout = 30000
            readTimeout = 30000
            instanceFollowRedirects = true
        }
        if (conn.responseCode != 200) throw RuntimeException("HTTP ${conn.responseCode}")
        dest.parentFile?.mkdirs()
        conn.inputStream.use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }
    }
}
