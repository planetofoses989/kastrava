// Tiny JSON-backed store for orders + licenses. Used by the dev server and
// local installs alike; swap for SQLite when volume grows.
const fs = require('fs')
const path = require('path')

class Store {
  constructor(file) {
    this.file = file
    this.data = { orders: {}, licenses: {} }
    this.load()
  }

  load() {
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'))
      this.data.orders = raw.orders || {}
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

  // ---- licenses ----
  getLicense(key) {
    return this.data.licenses[key] || null
  }

  issueLicense(key, orderId) {
    this.data.licenses[key] = {
      key,
      order_id: orderId,
      status: 'issued',
      machine_id: null,
      issued_at: new Date().toISOString()
    }
    this.save()
    return this.data.licenses[key]
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