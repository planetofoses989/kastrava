// Tiny JSON-backed store for orders + licenses. Used by the dev server and
// local installs alike; swap for SQLite when volume grows.
const fs = require('fs')
const path = require('path')

class Store {
  constructor(file) {
    this.file = file
    this.data = { orders: {}, subscriptions: {}, licenses: {} }
    this.load()
  }

  load() {
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'))
      this.data.orders = raw.orders || {}
      this.data.subscriptions = raw.subscriptions || {}
      this.data.licenses = raw.licenses || {}
    } catch {}
  }

  save() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true })
    fs.writeFileSync(this.file, JSON.stringify(this.data, null, 2), { mode: 0o600 })
  }

  // ---- orders ----
  createOrder(orderId, meta) {
    this.data.orders[orderId] = { status: 'created', created_at: new Date().toISOString(), ...meta }
    this.save()
    return this.data.orders[orderId]
  }

  getOrder(orderId) {
    return this.data.orders[orderId] || null
  }

  markPaid(orderId, paymentId) {
    const o = this.getOrder(orderId)
    if (!o) return null
    o.status = 'paid'
    o.payment_id = paymentId
    o.paid_at = new Date().toISOString()
    this.save()
    return o
  }

  keyForOrder(orderId) {
    for (const k in this.data.licenses) {
      if (this.data.licenses[k].order_id === orderId) return k
    }
    return null
  }

  // ---- subscriptions ----
  createSubscription(subId, meta) {
    this.data.subscriptions[subId] = { status: 'created', created_at: new Date().toISOString(), ...meta }
    this.save()
    return this.data.subscriptions[subId]
  }

  getSubscription(subId) {
    return this.data.subscriptions[subId] || null
  }

  markSubPaid(subId, paymentId, currentEnd) {
    const s = this.getSubscription(subId)
    if (!s) return null
    s.status = 'active'
    s.payment_id = paymentId
    if (currentEnd) s.current_end = currentEnd
    s.paid_at = new Date().toISOString()
    this.save()
    return s
  }

  setSubscriptionStatus(subId, status) {
    const s = this.getSubscription(subId)
    if (!s) return null
    s.status = status
    s.updated_at = new Date().toISOString()
    this.save()
    return s
  }

  keyForSubscription(subId) {
    for (const k in this.data.licenses) {
      if (this.data.licenses[k].subscription_id === subId) return k
    }
    return null
  }

  // ---- licenses ----
  getLicense(key) {
    return this.data.licenses[key] || null
  }

  issueLicense(key, orderId, subscriptionId) {
    this.data.licenses[key] = {
      key,
      order_id: orderId || null,
      subscription_id: subscriptionId || null,
      status: 'issued',
      machine_id: null,
      expires_at: null,
      issued_at: new Date().toISOString()
    }
    this.save()
    return this.data.licenses[key]
  }

  extendLicense(key, expiresAt) {
    const l = this.getLicense(key)
    if (!l) return null
    l.expires_at = expiresAt
    l.renewed_at = new Date().toISOString()
    if (l.status === 'expired') l.status = 'activated'
    this.save()
    return l
  }

  bindLicense(key, machineId) {
    const l = this.getLicense(key)
    if (!l) return null
    l.machine_id = machineId
    l.status = 'activated'
    l.activated_at = new Date().toISOString()
    this.save()
    return l
  }

  releaseLicense(key) {
    const l = this.getLicense(key)
    if (!l) return null
    l.machine_id = null
    l.status = 'released'
    l.released_at = new Date().toISOString()
    this.save()
    return l
  }

  all() {
    return this.data
  }
}

module.exports = Store