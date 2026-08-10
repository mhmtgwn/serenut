import crypto from 'crypto';
import fs from 'fs';

const SHA256_HEX = /^[a-f0-9]{64}$/;

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
