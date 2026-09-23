package pp.ua.kastrava

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

/**
 * Kastrava for Android: tabbed WebView browser.
 * - Omnibox (URL or search via the configured engine)
 * - Tracker/ad blocking at the network layer (FilterLists)
 * - Session downloads (volatile area + explicit Save)
 * - Website data wiped on exit (cookies, DOM storage, cache)
 */
class MainActivity : AppCompatActivity() {

    private lateinit var app: KastravaApp
    private lateinit var container: FrameLayout
    private lateinit var homeView: ScrollView
    private lateinit var omnibox: EditText
    private lateinit var homeSearch: EditText
    private lateinit var homePremium: TextView
    private lateinit var progress: ProgressBar
    private lateinit var btnTabs: ImageButton

    private val tabs = mutableListOf<WebView>()
    private var current = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app = application as KastravaApp
        setContentView(R.layout.activity_main)

        container = findViewById(R.id.webContainer)
        homeView = findViewById(R.id.homeView)
        omnibox = findViewById(R.id.omnibox)
        homeSearch = findViewById(R.id.homeSearch)
        homePremium = findViewById(R.id.homePremium)
        progress = findViewById(R.id.progress)
        btnTabs = findViewById(R.id.btnTabs)

        CookieManager.getInstance().setAcceptCookie(true)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { currentTab()?.goBack() }
        findViewById<ImageButton>(R.id.btnForward).setOnClickListener { currentTab()?.goForward() }
        findViewById<ImageButton>(R.id.btnReload).setOnClickListener { currentTab()?.reload() }
        btnTabs.setOnClickListener { showTabs() }
        findViewById<ImageButton>(R.id.btnMenu).setOnClickListener { showMenu(it) }

