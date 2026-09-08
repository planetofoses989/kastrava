const { app, BrowserWindow, ipcMain, Menu, nativeTheme, nativeImage, clipboard, shell, dialog, protocol } = require('electron')
const path = require('path')
const fs = require('fs')
const { spawn, spawnSync } = require('child_process')
const backend = require('./backend')

// Serve the browser UI over kastrava:// instead of file:// so no
// filesystem paths leak (e.g. in DevTools titles) and the shell has a
// proper secure origin.
protocol.registerSchemesAsPrivileged([{
  scheme: 'kastrava',
  privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true }
}])

const preReadyPrefs = backend.initPreReady()

// Volatile RAM: never write GPU shader caches to disk either.
try { app.commandLine.appendSwitch('disable-gpu-shader-disk-cache'); } catch {}

let db
let settingsBackend
let radar
async function initDatabase() {
  try {
    const initSqlJs = require('sql.js')
    const SQL = await initSqlJs()
    const dbDir = path.join(app.getPath('userData'), 'data')
    fs.mkdirSync(dbDir, { recursive: true })
    const dbPath = path.join(dbDir, 'kastrava.db')
    let buffer
    try { buffer = fs.readFileSync(dbPath) } catch {}

    db = new SQL.Database(buffer)
    db.run(`CREATE TABLE IF NOT EXISTS bookmarks (
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, url TEXT NOT NULL,
      pos INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now'))
    )`)
    db.run(`CREATE TABLE IF NOT EXISTS history (
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, url TEXT NOT NULL,
      visited_at TEXT DEFAULT (datetime('now'))
    )`)
    db.run(`CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY, value TEXT
    )`)
    db.run(`CREATE TABLE IF NOT EXISTS top_sites (
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, url TEXT NOT NULL,
      icon TEXT, pos INTEGER DEFAULT 0
    )`)
  } catch (e) {
    console.error('DB init error:', e)
  }
}

function all(sql, params = []) {
  if (!db) return []
  try {
    const stmt = db.prepare(sql)
    if (params.length) stmt.bind(params)
    const cols = stmt.getColumnNames()
    const rows = []
    while (stmt.step()) {
      const vals = stmt.getAsObject()
      rows.push(vals)
    }
    stmt.free()
    return rows
  } catch { return [] }
}

function run(sql, params = []) {
  if (!db) return
  try { db.run(sql, params); saveDb() } catch {}
}

function saveDb() {
  try {
    const data = db.export()
    const buf = Buffer.from(data)
    fs.writeFileSync(path.join(app.getPath('userData'), 'data', 'kastrava.db'), buf)
  } catch (e) { console.error('[DB] save error:', e) }
}

function applyNativeTheme(theme) {
  try {
    if (typeof theme === 'string' && theme.indexOf('dark') === 0) nativeTheme.themeSource = 'dark'
    else if (typeof theme === 'string' && theme.indexOf('light') === 0) nativeTheme.themeSource = 'light'
    else nativeTheme.themeSource = 'system'
  } catch (e) {
    console.error('[Theme] applyNativeTheme error:', e)
  }
}

function initBackend() {
  settingsBackend = backend.createSettingsBackend({ all, run })
  settingsBackend.load()
  applyNativeTheme(settingsBackend.get('theme'))
  radar = backend.createRadarBackend({
    send: (wcId, ev) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('radar-update', wcId, ev)
      }
    }
  })
}

let mainWindow

function sendWinState() {
  mainWindow?.webContents.send('win-state', {
    maximized: mainWindow?.isMaximized() || false,
    minimized: mainWindow?.isMinimized() || false
  })
}

