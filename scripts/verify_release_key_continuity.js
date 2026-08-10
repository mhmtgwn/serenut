const crypto = require('crypto');
const fs = require('fs');
const { execFileSync } = require('child_process');

const previousRef = process.argv[2] || 'HEAD^';
const currentKeys = JSON.parse(
  fs.readFileSync('config/signing_public_keys.json', 'utf8'),
);
const policy = JSON.parse(
  fs.readFileSync('server/release-signing-policy.json', 'utf8'),
);

function keyring(config, strict = true) {
  const arrayValues = (config.RELEASE_RSA_TRUSTED_MODULI || [])
    .map(String)
    .map(value => value.trim())
    .filter(Boolean);
  const csvValues = String(config.RELEASE_RSA_MODULI || '')
    .split(',')
    .map(value => value.trim())
    .filter(Boolean);
  if (!strict && arrayValues.length === 0 && csvValues.length === 0) {
    const legacyValue = String(config.RELEASE_RSA_MODULUS || '').trim();
    return legacyValue ? [legacyValue] : [];
  }
  if (arrayValues.length === 0 || arrayValues.join(',') !== csvValues.join(',')) {
    throw new Error(
      'RELEASE_RSA_MODULI and RELEASE_RSA_TRUSTED_MODULI must be identical.',
    );
  }
  return arrayValues;
}

function fingerprint(modulus) {
  return crypto.createHash('sha256').update(modulus, 'utf8').digest('hex');
}

const required = policy.requiredUpgradeSignerModulusSha256;
if (!/^[a-f0-9]{64}$/.test(required || '')) {
  throw new Error('Invalid required upgrade signer fingerprint in policy.');
}

const currentKeyring = keyring(currentKeys, true);
if (fingerprint(currentKeyring[0]) !== required) {
  throw new Error(
    'The client active release key does not match the required upgrade signer.',
  );
}

const previousRaw = execFileSync(
  'git',
  ['show', `${previousRef}:config/signing_public_keys.json`],
  { encoding: 'utf8' },
);
const previousKeyring = keyring(JSON.parse(previousRaw), false);
if (!previousKeyring.some(modulus => fingerprint(modulus) === required)) {
  throw new Error(
    'Release signer rotation blocked: the previous client does not trust this signer. ' +
      'First publish a bridge release signed by the old key with both keys embedded.',
  );
}

console.log(
  `Release key continuity: PASS (${required.slice(0, 12)}…, previous=${previousRef})`,
);
