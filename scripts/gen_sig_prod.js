const crypto = require('crypto');
const fs = require('fs');

const envText = fs.readFileSync('/var/www/serenut-api/.env.production', 'utf8');

// Try RELEASE_RSA_PRIVATE_KEY first, fall back to RSA_PRIVATE_KEY
let match = envText.match(/RELEASE_RSA_PRIVATE_KEY="([^"]+)"/s);
if (!match) {
  match = envText.match(/RSA_PRIVATE_KEY="([^"]+)"/s);
}
if (!match) {
  console.error('No RSA private key found in .env.production');
  process.exit(1);
}
const key = match[1].replace(/\\n/g, '\n');

function sign(hash) {
  const s = crypto.createSign('SHA256');
  s.update(hash);
  s.end();
  return s.sign(key, 'base64');
}

const winHash = '4dd4c7b462651ee66f2529bb561a5b17417d32095220cf1908ad94362407503c';
const apkHash = '571b529ef7c5453c7f0aa6b8c2b6919e21abe4ab2d4a22c64ba6bd1c34d84841';

const winSig = sign(winHash);
const apkSig = sign(apkHash);

console.log('WIN_SIG:', winSig);
console.log('APK_SIG:', apkSig);

const sql = `
UPDATE app_versions SET signature = '${winSig}' WHERE id = 'rel-win-119-20';
UPDATE app_versions SET signature = '${apkSig}' WHERE id = 'rel-apk-119-20';
SELECT id, version_code, platform, length(signature) as sig_len FROM app_versions WHERE version_code = '1.1.9+20';
`;

fs.writeFileSync('/tmp/fix_signatures.sql', sql);
console.log('SQL written to /tmp/fix_signatures.sql');
