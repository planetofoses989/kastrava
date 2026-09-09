// Kastrava license/Payment server. Serves the site + payment+license API.
//   npm run server            -> dev mode (no Razorpay keys needed)
//   RAZORPAY_KEY_ID=.. RAZORPAY_KEY_SECRET=.. ADMIN_TOKEN=.. npm run server
// Env (also readable from server/.env):
//   PORT            default 8787
//   KAS_HOST        public base URL used in responses, default http://127.0.0.1:8787
//   PRICE_INR       price in rupees, default 500
//   LICENSE_YEARS   license lifetime in years, default 10
//   PREMIUM_BUILD   filesystem path to the premium install package served after payment
//   DATA_DIR        store location, default ../data
const http = require('http')
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

require('./lib/env').loadEnv()
const sign = require('./lib/sign')
const razorpay = require('./lib/razorpay')

const port = parseInt(process.env.PORT || '8787', 10)
const HOST = process.env.KAS_HOST || 'http://127.0.0.1:' + port
const PRICE_INR = parseInt(process.env.PRICE_INR || '500', 10)
const LICENSE_YEARS = parseInt(process.env.LICENSE_YEARS || '10', 10)
const PREMIUM_BUILD = process.env.PREMIUM_BUILD || ''
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data')
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || ''
const SITE_DIR = path.join(__dirname, '..', 'site')

const keys = sign.ensureKeys()
const store = new (require('./lib/store'))(path.join(DATA_DIR, 'db.json'))

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8',
  '.ico': 'image/x-icon',
  '.pdf': 'application/pdf',
  '.deb': 'application/vnd.debian.binary-package',
  '.zst': 'application/zstd',
  '.gz': 'application/gzip'
}

function json(res, code, obj) {
  const body = JSON.stringify(obj)
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Token',
    'Access-Control-Max-Age': '600'
  })
  res.end(body)
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = ''
    req.on('data', (c) => { data += c; if (data.length > 1e6) req.destroy() })
    req.on('end', () => {
      try { resolve(JSON.parse(data || '{}')) } catch { resolve({}) }
    })
    req.on('error', () => resolve({}))
  })
}

function makeLicensePayload(key, machineId) {
  const now = Math.floor(Date.now() / 1000)
  return {
    sub: key,
    mid: (machineId || '').toUpperCase(),
    product: 'kastrava-premium',
    edition: 'premium',
    iss: 'kastrasoft',
    iat: now,
    exp: now + LICENSE_YEARS * 365 * 24 * 3600
  }
}

function adminOk(req) {
  const t = (req.headers['x-admin-token'] || '').toString()
  return !!ADMIN_TOKEN && t.length === ADMIN_TOKEN.length && crypto.timingSafeEqual(Buffer.from(t), Buffer.from(ADMIN_TOKEN))
}

function serveStatic(req, res, pathname) {
  if (pathname === '/') pathname = '/index.html'
  let p = path.normalize(path.join(SITE_DIR, pathname))
  if (p !== SITE_DIR && !p.startsWith(SITE_DIR + path.sep)) return json(res, 403, { error: 'forbidden' })
  fs.stat(p, (err, st) => {
    if (err || !st.isFile()) return json(res, 404, { error: 'not_found' })
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(p).toLowerCase()] || 'application/octet-stream',
      'Content-Length': st.size,
      'X-Content-Type-Options': 'nosniff'
    })
    fs.createReadStream(p).pipe(res)
  })
}

function servePremium(res, key) {
  const lic = store.getLicense(key)
  if (!lic || (lic.status !== 'issued' && lic.status !== 'activated')) {
    return json(res, 403, { error: 'invalid_key', msg: 'Valid paid key required.' })
  }
  if (!PREMIUM_BUILD) return json(res, 404, { error: 'no_artifact', msg: 'Premium build not configured on this server yet.' })
  const file = path.resolve(PREMIUM_BUILD)
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) return json(res, 404, { error: 'no_artifact', msg: 'Premium build file missing.' })
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Content-Length': st.size,
      'Content-Disposition': 'attachment; filename="' + path.basename(file) + '"'
    })
    fs.createReadStream(file).pipe(res)
  })
}

