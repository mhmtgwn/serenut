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

const baselineRef = String(policy.compatibilityBaselineRef || '').trim();
if (!/^[a-f0-9]{40}$/.test(baselineRef)) {
  throw new Error('Invalid compatibilityBaselineRef in release signing policy.');
}
const baselineRaw = execFileSync(
  'git',
  ['show', `${baselineRef}:config/signing_public_keys.json`],
  { encoding: 'utf8' },
);
const baselineKeyring = keyring(JSON.parse(baselineRaw), false);
if (!baselineKeyring.some(modulus => fingerprint(modulus) === required)) {
  throw new Error(
    `Minimum directly supported client ${policy.trustedSinceVersion} does not trust ` +
      'the active release signer. Publish a bridge release; direct rollout is blocked.',
  );
}

const androidCert = String(policy.androidPackageCertificateSha256 || '');
if (!/^[a-f0-9]{64}$/.test(androidCert)) {
  throw new Error('Invalid Android package certificate fingerprint in policy.');
}
const legacySigner = String(policy.legacyUpgradeSignerModulusSha256 || '');
if (!/^[a-f0-9]{64}$/.test(legacySigner)) {
  throw new Error('Invalid legacy upgrade signer fingerprint in policy.');
}
if (legacySigner === required) {
  throw new Error('Legacy and active signer fingerprints must describe distinct keys.');
}

console.log(
  `Release key continuity: PASS (${required.slice(0, 12)}…, previous=${previousRef}, ` +
    `baseline=${policy.trustedSinceVersion})`,
);