function handleKastravaProto(request, callback) {
  try {
    const u = new URL(request.url)
    let p = decodeURIComponent(u.pathname)
    if (p.startsWith('/')) p = p.slice(1)
    if (!p) p = 'browser.html'
    const file = path.normalize(path.join(__dirname, p))
    if (file !== __dirname && !file.startsWith(__dirname + path.sep)) return callback({ error: -6 })
    callback({ path: file })
  } catch { callback({ error: -6 }) }
}
function createWindow() {
  if (!globalThis.__kastravaProtoRegistered) {
    globalThis.__kastravaProtoRegistered = true;
    protocol.registerFileProtocol('kastrava', handleKastravaProto);
    try {
      // The shell window runs on its own memory session: register there too,
      // otherwise kastrava:// pages fail to load in it.
      const shSes = require('electron').session.fromPartition('kastrava-shell');
      shSes.protocol.registerFileProtocol('kastrava', handleKastravaProto);
    } catch (e) { console.error('shell protocol error:', e); }
  }
  const ses = require('electron').session.fromPartition('kastrava')

  ses.on('will-download', (event, item) => {
    const url = item.getURL()
    // Native fallback engine: a download started via Kastget when curl
    // is unavailable. Let it proceed into our tracked item.
    if (fallbackPending.has(url)) {
      const id = fallbackPending.get(url)
      fallbackPending.delete(url)
      attachNativeDownload(id, item)
      return
    }
    event.preventDefault()
    if (mainWindow) mainWindow.webContents.send('show-download-modal', {
      url,
      filename: item.getFilename()
    })
  })

  // Tracking Radar: live per-tab tracker monitoring
  ses.webRequest.onBeforeRequest((details, callback) => {
    // Context isolation: webpages must never touch local files
    try {
      if (new URL(details.url).protocol === 'file:') return callback({ cancel: true })
    } catch {}
    callback({})
    let host = ''
    try {
      const u = new URL(details.url)
      if (u.protocol === 'http:' || u.protocol === 'https:') host = u.hostname
    } catch {}
    if (!host || !details.webContentsId) return
    if (details.resourceType === 'mainFrame') {
      radar.setMain(details.webContentsId, host)
      return
    }
    radar.add(details.webContentsId, { kind: 'req', host, t: Date.now() })
  })
  ses.webRequest.onHeadersReceived((details, callback) => {
    const rh = details.responseHeaders
    const cookiesOff = settingsBackend && settingsBackend.get('cookies') === 'off'
    let hasSetCookie = false
    if (rh) {
      const filtered = {}
      for (const k in rh) {
        if (k.toLowerCase() === 'set-cookie') {
          hasSetCookie = true
          if (cookiesOff) continue
        }
        filtered[k] = rh[k]
      }
      if (cookiesOff && hasSetCookie) {
        callback({ responseHeaders: filtered })
        return
      }
    }
    callback({})
    if (!details.webContentsId || !rh || !hasSetCookie) return
    try {
      const u = new URL(details.url)
      radar.add(details.webContentsId, { kind: 'cookie', host: u.hostname, t: Date.now() })
    } catch {}
  })
  ses.webRequest.onBeforeSendHeaders((details, callback) => {
    const requestHeaders = details.requestHeaders || {}
    if (settingsBackend) {
      if (settingsBackend.get('dnt') === 'on') requestHeaders['DNT'] = '1'
      if (settingsBackend.get('cookies') === 'off') {
        delete requestHeaders['Cookie']
        delete requestHeaders['cookie']
      }
      if (settingsBackend.get('sendReferrer') === 'off') {
        delete requestHeaders['Referer']
        delete requestHeaders['Referrer']
      }
    }
    callback({ requestHeaders })
  })

  // Privacy by default: deny sensitive permissions, keep fullscreen
  ses.setPermissionRequestHandler((wc, permission, callback) => {
    if (permission === 'fullscreen') return callback(true)
    if (permission === 'geolocation') {
      return callback(settingsBackend ? settingsBackend.get('location') === 'allow' : false)
    }
    callback(false)
  })

  // Remove all stored cookies when private-cookies mode is active
  if (settingsBackend && settingsBackend.get('cookies') === 'off') {
    ses.clearStorageData({ storages: ['cookies'] }).catch(() => {})
  }

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 600,
    minHeight: 400,
    frame: false,
    backgroundColor: '#000000',
    icon: path.join(__dirname, '../static/logo.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true,
      partition: 'kastrava-shell'
    }
  })

  mainWindow.loadURL('kastrava://app/browser.html')

function sendShortcut(action) {
  try { if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('menu-shortcut', action) } catch {}
}

