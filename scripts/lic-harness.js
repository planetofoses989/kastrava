// Dev harness: exercises src/license.js against the running license server
// without launching Electron. Usage: node scripts/lic-harness.js [KEY]
const Module = require('module')
const orig = Module._load
Module._load = function (request, ...args) {
  if (request === 'electron') {
    return { app: { getPath: () => '/tmp/opencode/lic-userdata' }, net: {} }
  }
  return orig.apply(this, arguments)
}
globalThis.__KAS_API__ = 'http://127.0.0.1:8787'
process.on('unhandledRejection', (e) => console.error('UNHANDLED', e && e.stack || e))

const lic = require('/home/tejas/Projects/antersurf/src/license.js')

;(async () => {
  const KEY = process.argv[2]
  console.log('machine:', lic.machineCode())
  console.log('before:', JSON.stringify(lic.status()))
  if (!KEY) return
  const r = await lic.activate(KEY)
  console.log('activate:', JSON.stringify(r))
  console.log('after:', JSON.stringify(lic.status()))
})().catch((e) => { console.error('ERR', e && e.stack || e) })