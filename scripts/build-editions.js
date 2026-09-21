#!/usr/bin/env node
// Builds an edition of the Kastrava app:
//   node scripts/build-editions.js premium   -> dist/    (KAS_API from env or default)
//   node scripts/build-editions.js free      -> dist-free/
// Embeds the server API URL (defines) and stamps the edition token into the
// hand-written inline browser.html (which webpack cannot transform).
const { spawnSync } = require('child_process')
const fs = require('fs')
const path = require('path')

const edition = process.argv[2]
if (!edition || !['premium', 'free'].includes(edition)) {
  console.error('usage: node scripts/build-editions.js <premium|free>')
  process.exit(1)
}

// API + store hosts. KAS_API is what the app uses for license/payment calls;
// KAS_STORE is where the built-in Subscribe button opens (#premium checkout).
// Both are stamped into the hand-written inline script in browser.html.
const KAS_API = process.env.KAS_API || 'http://127.0.0.1:8787'
const KAS_STORE = process.env.KAS_STORE || process.env.KAS_API || 'http://127.0.0.1:8787'

const OUT_DIR = edition === 'premium' ? 'dist' : 'dist-free'
const htmlFile = path.join(__dirname, '..', OUT_DIR, 'browser.html')

// 1) webpack build into the target dir (DefinePlugin injects __KAS_API__).
const r = spawnSync('npx', ['webpack', '--mode', 'production'], {
  cwd: path.join(__dirname, '..'),
  env: { ...process.env, OUT_DIR },
  stdio: 'inherit',
  // Windows: `npx` is npx.cmd, so plain spawn can't resolve it.
  shell: process.platform === 'win32'
})
if (r.status !== 0) process.exit(r.status || 1)

// 2) Stamp the edition token into the built renderer HTML.
if (!fs.existsSync(htmlFile)) {
  console.error('missing output file:', htmlFile)
  process.exit(1)
}
let html = fs.readFileSync(htmlFile, 'utf8')
html = html.split('__EDITION__').join(JSON.stringify(edition))
html = html.split('__KAS_API__').join(JSON.stringify(KAS_API))
html = html.split('__KAS_STORE__').join(JSON.stringify(KAS_STORE))
fs.writeFileSync(htmlFile, html)
console.log(`[build-editions] ${edition} edition written to ${OUT_DIR} (${html.length} bytes)`)
console.log(`[build-editions] KAS_API=${KAS_API} KAS_STORE=${KAS_STORE}`)