async function handlePost(req, res, pathname) {
  const body = await readBody(req)

  if (pathname === '/api/order') {
    try {
      const o = await razorpay.createOrder(PRICE_INR * 100)
      const meta = {}
      if (typeof body.name === 'string' && body.name) meta.name = body.name
      if (typeof body.email === 'string' && body.email) meta.email = body.email
      store.createOrder(o.order_id, meta)
      return json(res, 200, { order_id: o.order_id, amount: o.amount, currency: o.currency, key_id: o.key_id, dev: !!o.dev })
    } catch (e) {
      return json(res, 500, { error: 'order_failed', msg: String(e.message || e) })
    }
  }

  if (pathname === '/api/verify') {
    const { order_id, payment_id, signature } = body
    if (!order_id || !payment_id) return json(res, 400, { error: 'bad_request' })
    const order = store.getOrder(order_id)
    if (!order) return json(res, 404, { error: 'order_not_found' })
    if (order.status === 'paid') {
      const k = store.keyForOrder(order_id)
      return json(res, 200, { ok: true, already_paid: true, key: k })
    }
    if (!razorpay.verifySignature(String(order_id), String(payment_id), String(signature || ''))) {
      return json(res, 403, { error: 'bad_signature', msg: 'Payment could not be verified.' })
    }
    store.markPaid(order_id, payment_id)
    let key = store.keyForOrder(order_id)
    if (!key) {
      key = sign.makeLicenseKey()
      store.issueLicense(key, order_id)
    }
    return json(res, 200, { ok: true, key, already_paid: false })
  }

  if (pathname === '/api/activate') {
    const key = String(body.key || '').trim().toUpperCase()
    const machineId = String(body.machine_id || '').trim().toUpperCase()
    if (!key || !machineId) return json(res, 400, { error: 'bad_request' })
    const lic = store.getLicense(key)
    if (!lic) return json(res, 404, { error: 'invalid_key', msg: 'No such license key.' })
    if (lic.status === 'activated' && lic.machine_id !== machineId) {
      return json(res, 403, { error: 'machine_mismatch', msg: 'This key is already activated on another machine.' })
    }
    if (lic.status === 'activated') {
      // Same machine re-activating: just re-sign, idempotent.
      const payload = makeLicensePayload(key, machineId)
      const sig = sign.signPayload(payload, keys.privateKey)
      return json(res, 200, { ok: true, license: { key, payload, sig }, status: 'renewed' })
    }
    store.bindLicense(key, machineId)
    const payload = makeLicensePayload(key, machineId)
    const sig = sign.signPayload(payload, keys.privateKey)
    return json(res, 200, { ok: true, license: { key, payload, sig }, status: 'activated' })
  }

  if (pathname === '/api/admin/release') {
    if (!adminOk(req)) return json(res, 401, { error: 'unauthorized' })
    const lic = store.releaseLicense(String(body.key || '').trim().toUpperCase())
    if (!lic) return json(res, 404, { error: 'invalid_key' })
    return json(res, 200, { ok: true })
  }

  if (pathname === '/api/admin/markpaid') {
    if (!adminOk(req)) return json(res, 401, { error: 'unauthorized' })
    const order = store.getOrder(body.order_id)
    if (!order) return json(res, 404, { error: 'order_not_found' })
    if (order.status !== 'paid') store.markPaid(body.order_id, body.payment_id || 'admin')
    let key = store.keyForOrder(body.order_id)
    if (!key) {
      key = sign.makeLicenseKey()
      store.issueLicense(key, body.order_id)
    }
    return json(res, 200, { ok: true, key })
  }

  return json(res, 404, { error: 'not_found' })
}

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Token',
      'Access-Control-Max-Age': '600'
    })
    return res.end()
  }

  const u = new URL(req.url, HOST + '/')
  const pathname = u.pathname

  if (req.method === 'POST') return handlePost(req, res, pathname)

  if (req.method === 'GET') {
    if (pathname === '/api/health') {
      return json(res, 200, { ok: true, dev: razorpay.isDev(), host: HOST, price: PRICE_INR, version: '27.0.0' })
    }
    const dl = pathname.match(/^\/api\/dl\/(.+)$/)
    if (dl) return servePremium(res, decodeURIComponent(dl[1]))
    if (pathname === '/api/admin/list') {
      if (!adminOk(req)) return json(res, 401, { error: 'unauthorized' })
      return json(res, 200, store.all())
    }
    return serveStatic(req, res, pathname)
  }

  return json(res, 405, { error: 'method_not_allowed' })
})

server.listen(port, () => {
  console.log('[kastrava-licenses] listening on http://127.0.0.1:' + port)
  console.log('[kastrava-licenses] host=' + HOST + ' price=INR ' + PRICE_INR + ' dev=' + razorpay.isDev())
  console.log('[kastrava-licenses] premium_build=' + (PREMIUM_BUILD || '(not configured — set PREMIUM_BUILD)'))
})