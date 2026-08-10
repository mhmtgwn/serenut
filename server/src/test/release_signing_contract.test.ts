import assert from 'assert';
import crypto from 'crypto';
import {
  loadReleaseSigningKey,
  signReleaseHash,
  verifyReleaseHashSignature,
} from '../security/release-signing';

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
});
const artifact = Buffer.from('serenut-release-signing-contract');
const hash = crypto.createHash('sha256').update(artifact).digest('hex');

const signature = signReleaseHash(hash, privateKey);
assert(
  verifyReleaseHashSignature(hash, signature, publicKey),
  'The canonical signature over the lowercase SHA-256 text must verify.',
);

const wrongPayloadSignature = crypto.sign('RSA-SHA256', artifact, privateKey)
  .toString('base64');
assert(
  !verifyReleaseHashSignature(hash, wrongPayloadSignature, publicKey),
  'A signature over raw artifact bytes must not satisfy the hash-text contract.',
);

const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
const loadedFromBase64 = loadReleaseSigningKey(
  [Buffer.from(pem, 'utf8').toString('base64')],
  [],
);
const base64SecretSignature = signReleaseHash(hash, loadedFromBase64);
assert(
  verifyReleaseHashSignature(hash, base64SecretSignature, publicKey),
  'Base64-encoded PEM secrets must load without changing the signing key.',
);

assert.throws(
  () => signReleaseHash('not-a-sha256', privateKey),
  /64-character lowercase SHA-256/,
);

console.log('Release signing contract: PASS');
