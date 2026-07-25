const crypto = require('crypto');
const fs = require('fs');

const env = fs.readFileSync('/var/www/serenut-api/.env.production', 'utf8');

// Try RELEASE_RSA_PRIVATE_KEY first, fallback to RSA_PRIVATE_KEY
let m = env.match(/RELEASE_RSA_PRIVATE_KEY="([^"]+)"/s);
const keyLabel = m ? 'RELEASE_RSA_PRIVATE_KEY' : 'RSA_PRIVATE_KEY';
if (!m) m = env.match(/RSA_PRIVATE_KEY="([^"]+)"/s);

if (!m) { console.error('No key found'); process.exit(1); }

const key = m[1].replace(/\\n/g, '\n');
console.log('Using key:', keyLabel);

const privKey = crypto.createPrivateKey(key);
const pubKey = crypto.createPublicKey(privKey);
const jwk = pubKey.export({ format: 'jwk' });
const nBuf = Buffer.from(jwk.n, 'base64url');
const modDec = BigInt('0x' + nBuf.toString('hex')).toString();

console.log('MODULUS_DEC=' + modDec);
console.log('MODULUS_FIRST_20=' + modDec.substring(0, 20));
