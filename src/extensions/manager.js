const { session, dialog } = require('electron')
const fs = require('fs')
const path = require('path')
const https = require('https')
const http = require('http')
const { spawnSync } = require('child_process')
const ExtensionRegistry = require('./registry')

let registry
let mainWindow
const SESSION_PARTITION = 'kastrava'

function init(win) {
  mainWindow = win
  registry = new ExtensionRegistry()
}

function loadAll() {
  if (!registry) return
  const ses = session.fromPartition(SESSION_PARTITION)
  const exts = registry.list()
  for (const ext of exts) {
    if (ext.enabled && ext.path) {
      try {
        ses.loadExtension(ext.path, { allowFileAccess: true }).catch(e => {
          console.error('[ExtMgr] load failed:', ext.id, e.message)
        })
      } catch (e) {
        console.error('[ExtMgr] load error:', ext.id, e.message)
      }
    }
  }
}

function list() {
  if (!registry) return []
  return registry.list().map(ext => {
    let icon = null
    try {
      const mf = JSON.parse(fs.readFileSync(path.join(ext.path, 'manifest.json'), 'utf-8'))
      if (mf.icons) {
        const sizes = Object.keys(mf.icons).map(Number).sort((a, b) => b - a)
        if (sizes.length) icon = path.join(ext.path, mf.icons[sizes[0]])
      }
    } catch {}
    return { id: ext.id, name: ext.name, version: ext.version, enabled: ext.enabled, icon, description: ext.description || '', path: ext.path }
  })
}

async function loadDirectory(dirPath) {
  const mfPath = path.join(dirPath, 'manifest.json')
  if (!fs.existsSync(mfPath)) throw new Error('No manifest.json found in directory')
  const mf = JSON.parse(fs.readFileSync(mfPath, 'utf-8'))
  if (!mf.name || !mf.version) throw new Error('manifest.json missing name or version')
  const ses = session.fromPartition(SESSION_PARTITION)
  let chromeId = null
  try {
    const loaded = await ses.loadExtension(dirPath, { allowFileAccess: true })
    if (loaded && loaded.id) chromeId = loaded.id
  } catch (e) {
    console.error('[ExtMgr] loadExtension error:', e.message)
    throw new Error('Failed to load extension: ' + e.message)
  }
  const id = chromeId || (mf.name.toLowerCase().replace(/[^a-z0-9]/g, '-') + '-' + mf.version)
  const ext = { id, name: mf.name, version: mf.version, path: dirPath, enabled: true, description: mf.description || '', chromeId: chromeId || null }
  registry.add(ext)
  if (mainWindow) mainWindow.webContents.send('extensions-updated', list())
  return ext
}

async function loadCrx() {
  const r = await dialog.showOpenDialog(mainWindow, {
    title: 'Import Extension',
    filters: [{ name: 'Extension', extensions: ['crx', 'zip'] }],
    properties: ['openFile']
  })
  if (r.canceled || !r.filePaths.length) return null
  const filePath = r.filePaths[0]
  const extDir = path.join(registry.dataDir, 'unpacked-' + Date.now())
  fs.mkdirSync(extDir, { recursive: true })

  if (filePath.endsWith('.crx')) {
    const buf = fs.readFileSync(filePath)
    const zipData = _extractCrxZip(buf)
    const tmpZip = path.join(extDir, 'ext.zip')
    fs.writeFileSync(tmpZip, zipData)
    spawnSync('unzip', ['-o', tmpZip, '-d', extDir])
    fs.unlinkSync(tmpZip)
  } else {
    spawnSync('unzip', ['-o', filePath, '-d', extDir])
  }

  const mfPath = path.join(extDir, 'manifest.json')
  if (!fs.existsSync(mfPath)) throw new Error('No manifest.json found in archive')
  return await loadDirectory(extDir)
}

function remove(id) {
  if (!registry) return
  const ext = registry.get(id)
  if (ext) {
    const ses = session.fromPartition(SESSION_PARTITION)
    const removeId = ext.chromeId || id
    try { ses.removeExtension(removeId) } catch (e) { console.error('[ExtMgr] removeExtension error:', e.message) }
    if (ext.path && fs.existsSync(ext.path)) {
      try { fs.rmSync(ext.path, { recursive: true, force: true }) } catch {}
    }
  }
  registry.remove(id)
  if (mainWindow) mainWindow.webContents.send('extensions-updated', list())
}

function toggle(id) {
  if (!registry) return
  const ext = registry.toggle(id)
  if (ext) {
    const ses = session.fromPartition(SESSION_PARTITION)
    const removeId = ext.chromeId || id
    if (ext.enabled && ext.path) {
      ses.loadExtension(ext.path, { allowFileAccess: true }).then(loaded => {
        if (loaded && loaded.id && !ext.chromeId) {
          ext.chromeId = loaded.id
          registry.add(ext)
        }
      }).catch(e => console.error('[ExtMgr] load error:', e.message))
    } else {
      try { ses.removeExtension(removeId) } catch {}
    }
  }
  if (mainWindow) mainWindow.webContents.send('extensions-updated', list())
  return ext
}

function getInfo(id) {
  if (!registry) return null
  const ext = registry.get(id)
  if (!ext) return null
  let icon = null
  try {
    const mf = JSON.parse(fs.readFileSync(path.join(ext.path, 'manifest.json'), 'utf-8'))
    if (mf.icons) {
      const sizes = Object.keys(mf.icons).map(Number).sort((a, b) => b - a)
      if (sizes.length) icon = path.join(ext.path, mf.icons[sizes[0]])
    }
  } catch {}
  return { id: ext.id, name: ext.name, version: ext.version, enabled: ext.enabled, icon, description: ext.description || '' }
}

