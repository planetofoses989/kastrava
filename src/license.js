// Kastrava Premium licensing (main process).
// - machineId(): stable one-way hardware fingerprint -> this PC only
// - verify(): local Ed25519 check of the signed license blob (public key embedded)
// - activate(): phones the license server to bind this PC to the buyer's key
// The private half of the signing key never leaves the seller's machine.
const os = require('os')
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const { app } = require('electron')
const PUBLIC_KEY = require('./kastraPublic')
const API = __KAS_API__

// The machine identity must stay stable across reboots, network changes, kernel
// upgrades and reinstalls — otherwise a legitimately-activated user would get
// locked out. MACs flap around boot (and with VPNs), so we anchor on the OS
// install identity instead.
function osAnchor() {
  if (process.platform === 'linux') {
    try {
      const v = fs.readFileSync('/etc/machine-id', 'utf8').trim()
      if (v) return v
    } catch {}
  }
  if (process.platform === 'darwin') {
    try {
      const v = fs.readFileSync('/var/db/.SystemInfo.InstallationIdentity', 'latin1')
      if (v) return v.trim() || v
    } catch {}
  }
  try {
    const p = path.join(app.getPath('userData'), 'machine.id')
    if (fs.existsSync(p)) return fs.readFileSync(p, 'utf8').trim()
    const seed = crypto.randomUUID()
    fs.mkdirSync(path.dirname(p), { recursive: true })
    fs.writeFileSync(p, seed, { mode: 0o600 })
    return seed
  } catch {}
  return os.hostname()
}

function machineIdRaw() {
  const parts = [os.platform(), os.arch(), osAnchor()]
  return crypto.createHash('sha256').update(parts.join('|')).digest('hex').toUpperCase()
}

// Display format: KAS2-XXXX-XXXX-... in 4-char groups.
function machineCode() {
  const raw = machineIdRaw()
  return 'KAS2-' + raw.replace(/(.{4})/g, '$1-').replace(/-$/, '')
}

function licensePath() {
  return path.join(app.getPath('userData'), 'license.json')
}

function loadLicense() {
  try {
    return JSON.parse(fs.readFileSync(licensePath(), 'utf8'))
  } catch {
    return null
  }
}

function saveLicense(lic) {
  try {
    const dir = path.dirname(licensePath())
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(licensePath(), JSON.stringify(lic, null, 2), { mode: 0o600 })
    return true
  } catch (e) {
    console.error('[license] save error', e)
    return false
  }
}

function verifyPayload(payload, sig) {
  if (!payload || !sig) return { ok: false, reason: 'no_license' }
  try {
    const good = crypto.verify(null, Buffer.from(JSON.stringify(payload), 'utf8'), PUBLIC_KEY, Buffer.from(sig, 'base64'))
    if (!good) return { ok: false, reason: 'bad_signature' }
  } catch {
    return { ok: false, reason: 'bad_signature' }
  }
  if (payload.iss !== 'kastrasoft' || payload.product !== 'kastrava-premium') {
    return { ok: false, reason: 'bad_issuer' }
  }
  const now = Date.now() / 1000
  if (payload.exp && now > payload.exp) return { ok: false, reason: 'expired' }
  if ((payload.mid || '').toUpperCase() !== machineCode()) return { ok: false, reason: 'machine_mismatch' }
  // Grace period: the billing period ended (sub_end) but exp (sub_end +
  // grace days) hasn't passed yet — still unlocked, UI nudges a renewal.
  const grace = !!(payload.sub_end && now > payload.sub_end)
  return { ok: true, grace }
}

function status() {
  const lic = loadLicense()
  const code = machineCode()
  if (!lic || !lic.payload) {
    return { activated: false, edition: 'premium', machine: code, key: null, reason: 'no_license', expiresAt: null, subEnd: null, grace: false }
  }
  const v = verifyPayload(lic.payload, lic.sig)
  return {
    activated: v.ok,
    edition: 'premium',
    machine: code,
    key: lic.key || null,
    reason: v.reason || null,
    expiresAt: v.ok && lic.payload.exp ? lic.payload.exp * 1000 : null,
    subEnd: v.ok && lic.payload.sub_end ? lic.payload.sub_end * 1000 : null,
    grace: v.ok && !!v.grace,
    iat: lic.payload.iat ? lic.payload.iat * 1000 : null
  }
}

async function activate(key) {
  const machine = machineCode()
  try {
    const res = await fetch(API.replace(/\/$/, '') + '/api/activate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key: String(key || '').trim(), machine_id: machine }),
      signal: AbortSignal.timeout(20000)
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) {
      const msg = body.msg || 'Activation failed (' + res.status + ')'
      if (body.error === 'machine_mismatch') return { ok: false, error: 'machine_mismatch', msg }
      if (body.error === 'invalid_key') return { ok: false, error: 'invalid_key', msg }
      return { ok: false, error: 'server', msg }
    }
    if (!body.license) return { ok: false, error: 'server', msg: 'Empty activation response' }
    const lic = { key: body.license.key, payload: body.license.payload, sig: body.license.sig, activated_at: Date.now() }
    saveLicense(lic)
    return { ok: true, license: lic }
  } catch (e) {
    return { ok: false, error: 'network', msg: 'Could not reach the Kastrava license server. Check your connection (' + API + ').' }
  }
}

function clear() {
  try { fs.rmSync(licensePath(), { force: true }) } catch {}
}

// Silent renewal pickup: activation is idempotent per machine, so calling it
// again on startup fetches a freshly-signed license with the renewed expiry
// (extended server-side by the Razorpay webhook after each successful charge).
async function refreshIfLicensed() {
  const lic = loadLicense()
  if (!lic || !lic.key) return
  if (!status().activated) return
  await activate(lic.key).catch(() => {})
}

module.exports = { machineCode, machineIdRaw, status, activate, verifyPayload, loadLicense, refreshIfLicensed, clear, API }