// OS-level keyboard accelerators. The renderer's keydown handler only fires
// when the browser UI has focus; when a webpage (webview) is focused the
// guest consumes all keys. Menu accelerators fire regardless of focus.
function buildMenu() {
  const tabItems = []
  for (let i = 1; i <= 9; i++) {
    tabItems.push({ label: 'Go to Tab ' + i, accelerator: 'CommandOrControl+' + i, click: () => sendShortcut('tab' + i) })
  }
  const template = [
    { label: 'File', submenu: [
      { label: 'New Tab', accelerator: 'CommandOrControl+T', click: () => sendShortcut('newTab') },
      { label: 'New Tab', accelerator: 'CommandOrControl+N', click: () => sendShortcut('newTab') },
      { type: 'separator' },
      { label: 'Close Tab', accelerator: 'CommandOrControl+W', click: () => sendShortcut('closeTab') },
      { label: 'Reopen Closed Tab', accelerator: 'CommandOrControl+Shift+T', click: () => sendShortcut('reopenTab') }
    ]},
    { label: 'Edit', submenu: [
      { role: 'undo' },
      { role: 'redo' },
      { type: 'separator' },
      { role: 'cut' },
      { role: 'copy' },
      { role: 'paste' },
      { role: 'selectAll' }
    ]},
    { label: 'View', submenu: [
      { label: 'Reload', accelerator: 'CommandOrControl+R', click: () => sendShortcut('reload') },
      { type: 'separator' },
      { label: 'Zoom In', accelerator: 'CommandOrControl+=', click: () => sendShortcut('zoomIn') },
      { label: 'Zoom Out', accelerator: 'CommandOrControl+-', click: () => sendShortcut('zoomOut') },
      { label: 'Reset Zoom', accelerator: 'CommandOrControl+0', click: () => sendShortcut('zoomReset') },
      { type: 'separator' },
      { label: 'Toggle Fullscreen', accelerator: 'F11', click: () => { try { if (mainWindow && !mainWindow.isDestroyed()) mainWindow.setFullScreen(!mainWindow.isFullScreen()) } catch {} } },
      { label: 'Focus Address Bar', accelerator: 'CommandOrControl+L', click: () => sendShortcut('focusOmnibox') },
      { label: 'Focus Address Bar', accelerator: 'Alt+D', click: () => sendShortcut('focusOmnibox') },
      { label: 'Find in Page', accelerator: 'CommandOrControl+F', click: () => sendShortcut('find') }
    ]},
    { label: 'Tabs', submenu: [
      { label: 'Next Tab', accelerator: 'CommandOrControl+Tab', click: () => sendShortcut('nextTab') },
      { label: 'Previous Tab', accelerator: 'CommandOrControl+Shift+Tab', click: () => sendShortcut('prevTab') },
      { type: 'separator' },
      ...tabItems,
      { type: 'separator' },
      { label: 'Back', accelerator: 'Alt+Left', click: () => sendShortcut('back') },
      { label: 'Forward', accelerator: 'Alt+Right', click: () => sendShortcut('forward') }
    ]},
    { label: 'Tools', submenu: [
      { label: 'Bookmark This Page', accelerator: 'CommandOrControl+D', click: () => sendShortcut('bookmark') },
      { label: 'History', accelerator: 'CommandOrControl+H', click: () => sendShortcut('history') },
      { label: 'Toggle Bookmark Bar', accelerator: 'CommandOrControl+Shift+B', click: () => sendShortcut('bookmarkBar') },
      { type: 'separator' },
      { label: 'Picture-in-Picture', accelerator: 'CommandOrControl+P', click: () => sendShortcut('pip') },
      { label: 'Reader Mode', accelerator: 'CommandOrControl+Shift+R', click: () => sendShortcut('reader') },
      { label: 'Split View', accelerator: 'CommandOrControl+Shift+E', click: () => sendShortcut('split') },
      { label: 'Tracking Radar', accelerator: 'CommandOrControl+Shift+K', click: () => sendShortcut('radar') },
      { label: 'Screenshot', accelerator: 'CommandOrControl+Shift+S', click: () => sendShortcut('screenshot') },
      { label: 'Mute Tab', accelerator: 'CommandOrControl+Shift+M', click: () => sendShortcut('mute') },
      { label: 'Open Kastget', accelerator: 'CommandOrControl+Shift+P', click: () => sendShortcut('kastget') },
      { label: 'Developer Tools', accelerator: 'F12', click: () => sendShortcut('devtools') },
      { label: 'Inspect', accelerator: 'CommandOrControl+Shift+I', click: () => sendShortcut('devtools') },
      { type: 'separator' },
      { label: 'Settings', accelerator: 'CommandOrControl+,', click: () => sendShortcut('settings') }
    ]}
  ]
  try { Menu.setApplicationMenu(Menu.buildFromTemplate(template)) } catch (e) { console.error('menu build error:', e) }
}
  if (settingsBackend && settingsBackend.get('launchMaximized') === 'on') {
    mainWindow.maximize()
  }

  mainWindow.on('maximize', sendWinState)
  mainWindow.on('unmaximize', sendWinState)
  mainWindow.on('minimize', sendWinState)
  mainWindow.on('restore', sendWinState)

  mainWindow.on('close', () => {
    if (mainWindow && db) {
      try {
        mainWindow.webContents.send('save-session-now')
      } catch {}
    }
  })

  buildMenu()

}

