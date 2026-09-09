#!/usr/bin/env node
// Seller CLI for the Kastrava license server.
//   node server/admin.js list [baseUrl] [token]
//   node server/admin.js release <KEY> [baseUrl] [token]
//   node server/admin.js paid <ORDER_ID> [paymentId] [baseUrl] [token]
// baseUrl/token default from server/.env (ADMIN_TOKEN) and KAS_HOST.
require('./lib/env').loadEnv()

const BASE = process.env.KAS_HOST || 'http://127.0.0.1:8787'
const TOKEN = process.env.ADMIN_TOKEN || ''

async function call(method, pathname, body) {
  const res = await fetch(BASE + pathname, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(TOKEN ? { 'X-Admin-Token': TOKEN } : {})
    },
    body: body ? JSON.stringify(body) : undefined
  })
  const out = await res.json().catch(() => ({}))
  console.log(JSON.stringify(out, null, 2))
}

async function main() {
  const [cmd, a, b] = process.argv.slice(2)
  if (cmd === 'list') return call('GET', '/api/admin/list')
  if (cmd === 'release') {
    if (!a) return console.error('usage: admin.js release <KEY>')
    return call('POST', '/api/admin/release', { key: a })
  }
  if (cmd === 'paid') {
    if (!a) return console.error('usage: admin.js paid <ORDER_ID> [paymentId]')
    return call('POST', '/api/admin/markpaid', { order_id: a, payment_id: b || 'admin' })
  }
  console.error('commands: list | release <KEY> | paid <ORDER_ID> [paymentId]')
  process.exit(1)
}

main().catch((e) => { console.error(e); process.exit(1) })