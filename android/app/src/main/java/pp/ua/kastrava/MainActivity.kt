package pp.ua.kastrava

import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
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
import android.graphics.Bitmap
import android.util.TypedValue
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
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
    private lateinit var tabCount: TextView
    private lateinit var findBar: LinearLayout
    private lateinit var etFind: EditText

    private data class WebTab(
        val view: WebView,
        var favicon: Bitmap? = null,
        var desktopMode: Boolean = false,
        var defaultUa: String? = null,
    )

    private val tabs = mutableListOf<WebTab>()
    private var current = -1

    companion object {
        private const val DESKTOP_UA =
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    }

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
        tabCount = findViewById(R.id.tabCount)
        findBar = findViewById(R.id.findBar)
        etFind = findViewById(R.id.etFind)
        findViewById<ImageButton>(R.id.btnFindClose).setOnClickListener { closeFindBar() }
        findViewById<ImageButton>(R.id.btnFindNext).setOnClickListener { currentTab()?.findNext(true) }
        findViewById<ImageButton>(R.id.btnFindPrev).setOnClickListener { currentTab()?.findNext(false) }
        etFind.setOnEditorActionListener { v, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                hideKeyboard(v)
                currentTab()?.findAllAsync((v as EditText).text.toString())
                true
            } else false
        }
        findViewById<LinearLayout>(R.id.tileNewTab).setOnClickListener { newTab() }
        findViewById<LinearLayout>(R.id.tileDownloads).setOnClickListener { openDownloads() }
        findViewById<LinearLayout>(R.id.tilePremium).setOnClickListener { openPremium() }
        findViewById<LinearLayout>(R.id.tileSettings).setOnClickListener { openSettings() }
        updateTabCount()

        CookieManager.getInstance().setAcceptCookie(true)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { currentTab()?.goBack() }
        findViewById<ImageButton>(R.id.btnForward).setOnClickListener { currentTab()?.goForward() }
        findViewById<ImageButton>(R.id.btnReload).setOnClickListener { currentTab()?.reload() }
        btnTabs.setOnClickListener { showTabs() }
        findViewById<ImageButton>(R.id.btnMenu).setOnClickListener { showMenu(it) }

        val go = { query: String -> openQuery(query); true }
        omnibox.setOnFocusChangeListener { v, focused ->
            val wv = currentTab()
            if (focused) {
                (v as EditText).setText(wv?.url ?: "")
                (v as EditText).selectAll()
            } else {
                syncOmnibox()
            }
        }
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
        tabs.forEach { it.view.settings.javaScriptEnabled = app.prefs.javaScript }
    }

    // ----- tabs -----

    private fun currentTab(): WebView? = tabs.getOrNull(current)?.view
    private fun currentWebTab(): WebTab? = tabs.getOrNull(current)

    private fun newTab(url: String? = null, desktopMode: Boolean = false) {
        val wv = buildWebView(this, app.prefs.javaScript)
        val tab = WebTab(wv)
        tab.defaultUa = wv.settings.userAgentString
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

            override fun onReceivedIcon(view: WebView, icon: Bitmap?) {
                tabs.find { it.view == view }?.favicon = icon
            }
        }
        wv.setOnLongClickListener {
            val result = wv.hitTestResult
            when (result?.type) {
                WebView.HitTestResult.SRC_ANCHOR_TYPE -> {
                    showLinkMenu(result.extra, isImage = false)
                    true
                }
                WebView.HitTestResult.IMAGE_TYPE,
                WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE -> {
                    showLinkMenu(result.extra, isImage = true)
                    true
                }
                else -> false
            }
        }
        wv.setDownloadListener { dlUrl, _, contentDisposition, _, _ ->
            startSessionDownload(dlUrl, contentDisposition)
        }
        if (desktopMode) applyDesktopMode(tab, true)
        tabs.add(tab)
        container.addView(
            wv,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        updateTabCount()
        switchTo(tabs.size - 1)
        if (url != null) wv.loadUrl(url) else showHome()
    }

    private fun updateTabCount() {
        tabCount.text = tabs.size.toString()
    }

    private fun switchTo(i: Int) {
        if (i !in tabs.indices) return
        currentTab()?.visibility = WebView.GONE
        current = i
        val wv = tabs[i].view
        wv.visibility = WebView.VISIBLE
        homeView.visibility = ScrollView.GONE
        syncOmnibox()
    }

    private fun closeTab(i: Int) {
        if (i !in tabs.indices) return
        val wv = tabs.removeAt(i).view
        container.removeView(wv)
        wv.destroy()
        if (tabs.isEmpty()) {
            current = -1
            updateTabCount()
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
        updateTabCount()
        omnibox.setText("")
        progress.visibility = ProgressBar.GONE
    }

    private fun showTabs() {
        val sheet = BottomSheetDialog(this)
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (16 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad / 2, pad, pad)
        }
        val density = resources.displayMetrics.density
        tabs.forEachIndexed { i, tab ->
            val wv = tab.view
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = android.view.Gravity.CENTER_VERTICAL
                isClickable = true
                isFocusable = true
                setBackgroundResource(selectableBackground())
                setPadding(0, (8 * density).toInt(), 0, (8 * density).toInt())
                setOnClickListener { sheet.dismiss(); switchTo(i) }
            }
            val icon = android.widget.ImageView(this).apply {
                layoutParams = LinearLayout.LayoutParams((40 * density).toInt(), (40 * density).toInt())
                val fav = tab.favicon
                if (fav != null) setImageBitmap(fav)
                else setImageResource(R.drawable.ic_globe)
            }
            row.addView(icon)
            val texts = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = (12 * density).toInt()
                    marginEnd = (8 * density).toInt()
                }
            }
            val title = wv.title?.takeIf { it.isNotBlank() } ?: wv.url ?: "New tab"
            texts.addView(TextView(this).apply {
                text = title
                textSize = 15f
                maxLines = 1
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            texts.addView(TextView(this).apply {
                text = wv.url ?: ""
                textSize = 12f
                maxLines = 1
            })
            row.addView(texts)
            val close = ImageButton(this).apply {
                setImageResource(R.drawable.ic_close)
                background = null
                contentDescription = "Close tab"
                setOnClickListener { closeTab(i); sheet.dismiss(); if (tabs.isNotEmpty()) showTabs() }
            }
            row.addView(close)
            if (i == current) row.setBackgroundColor(0x140288D1)
            list.addView(row)
        }
        val newTabRow = TextView(this).apply {
            text = "+ New tab"
            textSize = 16f
            val vpad = (14 * density).toInt()
            setPadding(0, vpad, 0, vpad)
            setTextColor(0xFF0288D1.toInt())
            setOnClickListener { sheet.dismiss(); newTab() }
        }
        list.addView(newTabRow)
        sheet.setContentView(ScrollView(this).apply { addView(list) })
        sheet.show()
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
        val url = wv?.url ?: ""
        omnibox.setText(if (omnibox.hasFocus()) url else displayHost(url))
    }

    private fun displayHost(url: String): String {
        if (url.isBlank()) return ""
        return try {
            val uri = android.net.Uri.parse(url)
            val host = uri.host ?: return url
            if (uri.scheme == "https" || uri.scheme == "http") host else url
        } catch (e: Exception) {
            url
        }
    }

    private fun openDownloads() {
        startActivity(Intent(this, DownloadsActivity::class.java))
    }

    private fun openPremium() {
        startActivity(Intent(this, PremiumActivity::class.java))
    }

    private fun openSettings() {
        startActivity(Intent(this, SettingsActivity::class.java))
    }

    private fun showMenu(anchor: android.view.View) {
        val sheet = BottomSheetDialog(this)
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (20 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad / 2, pad, pad)
        }
        val desktopLabel = if (currentWebTab()?.desktopMode == true) "Desktop site ✓" else "Desktop site"
        val entries = listOf("New tab", "Share page", "Find in page", desktopLabel, "Downloads", "Premium", "Settings", "About")
        entries.forEach { title ->
            val row = TextView(this).apply {
                text = title
                isClickable = true
                isFocusable = true
                setBackgroundResource(selectableBackground())
                textSize = 16f
                val vpad = (14 * resources.displayMetrics.density).toInt()
                setPadding(0, vpad, 0, vpad)
                setOnClickListener {
                    sheet.dismiss()
                    when {
                        title == "New tab" -> newTab()
                        title == "Share page" -> sharePage()
                        title == "Find in page" -> openFindBar()
                        title.startsWith("Desktop site") -> toggleDesktopMode()
                        title == "Downloads" -> openDownloads()
                        title == "Premium" -> openPremium()
                        title == "Settings" -> openSettings()
                        title == "About" -> showAbout()
                    }
                }
            }
            list.addView(row)
        }
        sheet.setContentView(list)
        sheet.show()
    }

    private fun showAbout() {
        MaterialAlertDialogBuilder(this)
            .setTitle("Kastrava 101.0.0")
            .setMessage(
                "Private browser · zero telemetry.\n" +
                    "Website data lives in memory and is wiped on exit.\n" +
                    "GPLv3 · kastrava.pp.ua",
            )
            .setPositiveButton("OK", null)
            .show()
    }

    private fun sharePage() {
        val url = currentTab()?.url ?: return
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
        }
        startActivity(Intent.createChooser(send, "Share page"))
    }

    private fun openFindBar() {
        if (currentTab() == null) return
        findBar.visibility = LinearLayout.VISIBLE
        etFind.requestFocus()
        etFind.setText("")
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showSoftInput(etFind, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun closeFindBar() {
        currentTab()?.clearMatches()
        findBar.visibility = LinearLayout.GONE
        hideKeyboard(etFind)
    }

    private fun toggleDesktopMode() {
        val tab = currentWebTab() ?: return
        applyDesktopMode(tab, !tab.desktopMode)
        tab.view.reload()
    }

    private fun applyDesktopMode(tab: WebTab, on: Boolean) {
        tab.desktopMode = on
        tab.view.settings.userAgentString = if (on) DESKTOP_UA else tab.defaultUa
        tab.view.settings.useWideViewPort = true
        tab.view.settings.loadWithOverviewMode = true
    }

    private fun copyLink(url: String, label: String = "Link copied") {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("link", url))
        Toast.makeText(this, label, Toast.LENGTH_SHORT).show()
    }

    private fun showLinkMenu(url: String?, isImage: Boolean) {
        if (url.isNullOrBlank()) return
        val items = if (isImage) {
            arrayOf("Open image in new tab", "Download image", "Share link", "Copy link")
        } else {
            arrayOf("Open in new tab", "Share link", "Copy link")
        }
        MaterialAlertDialogBuilder(this)
            .setItems(items) { _, which ->
                val action = items[which]
                when {
                    action.startsWith("Open") -> newTab(url)
                    action.startsWith("Download") -> startSessionDownload(url, null)
                    action.startsWith("Share") -> {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, url)
                        }
                        startActivity(Intent.createChooser(send, "Share link"))
                    }
                    else -> copyLink(url)
                }
            }
            .show()
    }

    private fun refreshPremiumLine() {
        val st = app.license.status()
        homePremium.text = if (st.activated) {
            val exp = st.expiresAtMs?.let { java.text.DateFormat.getDateInstance().format(java.util.Date(it)) }
            if (st.grace) "Premium active — renewal due (grace until $exp)"
            else "Premium active" + (if (exp != null) " · until $exp" else "")
        } else {
            "Free core · Premium $2.59/34D in the menu"
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

    private fun selectableBackground(): Int {
        val tv = TypedValue()
        theme.resolveAttribute(android.R.attr.selectableItemBackground, tv, true)
        return tv.resourceId
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
        tabs.toList().forEach { tab ->
            try {
                container.removeView(tab.view)
                tab.view.clearCache(true)
                tab.view.destroy()
            } catch (e: Exception) { }
        }
        tabs.clear()
        try {
            app.wipeSession()
        } catch (e: Exception) { }
        super.onDestroy()
    }
}
