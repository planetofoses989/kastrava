// Razorpay API glue (orders, subscriptions, plans, webhook signature
// verification) via plain fetch. Without RAZORPAY_KEY_ID/SECRET the server
// runs in DEV mode: orders/subscriptions are synthetic, any payment
// signature is accepted, so the whole flow can be tested locally with no
// credentials.
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const BASE = 'https://api.razorpay.com/v1'

function hasKeys() {
  return !!(process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET)
}

function isDev() {
  return !hasKeys()
}

function auth() {
  return 'Basic ' + Buffer.from(process.env.RAZORPAY_KEY_ID + ':' + process.env.RAZORPAY_KEY_SECRET).toString('base64')
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
  const res = await fetch(BASE + '/orders', {
    method: 'POST',
    headers: { Authorization: auth(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ amount: amountPaise, currency: 'INR', notes: { product: 'kastrava-premium' } })
  })
  const body = await res.json()
  if (!res.ok) throw new Error('razorpay order error: ' + res.status + ' ' + JSON.stringify(body))
  return { order_id: body.id, amount: body.amount, currency: body.currency, key_id: process.env.RAZORPAY_KEY_ID }
}

// Fetch (or self-provision) the 34-day plan for the subscription flow.
// Resolution order: RAZORPAY_PLAN_ID env -> DATA_DIR/plan.json cache ->
// create via API and cache. Idempotent across restarts. Dev mode returns a
// synthetic plan id.
function ensurePlan(dataDir, amountPaise) {
  if (isDev()) return 'dev_plan_34d'
  if (process.env.RAZORPAY_PLAN_ID) return process.env.RAZORPAY_PLAN_ID
  const cacheFile = path.join(dataDir, 'plan.json')
  try {
    const cached = JSON.parse(fs.readFileSync(cacheFile, 'utf8'))
    if (cached && cached.plan_id && cached.amount === amountPaise) return cached.plan_id
  } catch {}
  throw new Error('no_plan: set RAZORPAY_PLAN_ID, or create the 34-day plan in the Razorpay dashboard and cache it in ' + cacheFile)
}

// Create the plan synchronously via API (used by `npm run plan:create`).
async function createPlan(amountPaise) {
  if (isDev()) return { dev: true, plan_id: 'dev_plan' }
  const res = await fetch(BASE + '/plans', {
    method: 'POST',
    headers: { Authorization: auth(), 'Content-Type': 'application/json' },
    body: JSON.stringify({
      period: 'daily',
      interval: 34,
      item: { name: 'Kastrava Premium', amount: amountPaise, currency: 'INR', description: 'Kastrava Premium — 34-day cycle, one machine' }
    })
  })
  const body = await res.json()
  if (!res.ok) throw new Error('razorpay plan error: ' + res.status + ' ' + JSON.stringify(body))
  return { plan_id: body.id, amount: body.amount }
}

async function createSubscription(planId) {
  if (isDev()) {
    return {
      dev: true,
      subscription_id: 'dev_sub_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8),
      key_id: 'rzp_test_dev'
    }
  }
  const res = await fetch(BASE + '/subscriptions', {
    method: 'POST',
    headers: { Authorization: auth(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ plan_id: planId, total_count: 24, customer_notify: 1, notes: { product: 'kastrava-premium' } })
  })
  const body = await res.json()
  if (!res.ok) throw new Error('razorpay subscription error: ' + res.status + ' ' + JSON.stringify(body))
  return { subscription_id: body.id, key_id: process.env.RAZORPAY_KEY_ID }
}

async function fetchSubscription(subscriptionId) {
  if (isDev()) return { id: subscriptionId, status: 'active', current_end: Math.floor(Date.now() / 1000) + 31 * 86400 }
  const res = await fetch(BASE + '/subscriptions/' + encodeURIComponent(subscriptionId), {
    headers: { Authorization: auth() }
  })
  const body = await res.json()
  if (!res.ok) throw new Error('razorpay subscription fetch error: ' + res.status + ' ' + JSON.stringify(body))
  return body
}

// One-time checkout signs order_id|payment_id with the key secret.
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

// Subscription checkout signs payment_id|subscription_id with the key secret.
function verifySubSignature(paymentId, subscriptionId, signature) {
  if (isDev()) return true
  const secret = process.env.RAZORPAY_KEY_SECRET
  try {
    const expected = crypto
      .createHmac('sha256', secret)
      .update(paymentId + '|' + subscriptionId)
      .digest('hex')
    const a = Buffer.from(expected, 'hex')
    const b = Buffer.from(signature, 'hex')
    return a.length === b.length && crypto.timingSafeEqual(a, b)
  } catch {
    return false
  }
}

// Webhooks sign the raw request body with the webhook secret
// (X-Razorpay-Signature header).
function verifyWebhookSignature(rawBody, signature) {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET
  if (!secret || !signature) return false
  try {
    const expected = crypto.createHmac('sha256', secret).update(rawBody, 'utf8').digest('hex')
    const a = Buffer.from(expected, 'hex')
    const b = Buffer.from(String(signature), 'hex')
    return a.length === b.length && crypto.timingSafeEqual(a, b)
  } catch {
    return false
  }
}

module.exports = {
  createOrder,
  createPlan,
  ensurePlan,
  createSubscription,
  fetchSubscription,
  verifySignature,
  verifySubSignature,
  verifyWebhookSignature,
  isDev,
  hasKeys
}
