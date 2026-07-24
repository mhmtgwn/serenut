const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const workspace = path.resolve(__dirname, '..', '..');
const secretDir = process.argv[2];
if (!secretDir) {
  throw new Error('Usage: node generate-signing-keys.js <secret-directory>');
}

const resolvedSecretDir = path.resolve(secretDir);
if (resolvedSecretDir.startsWith(workspace + path.sep)) {
  throw new Error('Private keys must be generated outside the repository.');
}

fs.mkdirSync(resolvedSecretDir, { recursive: true, mode: 0o700 });

function base64UrlToBigInt(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - normalized.length % 4) % 4);
  const hex = Buffer.from(padded, 'base64').toString('hex');
  return BigInt(`0x${hex}`).toString(10);
}

function generate(name) {
  const privatePath = path.join(resolvedSecretDir, `${name}-private.pem`);
  if (fs.existsSync(privatePath)) {
    throw new Error(`Refusing to overwrite existing key: ${privatePath}`);
  }
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 3072,
    publicExponent: 0x10001,
  });
  const privatePem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  fs.writeFileSync(privatePath, privatePem, { mode: 0o600 });
  const jwk = publicKey.export({ format: 'jwk' });
  return {
    privatePath,
    privatePem: String(privatePem),
    modulus: base64UrlToBigInt(jwk.n),
  };
}

function upsertEnv(source, name, value) {
  const escaped = value.replace(/\r?\n/g, '\\n');
  const line = `${name}="${escaped}"`;
  const expression = new RegExp(`^${name}=.*$`, 'm');
  return expression.test(source)
    ? source.replace(expression, line)
    : `${source.trimEnd()}\n${line}\n`;
}

const license = generate('license');
const release = generate('release');
const envPath = path.join(workspace, 'server', '.env');
let env = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
env = upsertEnv(env, 'RSA_PRIVATE_KEY', license.privatePem);
env = upsertEnv(env, 'RELEASE_RSA_PRIVATE_KEY', release.privatePem);
fs.writeFileSync(envPath, env, { mode: 0o600 });

const configDir = path.join(workspace, 'config');
fs.mkdirSync(configDir, { recursive: true });
fs.writeFileSync(
  path.join(configDir, 'signing_public_keys.json'),
  `${JSON.stringify({
    LICENSE_RSA_MODULUS: license.modulus,
    RELEASE_RSA_MODULUS: release.modulus,
  }, null, 2)}\n`,
);

console.log(`Signing keys generated outside the repository: ${resolvedSecretDir}`);
console.log('Server .env and public Flutter build configuration updated.');
