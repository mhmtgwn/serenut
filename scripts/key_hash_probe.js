const crypto = require('crypto');

const variableName = process.argv[2] === 'release'
  ? 'RELEASE_RSA_PRIVATE_KEY'
  : 'RSA_PRIVATE_KEY';
const raw = process.env[variableName];
if (!raw) throw new Error('missing_private_key');
const normalized = raw.replace(/\\r?\\n/g, '\n').trim();
let material = normalized;
if (/^[A-Za-z0-9+/=_-]+$/.test(normalized)) {
  const decoded = Buffer.from(normalized, 'base64').toString('utf8').trim();
  if (decoded.startsWith('-----BEGIN ') || decoded.startsWith('{')) {
    material = decoded;
  }
}
const privateKey = material.startsWith('{')
  ? crypto.createPrivateKey({ key: JSON.parse(material), format: 'jwk' })
  : crypto.createPrivateKey({ key: material, format: 'pem' });
const modulusBase64Url = crypto.createPublicKey(privateKey).export({
  format: 'jwk',
}).n;
const modulusBytes = Buffer.from(
  modulusBase64Url.replace(/-/g, '+').replace(/_/g, '/'),
  'base64',
);
const modulusDecimal = BigInt(`0x${modulusBytes.toString('hex')}`).toString();
console.log(modulusDecimal);
