import assert from 'assert';
import crypto from 'crypto';
import {
  assertReleaseSigningContinuity,
  loadReleaseSigningKey,
  releaseSigningModulusSha256,
  signReleaseHash,
  verifyReleaseHashSignature,
} from '../security/release-signing';

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
});
const artifact = Buffer.from('serenut-release-signing-contract');
const hash = crypto.createHash('sha256').update(artifact).digest('hex');

const signature = signReleaseHash(hash, privateKey);
const signerFingerprint = releaseSigningModulusSha256(privateKey);
assertReleaseSigningContinuity(privateKey, {
  requiredUpgradeSignerModulusSha256: signerFingerprint,
  trustedSinceVersion: '1.0.0+1',
  rotationPhase: 'stable',
});
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

const unrelatedKeys = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
assert.throws(
  () => assertReleaseSigningContinuity(unrelatedKeys.privateKey, {
    requiredUpgradeSignerModulusSha256: signerFingerprint,
    trustedSinceVersion: '1.0.0+1',
    rotationPhase: 'stable',
  }),
  /not trusted by the supported upgrade population/,
  'A signer unknown to the supported clients must be rejected before publish.',
);

console.log('Release signing contract: PASS');
