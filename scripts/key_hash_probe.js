const crypto = require('crypto');

const raw = process.env.RSA_PRIVATE_KEY;
if (!raw) throw new Error('missing_private_key');
const privateKey = crypto.createPrivateKey({
  key: raw.startsWith('{') ? JSON.parse(raw) : raw.replace(/\\n/g, '\n'),
  format: raw.startsWith('{') ? 'jwk' : 'pem',
});
const modulusBase64Url = crypto.createPublicKey(privateKey).export({
  format: 'jwk',
}).n;
const modulusBytes = Buffer.from(
  modulusBase64Url.replace(/-/g, '+').replace(/_/g, '/'),
  'base64',
);
const modulusDecimal = BigInt(`0x${modulusBytes.toString('hex')}`).toString();
console.log(modulusDecimal);
