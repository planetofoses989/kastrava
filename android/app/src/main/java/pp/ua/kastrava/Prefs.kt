package pp.ua.kastrava

import android.content.Context
import androidx.preference.PreferenceManager

/**
 * User settings. Free ships KastravaSearch + DuckDuckGo and one light/dark
 * theme pair; Premium unlocks Brave/Google/Ecosia and accent themes —
 * same split as the desktop free/Premium FAQ.
 */
class Prefs(context: Context) {
    private val p = PreferenceManager.getDefaultSharedPreferences(context)

    var engine: String
        get() = p.getString("engine", "kastrava") ?: "kastrava"
        set(v) { p.edit().putString("engine", v).apply() }

    var theme: String
        get() = p.getString("theme", "system") ?: "system"
        set(v) { p.edit().putString("theme", v).apply() }

    var blockers: Boolean
        get() = p.getBoolean("blockers", true)
        set(v) { p.edit().putBoolean("blockers", v).apply() }

    var javaScript: Boolean
        get() = p.getBoolean("javascript", true)
        set(v) { p.edit().putBoolean("javascript", v).apply() }

    companion object {
        const val KASTRA_SEARCH = "https://kastravasearch.pp.ua/search?q="
        val ENGINES = mapOf(
            "kastrava" to ("KastravaSearch" to KASTRA_SEARCH),
            "duckduckgo" to ("DuckDuckGo" to "https://duckduckgo.com/?q="),
            "brave" to ("Brave" to "https://search.brave.com/search?q="),
            "google" to ("Google" to "https://www.google.com/search?q="),
            "ecosia" to ("Ecosia" to "https://www.ecosia.org/search?q="),
        )
        val FREE_ENGINES = setOf("kastrava", "duckduckgo")

        fun searchUrl(engine: String, premium: Boolean, query: String): String {
            val key = if (!premium && engine !in FREE_ENGINES) "kastrava" else engine
            return (ENGINES[key]?.second ?: KASTRA_SEARCH) + query
        }
    }
}
