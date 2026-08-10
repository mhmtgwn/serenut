import crypto from 'crypto';
import fs from 'fs';

const SHA256_HEX = /^[a-f0-9]{64}$/;
const VERSION_CODE = /^\d+\.\d+\.\d+\+\d+$/;

export type ReleaseSigningPolicy = {
  requiredUpgradeSignerModulusSha256: string;
  trustedSinceVersion: string;
  rotationPhase: 'bridge' | 'stable';
};

function decodeKeyMaterial(rawValue: string): string | crypto.JsonWebKey {
  const normalized = rawValue.replace(/\\r?\\n/g, '\n').trim();
  let material = normalized;

  if (/^[A-Za-z0-9+/=_-]+$/.test(normalized)) {
    const decoded = Buffer.from(normalized, 'base64').toString('utf8').trim();
    if (decoded.startsWith('-----BEGIN ') || decoded.startsWith('{')) {
      material = decoded;
    }
  }

  return material.startsWith('{')
    ? JSON.parse(material) as crypto.JsonWebKey
    : material;
}

export function loadReleaseSigningKey(
  values: Array<string | undefined>,
  keyPaths: Array<string | undefined>,
): crypto.KeyObject {
  const candidates = values.filter((value): value is string => Boolean(value));

  for (const keyPath of keyPaths.filter((value): value is string => Boolean(value))) {
    if (fs.existsSync(keyPath)) candidates.push(fs.readFileSync(keyPath, 'utf8'));
  }

  let lastError: unknown;
  for (const candidate of candidates) {
    try {
      const material = decodeKeyMaterial(candidate);
      return typeof material === 'string'
        ? crypto.createPrivateKey({ key: material, format: 'pem' })
        : crypto.createPrivateKey({ key: material, format: 'jwk' });
    } catch (error) {
      lastError = error;
    }
  }

  if (candidates.length === 0) {
    throw new Error(
      'RELEASE_RSA_PRIVATE_KEY or RELEASE_RSA_PRIVATE_KEY_FILE is required.',
    );
  }
  throw new Error(
    `Release signing key could not be decoded: ${
      lastError instanceof Error ? lastError.message : 'unknown error'
    }`,
  );
}

export function releaseSigningModulusSha256(key: crypto.KeyObject): string {
  const publicJwk = crypto.createPublicKey(key).export({ format: 'jwk' });
  if (publicJwk.kty !== 'RSA' || !publicJwk.n) {
    throw new Error('Release signing key must be RSA.');
  }
  const modulusHex = Buffer.from(publicJwk.n, 'base64url').toString('hex');
  const modulusDecimal = BigInt(`0x${modulusHex}`).toString(10);
  return crypto.createHash('sha256').update(modulusDecimal, 'utf8').digest('hex');
}

export function loadReleaseSigningPolicy(
  policyPaths: Array<string | undefined>,
): ReleaseSigningPolicy {
  const policyPath = policyPaths
    .filter((value): value is string => Boolean(value))
    .find(candidate => fs.existsSync(candidate));
  if (!policyPath) {
    throw new Error('Release signing continuity policy is missing.');
  }

  const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8')) as ReleaseSigningPolicy;
  if (!SHA256_HEX.test(policy.requiredUpgradeSignerModulusSha256 || '')) {
    throw new Error('Release signing policy has an invalid signer fingerprint.');
  }
  if (!VERSION_CODE.test(policy.trustedSinceVersion || '')) {
    throw new Error('Release signing policy has an invalid trustedSinceVersion.');
  }
  if (policy.rotationPhase !== 'bridge' && policy.rotationPhase !== 'stable') {
    throw new Error('Release signing policy has an invalid rotationPhase.');
  }
  return policy;
}

export function assertReleaseSigningContinuity(
  privateKey: crypto.KeyObject,
  policy: ReleaseSigningPolicy,
): void {
  const actualFingerprint = releaseSigningModulusSha256(privateKey);
  if (actualFingerprint !== policy.requiredUpgradeSignerModulusSha256) {
    throw new Error(
      'Release signer is not trusted by the supported upgrade population. ' +
      'Publish a bridge release with the existing signer before rotating keys.',
    );
  }
}

export function signReleaseHash(hash: string, privateKey: crypto.KeyObject): string {
  const normalizedHash = hash.trim().toLowerCase();
  if (!SHA256_HEX.test(normalizedHash)) {
    throw new Error('Release hash must be a 64-character lowercase SHA-256 value.');
  }
  return crypto.sign('RSA-SHA256', Buffer.from(normalizedHash, 'utf8'), privateKey)
    .toString('base64');
}

export function verifyReleaseHashSignature(
  hash: string,
  signature: string,
  key: crypto.KeyLike,
): boolean {
  const normalizedHash = hash.trim().toLowerCase();
  if (!SHA256_HEX.test(normalizedHash) || !signature.trim()) return false;

  try {
    return crypto.verify(
      'RSA-SHA256',
      Buffer.from(normalizedHash, 'utf8'),
      key,
      Buffer.from(signature.trim(), 'base64'),
    );
  } catch (_) {
    return false;
  }
}