function saveSessionSync(tabs) {
  run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['session', JSON.stringify(tabs)])
}

let lastSessionData = null

// Volatile RAM: web storage lives in a memory-only session. Wipe any web
// data persisted on disk by older builds (cookies, cache, DOM storage).
function wipeLegacyWebData() {
  try {
    const base = path.join(app.getPath('userData'), 'Partitions')
    for (const name of ['kastrava', 'persist:kastrava', 'persist_kastrava']) {
      try { fs.rmSync(path.join(base, name), { recursive: true, force: true }) } catch {}
    }
  } catch {}
}

app.whenReady().then(async () => {
  await initDatabase()
  initBackend()
  wipeLegacyWebData()

  app.on('web-contents-created', (_, wc) => {
    wc.setWindowOpenHandler(({ url }) => {
      try {
        const proto = new URL(url).protocol
        if (proto === 'http:' || proto === 'https:') {
          if (mainWindow) mainWindow.webContents.send('open-new-tab', url)
          return { action: 'deny' }
        }
        // Never hand local files to outside apps; mailto is safe to delegate
        if (proto === 'mailto:') {
          shell.openExternal(url)
          return { action: 'deny' }
        }
      } catch {}
      return { action: 'deny' }
    })
  })

  createWindow()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})

let quitSaved = false
app.on('before-quit', () => {
  if (quitSaved) return
  quitSaved = true
  // Volatile RAM: drop all in-memory web storage (cookies, cache,
  // IndexedDB, DOM storage). The OS frees the rest on exit.
  try {
    const { session } = require('electron')
    for (const part of ['kastrava', 'kastrava-shell']) {
      try { session.fromPartition(part).clearStorageData().catch(() => {}) } catch {}
      try { session.fromPartition(part).clearCache().catch(() => {}) } catch {}
    }
    try { session.defaultSession.clearStorageData().catch(() => {}) } catch {}
    try { session.defaultSession.clearCache().catch(() => {}) } catch {}
  } catch {}
  if (lastSessionData) {
    try { saveSessionSync(lastSessionData) } catch {}
  } else if (db) {
    try {
      const r = all('SELECT value FROM settings WHERE key = ?', ['session'])
      if (r.length && r[0].value) {
        run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['session', r[0].value])
      }
    } catch {}
  }
})

ipcMain.on('save-session-sync', (_, tabs) => {
  lastSessionData = tabs
  saveSessionSync(tabs)
})

ipcMain.handle('win-minimize', () => mainWindow?.minimize())
ipcMain.handle('win-maximize', () => {
  if (mainWindow?.isMaximized()) mainWindow.unmaximize()
  else mainWindow?.maximize()
})
ipcMain.handle('win-close', () => mainWindow?.close())
ipcMain.handle('win-is-maximized', () => mainWindow?.isMaximized())
ipcMain.handle('get-settings', () => {
  return settingsBackend ? settingsBackend.getAll() : {}
})

