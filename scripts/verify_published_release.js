const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const SHA256_HEX = /^[a-f0-9]{64}$/;

function decimalModulusToPublicKey(modulus) {
  let hex = BigInt(modulus).toString(16);
  if (hex.length % 2) hex = `0${hex}`;
  return crypto.createPublicKey({
    key: {
      kty: 'RSA',
      n: Buffer.from(hex, 'hex').toString('base64url'),
      e: 'AQAB',
    },
    format: 'jwk',
  });
}

async function hashResponse(response) {
  if (!response.ok || !response.body) {
    throw new Error(`Artifact download failed: HTTP ${response.status}`);
  }
  const hash = crypto.createHash('sha256');
  let size = 0;
  for await (const chunk of response.body) {
    hash.update(chunk);
    size += chunk.length;
  }
  return { hash: hash.digest('hex'), size };
}

async function verifyPlatform(apiBaseUrl, expectedVersion, platform, publicKeys) {
  const checkUrl = new URL('/api/v1/updates/check', apiBaseUrl);
  checkUrl.searchParams.set('platform', platform);
  checkUrl.searchParams.set('current_version', '0.0.0+0');
  const metadataResponse = await fetch(checkUrl, { cache: 'no-store' });
  if (!metadataResponse.ok) {
    throw new Error(`${platform} metadata failed: HTTP ${metadataResponse.status}`);
  }
  const metadata = await metadataResponse.json();
  const expectedHash = String(metadata.sha256_hash || '').toLowerCase();
  const expectedSize = Number(metadata.file_size_bytes);
  if (metadata.latestVersion !== expectedVersion) {
    throw new Error(`${platform} version mismatch: ${metadata.latestVersion}`);
  }
  if (!SHA256_HEX.test(expectedHash) || !Number.isSafeInteger(expectedSize) || expectedSize <= 0) {
    throw new Error(`${platform} metadata has an invalid hash or size`);
  }
  const expectedPath = `/download/${platform}/version/${encodeURIComponent(expectedVersion)}`;
  const artifactUrl = new URL(metadata.downloadUrl);
  if (!artifactUrl.pathname.endsWith(expectedPath)) {
    throw new Error(`${platform} download URL is not immutable: ${artifactUrl.pathname}`);
  }

  const artifactResponse = await fetch(artifactUrl, { cache: 'no-store' });
  const actual = await hashResponse(artifactResponse);
  if (actual.hash !== expectedHash || actual.size !== expectedSize) {
    throw new Error(
      `${platform} published bytes mismatch: expected ${expectedHash}/${expectedSize}, ` +
      `received ${actual.hash}/${actual.size}`,
    );
  }

  const signature = Buffer.from(String(metadata.signature || ''), 'base64');
  const signatureValid = publicKeys.some(key =>
    crypto.verify('RSA-SHA256', Buffer.from(actual.hash, 'utf8'), key, signature),
  );
  if (!signatureValid) {
    throw new Error(`${platform} RSA signature does not match the published bytes`);
  }
  console.log(`${platform}: PASS (${actual.hash.slice(0, 12)}…, ${actual.size} bytes)`);
}

async function main() {
  const expectedVersion = process.argv[2];
  if (!/^\d+\.\d+\.\d+\+\d+$/.test(expectedVersion || '')) {
    throw new Error('Usage: node scripts/verify_published_release.js <version+build>');
  }
  const apiBaseUrl = process.env.RELEASE_VERIFY_BASE_URL || 'https://api.serenut.com';
  const keysPath = path.resolve(__dirname, '../config/signing_public_keys.json');
  const keyConfig = JSON.parse(fs.readFileSync(keysPath, 'utf8'));
  const publicKeys = keyConfig.RELEASE_RSA_TRUSTED_MODULI.map(decimalModulusToPublicKey);
  for (const platform of ['android', 'windows']) {
    await verifyPlatform(apiBaseUrl, expectedVersion, platform, publicKeys);
  }
  console.log(`Published release verification: PASS (${expectedVersion})`);
}

if (require.main === module) {
  main().catch(error => {
    console.error(error.message || error);
    process.exit(1);
  });
}

module.exports = { decimalModulusToPublicKey, hashResponse, verifyPlatform };