        val go = { query: String -> openQuery(query); true }
        omnibox.setOnEditorActionListener { v, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_GO) {
                hideKeyboard(v)
                go((v as EditText).text.toString())
            } else false
        }
        homeSearch.setOnEditorActionListener { v, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                hideKeyboard(v)
                go((v as EditText).text.toString())
            } else false
        }

        handleIntent(intent)
        if (current < 0) showHome()
        refreshPremiumLine()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val url = when (intent.action) {
            Intent.ACTION_VIEW -> intent.dataString
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)?.let {
                Regex("https?://\\S+").find(it)?.value
            }
            else -> null
        }
        if (!url.isNullOrBlank()) newTab(url)
    }

    override fun onResume() {
        super.onResume()
        refreshPremiumLine()
        // Settings (engine, JS) may have changed: apply JS flag live.
        tabs.forEach { it.settings.javaScriptEnabled = app.prefs.javaScript }
    }

    // ----- tabs -----

    private fun currentTab(): WebView? = tabs.getOrNull(current)

    private fun newTab(url: String? = null) {
        val wv = buildWebView(this, app.prefs.javaScript)
        wv.webViewClient = KastraWebClient(app.filters, { app.prefs.blockers })
        wv.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, p: Int) {
                if (view == currentTab()) {
                    progress.visibility =
                        if (p in 1..99) ProgressBar.VISIBLE else ProgressBar.GONE
                    progress.progress = p
                }
                if (view == currentTab() && p == 100) syncOmnibox()
            }

            override fun onReceivedTitle(view: WebView, title: String?) {
                if (view == currentTab()) syncOmnibox()
            }
        }
        wv.setDownloadListener { dlUrl, _, contentDisposition, _, _ ->
            startSessionDownload(dlUrl, contentDisposition)
        }
        tabs.add(wv)
        container.addView(
            wv,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        switchTo(tabs.size - 1)
        if (url != null) wv.loadUrl(url) else showHome()
    }

    private fun switchTo(i: Int) {
        if (i !in tabs.indices) return
        currentTab()?.visibility = WebView.GONE
        current = i
        val wv = tabs[i]
        wv.visibility = WebView.VISIBLE
        homeView.visibility = ScrollView.GONE
        syncOmnibox()
    }

    private fun closeTab(i: Int) {
        if (i !in tabs.indices) return
        val wv = tabs.removeAt(i)
        container.removeView(wv)
        wv.destroy()
        if (tabs.isEmpty()) {
            current = -1
            showHome()
        } else {
            current = -1
            switchTo(i.coerceAtMost(tabs.size - 1))
        }
    }

    private fun showHome() {
        currentTab()?.visibility = WebView.GONE
        current = -1
        homeView.visibility = ScrollView.VISIBLE
        omnibox.setText("")
        progress.visibility = ProgressBar.GONE
    }

    private fun showTabs() {
        val names = tabs.mapIndexed { i, wv ->
            val t = wv.title?.takeIf { it.isNotBlank() } ?: wv.url ?: "New tab"
            "${if (i == current) "● " else "○ "}$t"
        }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Tabs (${tabs.size})")
            .setItems(names) { _, which -> switchTo(which) }
            .setPositiveButton("New tab") { _, _ -> newTab() }
            .setNeutralButton("Close current") { _, _ -> if (current >= 0) closeTab(current) }
            .show()
    }

    // ----- navigation -----

    private fun engineUrl(): (String) -> String {
        val premium = app.license.status().activated
        val engine = app.prefs.engine
        return { q -> Prefs.searchUrl(engine, premium, q.ifBlank { "kastrava browser" }) }
    }

    private fun openQuery(input: String) {
        if (input.isBlank()) return
        val url = resolveInput(input, engineUrl())
        if (current < 0) newTab(url) else currentTab()?.loadUrl(url)
    }

    private fun syncOmnibox() {
        val wv = currentTab()
        omnibox.setText(wv?.url ?: "")
    }

    private fun showMenu(anchor: android.view.View) {
        PopupMenu(this, anchor).apply {
            menu.add("New tab")
            menu.add("Downloads")
            menu.add("Premium")
            menu.add("Settings")
            menu.add("About")
            setOnMenuItemClickListener { item ->
                when (item.title.toString()) {
                    "New tab" -> newTab()
                    "Downloads" -> startActivity(Intent(this@MainActivity, DownloadsActivity::class.java))
                    "Premium" -> startActivity(Intent(this@MainActivity, PremiumActivity::class.java))
                    "Settings" -> startActivity(Intent(this@MainActivity, SettingsActivity::class.java))
                    "About" -> AlertDialog.Builder(this@MainActivity)
                        .setTitle("Kastrava 101.0.0")
                        .setMessage(
                            "Private browser · zero telemetry.\n" +
                                "Website data lives in memory and is wiped on exit.\n" +
                                "GPLv3 · kastrava.pp.ua",
                        )
                        .setPositiveButton("OK", null)
                        .show()
                }
                true
            }
            show()
        }
    }

    private fun refreshPremiumLine() {
        val st = app.license.status()
        homePremium.text = if (st.activated) {
            val exp = st.expiresAtMs?.let { java.text.DateFormat.getDateInstance().format(java.util.Date(it)) }
            if (st.grace) "Premium active — renewal due (grace until $exp)"
            else "Premium active" + (if (exp != null) " · until $exp" else "")
        } else {
            "Free core · Premium ₹248/34d in the menu"
        }
    }

    // ----- downloads -----

    private fun startSessionDownload(url: String, contentDisposition: String?) {
        val name = URLUtil.guessFileName(url, contentDisposition, null)
        val item = app.downloads.add(url, name)
        // WebViews must only be touched on the UI thread — snapshot the UA now.
        val ua = currentTab()?.settings?.userAgentString ?: System.getProperty("http.agent")
        Toast.makeText(this, "Downloading: $name", Toast.LENGTH_SHORT).show()
        Thread {
            try {
                val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                if (ua != null) conn.setRequestProperty("User-Agent", ua)
                conn.connect()
                item.total = conn.contentLengthLong
                conn.inputStream.use { input ->
                    item.file.outputStream().use { output ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            output.write(buf, 0, n)
                            item.received += n
                        }
                    }
                }
                item.state = "done"
            } catch (e: Exception) {
                item.state = "failed"
                try { item.file.delete() } catch (ignored: Exception) { }
            }
            runOnUiThread {
                Toast.makeText(
                    this,
                    if (item.state == "done") "Saved to session: $name" else "Download failed: $name",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }.start()
        // Offer the Downloads screen right away; explicit Save copies it out.
        startActivity(Intent(this, DownloadsActivity::class.java))
    }

    private fun hideKeyboard(v: android.view.View) {
        (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(v.windowToken, 0)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            val wv = currentTab()
            if (wv != null && wv.canGoBack()) {
                wv.goBack()
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        // Tear down WebViews first so their renderers release, then wipe.
        tabs.toList().forEach { wv ->
            try {
                container.removeView(wv)
                wv.clearCache(true)
                wv.destroy()
            } catch (e: Exception) { }
        }
        tabs.clear()
        try {
            app.wipeSession()
        } catch (e: Exception) { }
        super.onDestroy()
    }
}
