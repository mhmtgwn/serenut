const crypto = require('crypto');

// Read RSA key from environment variable (injected by Docker)
let keyRaw = process.env.RSA_PRIVATE_KEY || process.env.RELEASE_RSA_PRIVATE_KEY;
if (!keyRaw) { console.error('No RSA key found in env'); process.exit(1); }

// Docker env vars preserve actual newlines
const key = keyRaw.includes('\\n') ? keyRaw.replace(/\\n/g, '\n') : keyRaw;

const privKey = crypto.createPrivateKey(key);
const pubKey = crypto.createPublicKey(privKey);
const jwk = pubKey.export({ format: 'jwk' });
const nBuf = Buffer.from(jwk.n, 'base64url');
const modDec = BigInt('0x' + nBuf.toString('hex')).toString();

console.log('KEY_LABEL=RSA_PRIVATE_KEY');
console.log('MODULUS_DEC=' + modDec);