ipcMain.handle('set-setting', (_, key, value) => {
  if (settingsBackend) settingsBackend.set(key, value)
  if (key === 'theme') applyNativeTheme(value)
  if (key === 'cookies' && value === 'off') {
    try {
      const ses = require('electron').session.fromPartition('kastrava')
      ses.cookies.remove(undefined, undefined).catch(() => {})
    } catch {}
  }
  return true
})

ipcMain.handle('set-referrer', (_, value) => {
  if (settingsBackend) settingsBackend.set('sendReferrer', value)
  return true
})

ipcMain.handle('get-bookmarks', () => {
  return all('SELECT * FROM bookmarks ORDER BY pos ASC, created_at DESC')
})

ipcMain.handle('add-bookmark', (_, { title, url }) => {
  run('INSERT INTO bookmarks (title, url) VALUES (?, ?)', [title, url])
})

ipcMain.handle('is-bookmarked', (_, url) => {
  const r = all('SELECT id FROM bookmarks WHERE url = ? LIMIT 1', [url])
  return r.length ? r[0] : null
})

ipcMain.handle('remove-bookmark', (_, id) => {
  if (typeof id === 'number') {
    run('DELETE FROM bookmarks WHERE id = ?', [id])
  } else {
    run('DELETE FROM bookmarks WHERE url = ?', [id])
  }
})

ipcMain.handle('get-history', () => {
  return all('SELECT * FROM history ORDER BY visited_at DESC LIMIT 200')
})

ipcMain.handle('add-history', (_, { title, url }) => {
  run('INSERT INTO history (title, url) VALUES (?, ?)', [title, url])
  run('DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY visited_at DESC LIMIT 200)')
})

ipcMain.handle('clear-history', () => {
  run('DELETE FROM history')
})

ipcMain.handle('get-top-sites', () => {
  return all('SELECT * FROM top_sites ORDER BY pos ASC')
})

ipcMain.handle('save-top-sites', (_, sites) => {
  run('DELETE FROM top_sites')
  for (const s of sites) run('INSERT INTO top_sites (title, url, icon, pos) VALUES (?, ?, ?, ?)', [s.title, s.url, s.icon || null, s.pos])
})

ipcMain.handle('save-page-icon', async (_, { url, dataUrl }) => {
  try {
    const img = nativeImage.createFromDataURL(dataUrl)
    const png = img.toPNG()
    const name = encodeURIComponent(url.replace(/[^a-z0-9]/gi, '_'))
    const dir = path.join(app.getPath('userData'), 'icons')
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(path.join(dir, `${name}.png`), png)
  } catch {}
})


ipcMain.handle('open-external', (_, url) => {
  try { shell.openExternal(String(url)) } catch {}
})

ipcMain.handle('open-path', (_, p) => {
  try { shell.openPath(String(p)) } catch {}
})

// Session restore
ipcMain.handle('save-session', (_, tabs) => {
  lastSessionData = tabs
  run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['session', JSON.stringify(tabs)])
})

ipcMain.handle('load-session', () => {
  const r = all('SELECT value FROM settings WHERE key = ?', ['session'])
  if (r.length && r[0].value) {
    try { return JSON.parse(r[0].value) } catch {}
  }
  return null
})

// Kastget download manager (curl-based)
const agDownloads = new Map()
let agIdCounter = 0

function agSend(id) {
  const d = agDownloads.get(id)
  if (!d || !mainWindow) return
  mainWindow.webContents.send('ag-update', {
    id: d.id, filename: d.filename, url: d.url,
    received: d.received, total: d.total,
    speed: d.speed, state: d.state, outputPath: d.outputPath
  })
}

function agPoll(id) {
  const d = agDownloads.get(id)
  if (!d || d.state !== 'downloading') return
  try {
    const st = fs.statSync(d.outputPath)
    d.received = st.size
    const now = Date.now()
    if (d._lastCheck) {
      const dt = (now - d._lastCheck) / 1000
      const db = d.received - d._lastBytes
      d.speed = dt > 0 ? db / dt : 0
    }
    d._lastCheck = now
    d._lastBytes = d.received
    agSend(id)
  } catch {}
  d._timer = setTimeout(() => agPoll(id), 500)
}

