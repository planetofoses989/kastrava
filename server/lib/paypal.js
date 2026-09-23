// PayPal Orders API v2 glue (create + server-side capture) via plain fetch.
// No SDK dependency. Money flow:
//   site -> POST /api/pp-order {machine_id} -> PayPal order id
//   buyer approves in the PayPal buttons popup
//   site -> POST /api/pp-capture {order_id, machine_id}
//     -> server captures server-to-server (trusted, secret never leaves us)
//     -> license minted from the capture, same as the Razorpay path.
//
// Env:
//   PAYPAL_CLIENT_ID / PAYPAL_SECRET   REST app credentials (sandbox or live)
//   PAYPAL_MODE                        'live' or anything else = sandbox
// Without credentials the server runs in DEV mode with synthetic orders,
// mirroring server/lib/razorpay.js, so the whole flow is testable locally.
const BASE_LIVE = 'https://api-m.paypal.com'
const BASE_SANDBOX = 'https://api-m.sandbox.paypal.com'

function mode() {
  return String(process.env.PAYPAL_MODE || 'sandbox').toLowerCase() === 'live'
    ? 'live'
    : 'sandbox'
}

function base() {
  return mode() === 'live' ? BASE_LIVE : BASE_SANDBOX
}

function hasKeys() {
  return !!(process.env.PAYPAL_CLIENT_ID && process.env.PAYPAL_SECRET)
}

function isDev() {
  return !hasKeys()
}

let cachedToken = null
let cachedExp = 0

async function token() {
  if (cachedToken && Date.now() < cachedExp) return cachedToken
  const id = process.env.PAYPAL_CLIENT_ID
  const secret = process.env.PAYPAL_SECRET
  const res = await fetch(base() + '/v1/oauth2/token', {
    method: 'POST',
    headers: {
      Authorization: 'Basic ' + Buffer.from(id + ':' + secret).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: 'grant_type=client_credentials'
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok || !body.access_token) {
    throw new Error('paypal auth failed: ' + res.status + ' ' + JSON.stringify(body).slice(0, 200))
  }
  cachedToken = body.access_token
  cachedExp = Date.now() + Math.max(0, (body.expires_in || 300) - 60) * 1000
  return cachedToken
}

async function createOrder(amountUsd, machineId) {
  if (isDev()) {
    return {
      dev: true,
      order_id: 'ppdev_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8),
      amount: amountUsd,
      currency: 'USD'
    }
  }
  const tok = await token()
  const res = await fetch(base() + '/v2/checkout/orders', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + tok,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      intent: 'CAPTURE',
      purchase_units: [{
        amount: { currency_code: 'USD', value: String(amountUsd) },
        description: 'Kastrava Premium — 34 days, one machine',
        custom_id: String(machineId || '').slice(0, 127) || undefined
      }]
    })
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok || !body.id) {
    throw new Error('paypal order error: ' + res.status + ' ' + JSON.stringify(body).slice(0, 300))
  }
  return { order_id: body.id, amount: amountUsd, currency: 'USD' }
}

// Server-side capture. The buyer's approval alone never mints a license —
// only a COMPLETED capture response from PayPal (authenticated with our
// secret) settles the order. Returns { captureId, status, amount, currency }.
async function capture(orderId) {
  if (isDev()) {
    if (!String(orderId || '').startsWith('ppdev_')) {
      throw new Error('unknown dev order')
    }
    return { captureId: 'CAPDEV-' + Date.now().toString(36), status: 'COMPLETED', amount: null, currency: 'USD' }
  }
  const tok = await token()
  const res = await fetch(base() + '/v2/checkout/orders/' + encodeURIComponent(orderId) + '/capture', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + tok,
      'Content-Type': 'application/json'
    },
    body: '{}'
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    throw new Error('paypal capture error: ' + res.status + ' ' + JSON.stringify(body).slice(0, 300))
  }
  try {
    const cap = body.purchase_units[0].payments.captures[0]
    return {
      captureId: cap.id,
      status: cap.status,
      amount: cap.amount && cap.amount.value,
      currency: cap.amount && cap.amount.currency_code
    }
  } catch {
    throw new Error('paypal capture unparseable: ' + JSON.stringify(body).slice(0, 300))
  }
}

module.exports = { mode, hasKeys, isDev, createOrder, capture }
