const { app, BrowserWindow, ipcMain, Menu, nativeImage, clipboard, shell } = require('electron')
const path = require('path')
const fs = require('fs')
const { spawn, spawnSync } = require('child_process')


let db
async function initDatabase() {
  try {
    const initSqlJs = require('sql.js')
    const SQL = await initSqlJs()
    const dbDir = path.join(app.getPath('userData'), 'data')
    fs.mkdirSync(dbDir, { recursive: true })
    const dbPath = path.join(dbDir, 'antersurf.db')
    let buffer
    try { buffer = fs.readFileSync(dbPath) } catch {}
    console.log('[DB] path:', dbPath, 'size:', buffer ? buffer.length : 'new')
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
    fs.writeFileSync(path.join(app.getPath('userData'), 'data', 'antersurf.db'), buf)
  } catch (e) { console.error('[DB] save error:', e) }
}

let mainWindow

function sendWinState() {
  mainWindow?.webContents.send('win-state', {
    maximized: mainWindow?.isMaximized() || false,
    minimized: mainWindow?.isMinimized() || false
  })
}

function createWindow() {
  const ses = require('electron').session.fromPartition('persist:antersurf')

  ses.on('will-download', (event, item) => {
    event.preventDefault()
    if (mainWindow) mainWindow.webContents.send('show-download-modal', {
      url: item.getURL(),
      filename: item.getFilename()
    })
  })

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 600,
    minHeight: 400,
    frame: false,
    backgroundColor: '#0e0e1a',
    icon: path.join(__dirname, '../static/logo.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true
    }
  })

  mainWindow.loadFile(path.join(__dirname, 'browser.html'))

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

}

function saveSessionSync(tabs) {
  run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['session', JSON.stringify(tabs)])
}

let lastSessionData = null

app.whenReady().then(async () => {
  await initDatabase()

  app.on('web-contents-created', (_, wc) => {
    wc.setWindowOpenHandler(({ url }) => {
      if (mainWindow) mainWindow.webContents.send('open-new-tab', url)
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
  const rows = all('SELECT key, value FROM settings')
  const out = {}
  for (const r of rows) {
    try { out[r.key] = JSON.parse(r.value) } catch { out[r.key] = r.value }
  }
  return out
})

ipcMain.handle('set-setting', (_, key, value) => {
  run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, JSON.stringify(value)])
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

ipcMain.handle('log', (_, msg) => console.log('Renderer:', msg))

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

// AnterGet download manager (curl-based)
const agDownloads = new Map()
let agIdCounter = 0

function agSend(id) {
  const d = agDownloads.get(id)
  if (!d || !mainWindow) return
  mainWindow.webContents.send('ag-update', {
    id: d.id, filename: d.filename, url: d.url,
    received: d.received, total: d.total,
    speed: d.speed, state: d.state
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
    const r = spawnSync('curl', ['-sIL', '-o', '/dev/null', '-w', '%{size_download}', url], {
      timeout: 10000, encoding: 'utf-8', env: { ...process.env, LC_ALL: 'C' }
    })
    return parseInt(r.stdout.trim(), 10) || 0
  } catch { return 0 }
}

const dlDir = () => app.getPath('downloads')

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
  const fp = agFinalPath(filename)
  const dl = { id, url, filename: path.basename(fp), outputPath: fp, received: 0, total: 0, speed: 0, state: 'queued', proc: null, _timer: null, _lastCheck: null, _lastBytes: 0 }
  agDownloads.set(id, dl)

  dl.total = await agGetTotalSize(url)
  dl.state = 'downloading'
  agSend(id)

  dl.proc = spawn('curl', ['-o', dl.outputPath, '-L', '-s', url])
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
  if (d.proc) { try { d.proc.kill('SIGTERM') } catch {} }
  if (d._timer) { clearTimeout(d._timer); d._timer = null }
  d.speed = 0
  agSend(id)
})

ipcMain.handle('ag-resume', async (_, id) => {
  const d = agDownloads.get(id)
  if (!d || d.state !== 'paused') return
  d.state = 'downloading'
  if (d.total === 0) d.total = await agGetTotalSize(d.url)
  agSend(id)

  const args = ['-o', d.outputPath, '-L', '-s']
  if (d.received > 0) args.push('-C', '-')
  args.push(d.url)

  d.proc = spawn('curl', args)
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
  if (d.proc) { try { d.proc.kill('SIGTERM') } catch {} }
  if (d._timer) { clearTimeout(d._timer); d._timer = null }
  d.speed = 0
  try { if (fs.existsSync(d.outputPath)) fs.unlinkSync(d.outputPath) } catch {}
  agSend(id)
})

ipcMain.handle('ag-clear', (_, id) => {
  const d = agDownloads.get(id)
  if (!d) return
  if (d._timer) clearTimeout(d._timer)
  try { if (fs.existsSync(d.outputPath)) fs.unlinkSync(d.outputPath) } catch {}
  agDownloads.delete(id)
  mainWindow?.webContents.send('ag-cleared', id)
})

ipcMain.handle('ag-list', () => {
  return Array.from(agDownloads.values()).map(d => ({
    id: d.id, filename: d.filename, url: d.url,
    received: d.received, total: d.total, speed: d.speed, state: d.state,
    outputPath: d.state === 'done' ? d.outputPath : null
  }))
})

ipcMain.handle('web-inspect', async (_, { tabId }) => {
  try {
    if (!mainWindow) return
    const ses = require('electron').session.fromPartition('persist:antersurf')
    const wcs = ses.getAllRunningWebContents()
    for (const wc of wcs) {
      if (wc.id === tabId) { wc.inspectElement(0, 0); break }
    }
  } catch {}
})