async function agGetTotalSize(url) {
  try {
    // Windows has no /dev/null and needs curl.exe explicitly
    const nullDev = process.platform === 'win32' ? 'NUL' : '/dev/null'
    const curlBin = process.platform === 'win32' ? 'curl.exe' : 'curl'
    const r = spawnSync(curlBin, ['-sIL', '-o', nullDev, '-w', '%{size_download}', url], {
      timeout: 10000, encoding: 'utf-8', env: { ...process.env, LC_ALL: 'C' }
    })
    return parseInt(r.stdout.trim(), 10) || 0
  } catch { return 0 }
}

const dlDir = () => app.getPath('downloads')
const CURL_BIN = process.platform === 'win32' ? 'curl.exe' : 'curl'
const killProc = (proc) => { if (proc) { try { proc.kill() } catch {} } }

// Native fallback engine (used when curl is missing). Chromium handles
// networking, so cookies/auth/redirects keep working.
const fallbackPending = new Map() // url -> dlId
let _curlOk = null
function curlOk() {
  if (process.env.KASTRAVA_NO_CURL) return false
  if (_curlOk !== null) return _curlOk
  try {
    const r = spawnSync(CURL_BIN, ['--version'], { timeout: 5000 })
    _curlOk = r.status === 0
  } catch { _curlOk = false }
  return _curlOk
}
function attachNativeDownload(id, item) {
  const d = agDownloads.get(id)
  if (!d) { try { item.cancel() } catch {} return }
  d.item = item
  try { item.setSavePath(d.outputPath) } catch {}
  item.on('updated', () => {
    if (!agDownloads.get(id)) return
    try { d.received = item.getReceivedBytes() } catch {}
    try { const t = item.getTotalBytes(); if (t > 0) d.total = t } catch {}
    agSend(id)
  })
  item.on('done', (_, state) => {
    if (!agDownloads.get(id)) return
    if (d.state === 'stopped' || d.state === 'paused') return
    if (state === 'completed') {
      d.received = d.total || d.received
      d.speed = 0
      d.state = 'done'
    } else {
      d.state = 'error'
    }
    agSend(id)
  })
}
function startNativeDownload(dl) {
  try {
    const ses = require('electron').session.fromPartition('kastrava')
    fallbackPending.set(dl.url, dl.id)
    ses.downloadURL(dl.url)
  } catch { dl.state = 'error'; agSend(dl.id); return }
  dl._timer = setTimeout(() => agPoll(dl.id), 500)
}

function agFinalPath(filename) {
  let p = path.join(dlDir(), filename)
  if (!fs.existsSync(p)) return p
  const ext = path.extname(filename)
  const base = path.basename(filename, ext)
  for (let i = 1; i < 999; i++) {
    p = path.join(dlDir(), `${base} (${i})${ext}`)
    if (!fs.existsSync(p)) return p
  }
  return path.join(dlDir(), `${base} (999)${ext}`)
}

ipcMain.handle('ag-start', async (_, url) => {
  const id = ++agIdCounter
  let filename = 'download'
  try { filename = decodeURIComponent(path.basename(new URL(url).pathname)) || 'download' } catch {}
  filename = filename.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_') || 'download'
  const fp = agFinalPath(filename)
  const dl = { id, url, filename: path.basename(fp), outputPath: fp, received: 0, total: 0, speed: 0, state: 'queued', proc: null, item: null, engine: curlOk() ? 'curl' : 'native', _timer: null, _lastCheck: null, _lastBytes: 0 }
  agDownloads.set(id, dl)

  dl.total = await agGetTotalSize(url)
  if (dl.engine === 'native') {
    dl.state = 'downloading'
    agSend(id)
    startNativeDownload(dl)
    return id
  }
  dl.state = 'downloading'
  agSend(id)

  dl.proc = spawn(CURL_BIN, ['-o', dl.outputPath, '-L', '-s', url])
  dl.proc.on('error', () => { dl.state = 'error'; agSend(id) })
  dl.proc.on('exit', (code) => {
    if (dl.state === 'stopped' || dl.state === 'paused') return
    if (code === 0) {
      dl.received = dl.total || 0
      dl.speed = 0
      dl.state = 'done'
      agSend(id)
    } else {
      dl.state = 'error'
      agSend(id)
    }
  })

  agPoll(id)
  return id
})

