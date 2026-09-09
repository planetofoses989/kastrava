// Razorpay API glue (orders + signature verification) via plain fetch.
// Without RAZORPAY_KEY_ID/SECRET the server runs in DEV mode: orders are
// synthetic, any payment signature is accepted, so the whole flow can be
// tested locally with no credentials.
const crypto = require('crypto')
const BASE = 'https://api.razorpay.com/v1'

function hasKeys() {
  return !!(process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET)
}

function isDev() {
  return !hasKeys()
}

async function createOrder(amountPaise) {
  if (isDev()) {
    return {
      dev: true,
      order_id: 'dev_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8),
      amount: amountPaise,
      currency: 'INR',
      key_id: 'rzp_test_dev'
    }
  }
  const auth = 'Basic ' + Buffer.from(process.env.RAZORPAY_KEY_ID + ':' + process.env.RAZORPAY_KEY_SECRET).toString('base64')
  const res = await fetch(BASE + '/orders', {
    method: 'POST',
    headers: {
      Authorization: auth,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ amount: amountPaise, currency: 'INR', notes: { product: 'kastrava-premium' } })
  })
  const body = await res.json()
  if (!res.ok) throw new Error('razorpay order error: ' + res.status + ' ' + JSON.stringify(body))
  return { order_id: body.id, amount: body.amount, currency: body.currency, key_id: process.env.RAZORPAY_KEY_ID }
}

// Razorpay signs order_id|payment_id with the webhook secret.
function verifySignature(orderId, paymentId, signature) {
  if (isDev()) return true
  const secret = process.env.RAZORPAY_KEY_SECRET
  try {
    const expected = crypto
      .createHmac('sha256', secret)
      .update(orderId + '|' + paymentId)
      .digest('hex')
    const a = Buffer.from(expected, 'hex')
    const b = Buffer.from(signature, 'hex')
    return a.length === b.length && crypto.timingSafeEqual(a, b)
  } catch {
    return false
  }
}

module.exports = { createOrder, verifySignature, isDev, hasKeys }