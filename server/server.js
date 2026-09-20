// Kastrava license/Payment server. Serves the site + payment+license API.
//   npm run server            -> dev mode (no Razorpay keys needed)
//   RAZORPAY_KEY_ID=.. RAZORPAY_KEY_SECRET=.. ADMIN_TOKEN=.. npm run server
// Env (also readable from server/.env):
//   PORT                  default 8787
//   BIND_HOST             interface to bind, default 127.0.0.1 (0.0.0.0 for a public/bare deployment)
//   KAS_HOST              public base URL used in responses, default http://127.0.0.1:8787
//   PRICE_INR             subscription price per 34-day billing cycle, default 199
//   GRACE_DAYS            days past expiry before access is revoked, default 3
//   RAZORPAY_PLAN_ID      34-day plan id (optional; cached in DATA_DIR/plan.json)
//   RAZORPAY_WEBHOOK_SECRET  secret for /api/webhook signature verification
//   LICENSE_YEARS         legacy fallback for old one-time keys, default 10
//   PREMIUM_BUILD         filesystem path to the premium install package served after payment
//   DATA_DIR              store location, default ../data
const http = require('http')
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

require('./lib/env').loadEnv()
const sign = require('./lib/sign')
const razorpay = require('./lib/razorpay')

const port = parseInt(process.env.PORT || '8787', 10)
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1'
const HOST = process.env.KAS_HOST || 'http://127.0.0.1:' + port
const PRICE_INR = parseInt(process.env.PRICE_INR || '199', 10)
const GRACE_DAYS = parseInt(process.env.GRACE_DAYS || '3', 10)
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
      let parsed = {}
      try { parsed = JSON.parse(data || '{}') } catch {}
      resolve({ raw: data, parsed })
    })
    req.on('error', () => resolve({ raw: data, parsed: {} }))
  })
}

function licenseExpirySeconds(lic) {
  let end = null
  if (lic && lic.expires_at) end = Math.floor(new Date(lic.expires_at).getTime() / 1000)
  // Fall back to the subscription's period end (covers licenses issued
  // before the expiry was seeded).
  if (!end && lic && lic.subscription_id) {
    const sub = store.getSubscription(lic.subscription_id)
    if (sub && sub.current_end) end = Math.floor(new Date(sub.current_end).getTime() / 1000)
  }
  if (!end) return null
  return end + GRACE_DAYS * 86400
}

function makeLicensePayload(key, machineId) {
  const now = Math.floor(Date.now() / 1000)
  const lic = store.getLicense(key)
  const exp = licenseExpirySeconds(lic)
  const payload = {
    sub: key,
    mid: (machineId || '').toUpperCase(),
    product: 'kastrava-premium',
    edition: 'premium',
    iss: 'kastrasoft',
    iat: now,
    // Subscription keys expire at period end + grace; legacy one-time
    // keys (no expires_at in store) keep the long LICENSE_YEARS lifetime.
    exp: exp || now + LICENSE_YEARS * 365 * 24 * 3600
  }
  if (lic && lic.expires_at) payload.sub_end = Math.floor(new Date(lic.expires_at).getTime() / 1000)
  return payload
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
  const { raw, parsed: body } = await readBody(req)

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

  // ---- subscriptions (₹199/34 days, auto-renew, webhook-driven) ----

  if (pathname === '/api/subscribe') {
    try {
      const planId = razorpay.ensurePlan(DATA_DIR, PRICE_INR * 100)
      const s = await razorpay.createSubscription(planId)
      const meta = {}
      if (typeof body.name === 'string' && body.name) meta.name = body.name
      if (typeof body.email === 'string' && body.email) meta.email = body.email
      store.createSubscription(s.subscription_id, meta)
      return json(res, 200, { subscription_id: s.subscription_id, key_id: s.key_id, dev: !!s.dev })
    } catch (e) {
      return json(res, 500, { error: 'subscribe_failed', msg: String(e.message || e) })
    }
  }

  if (pathname === '/api/verify-subscription') {
    const { subscription_id, payment_id, signature } = body
    if (!subscription_id || !payment_id) return json(res, 400, { error: 'bad_request' })
    const sub = store.getSubscription(String(subscription_id))
    if (!sub) return json(res, 404, { error: 'subscription_not_found' })
    if (sub.status === 'active' || sub.status === 'paid') {
      const k = store.keyForSubscription(String(subscription_id))
      return json(res, 200, { ok: true, already_paid: true, key: k })
    }
    if (!razorpay.verifySubSignature(String(payment_id), String(subscription_id), String(signature || ''))) {
      return json(res, 403, { error: 'bad_signature', msg: 'Payment could not be verified.' })
    }
    // Pull the authoritative period end from Razorpay (dev mode returns a
    // synthetic one). Fallback: one month from now.
    let currentEnd = null
    try {
      const rs = await razorpay.fetchSubscription(String(subscription_id))
      if (rs && rs.current_end) currentEnd = new Date(rs.current_end * 1000).toISOString()
    } catch {}
    if (!currentEnd && !razorpay.isDev()) currentEnd = new Date(Date.now() + 31 * 86400 * 1000).toISOString()
    store.markSubPaid(String(subscription_id), String(payment_id), currentEnd)
    let key = store.keyForSubscription(String(subscription_id))
    if (!key) {
      key = sign.makeLicenseKey()
      store.issueLicense(key, null, String(subscription_id))
    }
    // Seed the license expiry from the subscription's period end.
    if (currentEnd) store.extendLicense(key, currentEnd)
    return json(res, 200, { ok: true, key, already_paid: false })
  }

  // Razorpay webhook: renews extend the license expiry; cancellations stop it.
  if (pathname === '/api/webhook') {
    if (!razorpay.verifyWebhookSignature(raw, (req.headers['x-razorpay-signature'] || '').toString())) {
      return json(res, 400, { error: 'bad_signature', msg: 'Webhook signature verification failed.' })
    }
    try {
      const ent = body.payload && body.payload.subscription && body.payload.subscription.entity
      if (ent && ent.id) {
        const subId = String(ent.id)
        const sub = store.getSubscription(subId)
        if (sub) {
          if (ent.current_end) {
            const key = store.keyForSubscription(subId)
            if (key) store.extendLicense(key, new Date(ent.current_end * 1000).toISOString())
          }
          if (body.event === 'subscription.charged' || body.event === 'subscription.activated') {
            store.setSubscriptionStatus(subId, 'active')
          } else if (body.event === 'subscription.cancelled' || body.event === 'subscription.completed' || body.event === 'subscription.halted') {
            store.setSubscriptionStatus(subId, 'cancelled')
          }
        }
      }
    } catch (e) {
      console.error('[webhook] error:', e)
    }
    return json(res, 200, { ok: true })
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
      return json(res, 200, { ok: true, dev: razorpay.isDev(), host: HOST, price: PRICE_INR, grace_days: GRACE_DAYS, version: '27.0.0' })
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

server.listen(port, BIND_HOST, () => {
  console.log('[kastrava-licenses] listening on http://' + BIND_HOST + ':' + port)
  console.log('[kastrava-licenses] host=' + HOST + ' price=INR ' + PRICE_INR + '/34d grace=' + GRACE_DAYS + 'd dev=' + razorpay.isDev())
  console.log('[kastrava-licenses] premium_build=' + (PREMIUM_BUILD || '(not configured — set PREMIUM_BUILD)'))
})