ipcMain.handle('ag-pause', (_, id) => {
  const d = agDownloads.get(id)
  if (!d || d.state !== 'downloading') return
  d.state = 'paused'
  if (d.engine === 'native' && d.item) { try { d.item.pause() } catch {} }
  else killProc(d.proc)
  if (d._timer) { clearTimeout(d._timer); d._timer = null }
  d.speed = 0
  agSend(id)
})

ipcMain.handle('ag-resume', async (_, id) => {
  const d = agDownloads.get(id)
  if (!d || d.state !== 'paused') return
  d.state = 'downloading'
  if (d.engine === 'native') {
    let resumed = false
    try { if (d.item) { d.item.resume(); resumed = true } } catch {}
    if (!resumed) {
      if (d.total === 0 && curlOk()) d.total = await agGetTotalSize(d.url)
      agSend(id)
      startNativeDownload(d)
      return
    }
    agSend(id)
    agPoll(id)
    return
  }
  if (d.total === 0) d.total = await agGetTotalSize(d.url)
  agSend(id)

  const args = ['-o', d.outputPath, '-L', '-s']
  if (d.received > 0) args.push('-C', '-')
  args.push(d.url)

  d.proc = spawn(CURL_BIN, args)
  d.proc.on('error', () => { d.state = 'error'; agSend(id) })
  d.proc.on('exit', (code) => {
    if (d.state === 'stopped' || d.state === 'paused') return
    if (code === 0) {
      d.received = d.total || 0
      d.speed = 0
      d.state = 'done'
      agSend(id)
    } else {
      d.state = 'error'
      agSend(id)
    }
  })

  agPoll(id)
})

ipcMain.handle('ag-stop', (_, id) => {
  const d = agDownloads.get(id)
  if (!d) return
  d.state = 'stopped'
  fallbackPending.delete(d.url)
  if (d.engine === 'native' && d.item) { try { d.item.cancel() } catch {} }
  else killProc(d.proc)
  if (d._timer) { clearTimeout(d._timer); d._timer = null }
  d.speed = 0
  try { if (fs.existsSync(d.outputPath)) fs.unlinkSync(d.outputPath) } catch {}
  agSend(id)
})

ipcMain.handle('ag-clear', (_, id) => {
  const d = agDownloads.get(id)
  if (!d) return
  if (d._timer) clearTimeout(d._timer)
  fallbackPending.delete(d.url)
  if (d.engine === 'native' && d.item) { try { d.item.cancel() } catch {} }
  try { if (fs.existsSync(d.outputPath)) fs.unlinkSync(d.outputPath) } catch {}
  agDownloads.delete(id)
  mainWindow?.webContents.send('ag-cleared', id)
})

ipcMain.handle('ag-list', () => {
  return Array.from(agDownloads.values()).map(d => ({
    id: d.id, filename: d.filename, url: d.url,
    received: d.received, total: d.total, speed: d.speed, state: d.state, engine: d.engine || 'curl',
    outputPath: d.state === 'done' ? d.outputPath : null
  }))
})

