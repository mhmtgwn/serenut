const pg = require('pg');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Read production env file directly
const envPath = path.join(__dirname, '../.env.production');
if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, 'utf8');
  envContent.split('\n').forEach(line => {
    const match = line.match(/^\s*([\w.-]+)\s*=\s*(.*)?\s*$/);
    if (match) {
      const key = match[1];
      let value = match[2] || '';
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1).replace(/\\n/g, '\n');
      }
      process.env[key] = value;
    }
  });
}

const privateKeyEnv = process.env.RSA_PRIVATE_KEY;
if (!privateKeyEnv) {
  console.error('RSA_PRIVATE_KEY is not defined in environment.');
  process.exit(1);
}

// Load private key
let privateKey;
if (privateKeyEnv.startsWith('{')) {
  privateKey = crypto.createPrivateKey({
    key: JSON.parse(privateKeyEnv),
    format: 'jwk'
  });
} else {
  const formattedKey = privateKeyEnv.replace(/\\n/g, '\n');
  privateKey = crypto.createPrivateKey({
    key: formattedKey,
    format: 'pem'
  });
}

const hash = 'A3957023C775D5879F828514DEEE0830B3BFF65416A5821513A312E4A96F1383';
const fileSize = 16316011;

// Sign payload
const signer = crypto.createSign('RSA-SHA256');
signer.update(hash);
signer.end();
const signature = signer.sign(privateKey, 'base64');

console.log('New Hash:', hash);
console.log('New Signature:', signature);
console.log('New File Size:', fileSize);

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL
});

async function main() {
  const query = `
    UPDATE app_versions 
    SET sha256_hash = $1, signature = $2, file_size_bytes = $3
    WHERE platform = 'windows' AND version_code = '1.0.1'
  `;
  await pool.query(query, [hash, signature, fileSize]);
  console.log('Successfully updated DB with new metadata!');
  await pool.end();
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
