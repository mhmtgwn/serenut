const crypto = require('crypto');
const fs = require('fs');

const envText = fs.readFileSync('server/.env', 'utf8');
const match = envText.match(/RELEASE_RSA_PRIVATE_KEY="([^"]+)"/s);
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
DELETE FROM app_versions WHERE version_code IN ('1.1.9', '1.1.9+17', '1.1.9+18', '1.1.9+19', '1.1.9+20') AND channel = 'stable';

INSERT INTO app_versions (
  id, version_code, platform, channel, download_url, file_path,
  sha256_hash, signature, file_size_bytes, is_mandatory, min_required_version,
  release_notes, status, rollout_percentage, published_by
) VALUES
  ('rel-win-119-20', '1.1.9+20', 'windows', 'stable',
   '/api/v1/updates/download/windows/latest',
   '/var/www/serenut/server/public/website/downloads/SerenutOSSetup.exe',
   '${winHash}', '${winSig}', 40435256, false, '1.1.8',
   'Serenut OS v1.1.9+20 — Satış ve stok verilerinin tüm cihazlara toplu basılması ve anlık eşitlenmesi düzeltildi.',
   'active', 100, 'system'),
  ('rel-apk-119-20', '1.1.9+20', 'android', 'stable',
   '/api/v1/updates/download/android/latest',
   '/var/www/serenut/server/public/website/downloads/serenut.apk',
   '${apkHash}', '${apkSig}', 51129114, false, '1.1.8',
   'Serenut OS v1.1.9+20 — Satış ve stok verilerinin tüm cihazlara toplu basılması ve anlık eşitlenmesi düzeltildi.',
   'active', 100, 'system');

SELECT id, version_code, platform, sha256_hash, length(signature) as sig_len, status FROM app_versions WHERE version_code = '1.1.9+20';
`;

fs.writeFileSync('scripts/update_signed_release.sql', sql);
console.log('SQL generated at scripts/update_signed_release.sql');