ipcMain.handle('web-inspect', async (_, { tabId, x, y }) => {
  try {
    if (!mainWindow) return
    const { webContents } = require('electron')
    let wc = null
    try { wc = webContents.fromId(tabId) } catch {}
    if (wc && !wc.isDestroyed()) { try { wc.inspectElement(x||0, y||0); if(!wc.isDevToolsOpened()) wc.openDevTools({mode:'detach'}); } catch {} return }
    const ses = require('electron').session.fromPartition('kastrava')
    const wcs = ses.getAllRunningWebContents()
    for (const c of wcs) { if (c.id === tabId) { try { c.inspectElement(x||0, y||0); if(!c.isDevToolsOpened()) c.openDevTools({mode:'detach'}); } catch {} break } }
  } catch {}
})
ipcMain.handle('devtools-toggle', async (_, tabId) => {
  try {
    const { webContents } = require('electron')
    let wc = null
    try { wc = webContents.fromId(tabId) } catch {}
    if (!wc || wc.isDestroyed()) {
      const ses = require('electron').session.fromPartition('kastrava')
      const wcs = ses.getAllRunningWebContents()
      for (const c of wcs) if (c.id === tabId) { wc = c; break }
    }
    if (!wc || wc.isDestroyed()) return false
    if (wc.isDevToolsOpened()) wc.closeDevTools()
    else wc.openDevTools({mode:'detach'})
    return wc.isDevToolsOpened()
  } catch { return false }
})
ipcMain.handle('devtools-open', async (_, tabId) => {
  try {
    const { webContents } = require('electron')
    let wc = webContents.fromId(tabId)
    if (!wc || wc.isDestroyed()) return false
    if (!wc.isDevToolsOpened()) wc.openDevTools({mode:'detach'})
    return true
  } catch { return false }
})
ipcMain.handle('devtools-close', async (_, tabId) => {
  try {
    const { webContents } = require('electron')
    let wc = webContents.fromId(tabId)
    if (wc && !wc.isDestroyed() && wc.isDevToolsOpened()) wc.closeDevTools()
    return true
  } catch { return false }
})
// Fallback: toggle DevTools for the browser UI itself (used when the
// active tab has no inspectable guest, e.g. a blank new tab)
ipcMain.handle('devtools-self', async () => {
  try {
    if (!mainWindow || mainWindow.isDestroyed()) return false
    const wc = mainWindow.webContents
    if (wc.isDevToolsOpened()) wc.closeDevTools()
    else wc.openDevTools({ mode: 'detach' })
    return wc.isDevToolsOpened()
  } catch { return false }
})

// Tracking Radar data
ipcMain.handle('radar-get', (_, wcId) => radar ? radar.get(wcId) : [])
ipcMain.handle('radar-clear', (_, wcId) => { if (radar) radar.clear(wcId); return true })
ipcMain.handle('radar-stats', (_, wcId) => radar ? radar.stats(wcId) : { reqs: 0, cookies: 0, third: 0, doms: {}, score: 100 })

// Screenshots
ipcMain.handle('save-screenshot', async (_, { pngDataUrl }) => {
  try {
    const img = nativeImage.createFromDataURL(pngDataUrl)
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
    const p = path.join(app.getPath('downloads'), `Kastrava-${ts}.png`)
    fs.writeFileSync(p, img.toPNG())
    return p
  } catch { return null }
})

// Bookmark export (Netscape HTML)
ipcMain.handle('export-bookmarks', async (_, html) => {
  try {
    const r = await dialog.showSaveDialog(mainWindow, {
      defaultPath: 'kastrava-bookmarks.html',
      filters: [{ name: 'HTML', extensions: ['html'] }]
    })
    if (r.canceled || !r.filePath) return null
    fs.writeFileSync(r.filePath, html)
    return r.filePath
  } catch { return null }
})

// Bookmark import (Netscape HTML)
ipcMain.handle('import-bookmarks', async () => {
  try {
    const r = await dialog.showOpenDialog(mainWindow, {
      filters: [{ name: 'HTML', extensions: ['html', 'htm'] }],
      properties: ['openFile']
    })
    if (r.canceled || !r.filePaths.length) return 0
    const txt = fs.readFileSync(r.filePaths[0], 'utf-8')
    const re = /<a\s[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/gi
    let m, count = 0
    while ((m = re.exec(txt))) {
      const url = m[1].trim()
      const title = (m[2] || '').replace(/<[^>]+>/g, '').trim() || url
      if (/^https?:\/\//i.test(url)) {
        const exists = all('SELECT id FROM bookmarks WHERE url = ? LIMIT 1', [url])
        if (!exists.length) {
          run('INSERT INTO bookmarks (title, url) VALUES (?, ?)', [title, url])
          count++
        }
      }
    }
    return count
  } catch { return 0 }
})
