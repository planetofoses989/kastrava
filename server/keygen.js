#!/usr/bin/env node
// Generates (or re-embeds) the Ed25519 keypair the app verifies licenses with.
// Run once: `npm run license:keygen`. Writes server/secrets/*.pem (gitignored)
// and src/kastraPublic.js (committed — this is the public half the app embeds).
require('./lib/env').loadEnv()
const sign = require('./lib/sign')
const fs = require('fs')

const file = sign.embedPublicKey()
const priv = fs.existsSync(sign.PRIVATE_FILE)
console.log('embedded public key  ->', file)
console.log('server private key   ->', sign.PRIVATE_FILE, priv ? '(exists — keep safe, never commit)' : '(missing!)')
console.log('server public key    ->', sign.PUBLIC_FILE)