package pp.ua.kastrava

import android.content.Context
import androidx.preference.PreferenceManager
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bookmarks survive on purpose: they are the user's own saved places, not
 * website data. Everything else still wipes on exit.
 */
data class Bookmark(val title: String, val url: String)

class BookmarkStore(context: Context) {
    private val p = PreferenceManager.getDefaultSharedPreferences(context)

    fun load(): MutableList<Bookmark> {
        val out = mutableListOf<Bookmark>()
        try {
            val arr = JSONArray(p.getString("bookmarks", "[]") ?: "[]")
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val url = o.optString("url")
                if (url.startsWith("http")) out.add(Bookmark(o.optString("title", url), url))
            }
        } catch (e: Exception) { }
        return out
    }

    private fun save(list: List<Bookmark>) {
        val arr = JSONArray()
        list.forEach { arr.put(JSONObject().put("title", it.title).put("url", it.url)) }
        p.edit().putString("bookmarks", arr.toString()).apply()
    }

    fun contains(url: String): Boolean = load().any { it.url == url }

    fun add(title: String, url: String) {
        val list = load()
        list.removeAll { it.url == url }
        list.add(0, Bookmark(title.ifBlank { url }, url))
        save(list)
    }

    fun remove(url: String) {
        val list = load()
        list.removeAll { it.url == url }
        save(list)
    }
}