function _downloadFile(url, dest, headers, _redirectCount) {
  _redirectCount = _redirectCount || 0
  if (_redirectCount > 10) return Promise.reject(new Error('Too many redirects'))
  return new Promise((resolve, reject) => {
    const client = url.startsWith('https') ? https : http
    const file = fs.createWriteStream(dest)
    const opts = typeof headers === 'object' && headers ? { headers } : {}
    const req = url.startsWith('https')
      ? https.get(url, opts, onRes)
      : http.get(url, opts, onRes)
    function onRes(res) {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume()
        file.close()
        try { fs.unlinkSync(dest) } catch {}
        return _downloadFile(res.headers.location, dest, headers, _redirectCount + 1).then(resolve).catch(reject)
      }
      if (res.statusCode !== 200) {
        file.close()
        try { fs.unlinkSync(dest) } catch {}
        return reject(new Error('HTTP ' + res.statusCode))
      }
      res.pipe(file)
      file.on('finish', () => { file.close(); resolve() })
    }
    req.on('error', (e) => { file.close(); try { fs.unlinkSync(dest) } catch {}; reject(e) })
  })
}

function _extractCrxZip(buf) {
  if (buf.length < 16) throw new Error('CRX file too small')
  const magic = buf.slice(0, 4).toString('ascii')
  if (magic !== 'Cr24') throw new Error('Not a valid CRX file')
  const version = buf.readUInt32LE(4)
  const headerLen = buf.readUInt32LE(8)
  if (version === 2) {
    const sigLen = buf.readUInt32LE(12)
    return buf.slice(16 + headerLen + sigLen)
  }
  if (version === 3) {
    return buf.slice(12 + headerLen)
  }
  throw new Error('Unsupported CRX version: ' + version)
}

async function installFromUrl(url) {
  if (!registry) return null
  const tmpDir = path.join(registry.dataDir, 'dl-' + Date.now())
  fs.mkdirSync(tmpDir, { recursive: true })
  const tmpFile = path.join(tmpDir, 'ext.zip')

  await _downloadFile(url, tmpFile)

  let fileData = fs.readFileSync(tmpFile)
  const isCrx = fileData.length > 4 && fileData.slice(0, 4).toString('ascii') === 'Cr24'
  if (isCrx) {
    fileData = _extractCrxZip(fileData)
    fs.writeFileSync(tmpFile, fileData)
  }

  const extDir = path.join(registry.dataDir, 'ext-' + Date.now())
  fs.mkdirSync(extDir, { recursive: true })
  spawnSync('unzip', ['-o', tmpFile, '-d', extDir])
  try { fs.unlinkSync(tmpFile) } catch {}
  try { fs.rmdirSync(tmpDir) } catch {}

  const mfPath = path.join(extDir, 'manifest.json')
  if (!fs.existsSync(mfPath)) {
    const entries = fs.readdirSync(extDir)
    const nested = entries.find(e => fs.existsSync(path.join(extDir, e, 'manifest.json')))
    if (nested) {
      const innerDir = path.join(extDir, nested)
      const finalDir = path.join(registry.dataDir, 'ext-' + Date.now())
      fs.renameSync(innerDir, finalDir)
      try { fs.rmdirSync(extDir) } catch {}
      return await loadDirectory(finalDir)
    }
    throw new Error('No manifest.json found in downloaded extension')
  }
  return await loadDirectory(extDir)
}

function _extractCwsId(url) {
  const m = url.match(/chrome\.google\.com\/webstore\/detail\/[^/]+\/([a-z]{32})/i) ||
            url.match(/chromewebstore\.google\.com\/detail\/[^/]+\/([a-z]{32})/i) ||
            url.match(/[?&]id=([a-z]{32})/i)
  return m ? m[1] : null
}

async function installFromCws(url) {
  if (!registry) return null
  const extId = _extractCwsId(url)
  if (!extId) throw new Error('Could not extract extension ID from Chrome Web Store URL')

  const crxUrl = `https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0&acceptformat=crx2,crx3&x=id%3D${extId}%26uc`
  const headers = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Referer': 'https://chromewebstore.google.com/'
  }
  const tmpDir = path.join(registry.dataDir, 'cws-' + Date.now())
  fs.mkdirSync(tmpDir, { recursive: true })
  const tmpCrx = path.join(tmpDir, 'ext.crx')

  await _downloadFile(crxUrl, tmpCrx, headers)

  const buf = fs.readFileSync(tmpCrx)
  const zipData = _extractCrxZip(buf)
  const tmpZip = path.join(tmpDir, 'ext.zip')
  fs.writeFileSync(tmpZip, zipData)

  const extDir = path.join(registry.dataDir, 'ext-' + Date.now())
  fs.mkdirSync(extDir, { recursive: true })
  spawnSync('unzip', ['-o', tmpZip, '-d', extDir])
  try { fs.unlinkSync(tmpCrx) } catch {}
  try { fs.unlinkSync(tmpZip) } catch {}
  try { fs.rmdirSync(tmpDir) } catch {}

  const mfPath = path.join(extDir, 'manifest.json')
  if (!fs.existsSync(mfPath)) {
    const entries = fs.readdirSync(extDir)
    const nested = entries.find(e => fs.existsSync(path.join(extDir, e, 'manifest.json')))
    if (nested) {
      const innerDir = path.join(extDir, nested)
      const finalDir = path.join(registry.dataDir, 'ext-' + Date.now())
      fs.renameSync(innerDir, finalDir)
      try { fs.rmdirSync(extDir) } catch {}
      return await loadDirectory(finalDir)
    }
    throw new Error('No manifest.json found in Chrome Web Store extension')
  }
  return await loadDirectory(extDir)
}

module.exports = { init, loadAll, list, loadDirectory, loadCrx, installFromUrl, installFromCws, remove, toggle, getInfo }
