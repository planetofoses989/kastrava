const fs = require('fs')
const path = require('path')
const { app } = require('electron')

class ExtensionRegistry {
  constructor() {
    this.dataDir = path.join(app.getPath('userData'), 'data')
    this.filePath = path.join(this.dataDir, 'extensions.json')
    this.extensions = []
    this._load()
  }

  _load() {
    try {
      fs.mkdirSync(this.dataDir, { recursive: true })
      const raw = fs.readFileSync(this.filePath, 'utf-8')
      this.extensions = JSON.parse(raw)
    } catch {
      this.extensions = []
    }
  }

  _save() {
    try {
      fs.mkdirSync(this.dataDir, { recursive: true })
      fs.writeFileSync(this.filePath, JSON.stringify(this.extensions, null, 2))
    } catch (e) {
      console.error('[ExtRegistry] save error:', e)
    }
  }

  list() { return this.extensions }

  add(ext) {
    const existing = this.extensions.find(e => e.id === ext.id)
    if (existing) {
      Object.assign(existing, ext)
    } else {
      this.extensions.push(ext)
    }
    this._save()
  }

  remove(id) {
    this.extensions = this.extensions.filter(e => e.id !== id)
    this._save()
  }

  toggle(id) {
    const ext = this.extensions.find(e => e.id === id)
    if (ext) { ext.enabled = !ext.enabled; this._save() }
    return ext
  }

  get(id) {
    return this.extensions.find(e => e.id === id)
  }
}

module.exports = ExtensionRegistry
