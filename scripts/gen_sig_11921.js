const crypto = require('crypto');
const fs = require('fs');

let key = process.env.RELEASE_RSA_PRIVATE_KEY || process.env.RSA_PRIVATE_KEY;
if (!key) {
  for (const p of ['/var/www/serenut/server/.env.production', 'server/.env.production', '.env.production', 'server/.env', '.env']) {
    if (fs.existsSync(p)) {
      const text = fs.readFileSync(p, 'utf8');
      const m = text.match(/RELEASE_RSA_PRIVATE_KEY="([^"]+)"/s) || text.match(/RSA_PRIVATE_KEY="([^"]+)"/s);
      if (m) { key = m[1]; break; }
    }
  }
}

if (!key) {
  console.error('RSA private key not found');
  process.exit(1);
}

key = key.replace(/\\n/g, '\n');

function sign(hash) {
  const s = crypto.createSign('SHA256');
  s.update(hash);
  s.end();
  return s.sign(key, 'base64');
}

const apkHash = '8c3a46c6e456f0d8b1e217ae61d7a4c4c6d892ca5407135ce87aa2d184a52953';
const winHash = '1cbf1356c9d86e1254c6ab50df9fded1e68db3c3211ac65b1c3deffebb166a24';

const apkSig = sign(apkHash);
const winSig = sign(winHash);

console.log('APK & WIN Signatures generated successfully for 1.1.9+21');

const sql = `
INSERT INTO app_versions (
  id, version_code, platform, channel, download_url, file_path,
  sha256_hash, signature, file_size_bytes, is_mandatory, min_required_version,
  release_notes, status, rollout_percentage, published_by
) VALUES
(
  'rel-apk-119-21', '1.1.9+21', 'android', 'stable',
  '/api/v1/updates/download/android/latest',
  '/var/www/serenut/server/public/website/downloads/serenut.apk',
  '${apkHash}', '${apkSig}', 51133388, false, '1.1.8',
  'Serenut OS v1.1.9+21 — Veri eşitleme (ürün, müşteri, satış) veri dönüşüm çökmesi düzeltildi.',
  'active', 100, 'system'
),
(
  'rel-win-119-21', '1.1.9+21', 'windows', 'stable',
  '/api/v1/updates/download/windows/latest',
  '/var/www/serenut/server/public/website/downloads/SerenutOSSetup.exe',
  '${winHash}', '${winSig}', 16363446, false, '1.1.8',
  'Serenut OS v1.1.9+21 — Veri eşitleme (ürün, müşteri, satış) veri dönüşüm çökmesi düzeltildi.',
  'active', 100, 'system'
)
ON CONFLICT (id) DO UPDATE SET
  version_code = EXCLUDED.version_code,
  sha256_hash = EXCLUDED.sha256_hash,
  signature = EXCLUDED.signature,
  file_size_bytes = EXCLUDED.file_size_bytes,
  release_notes = EXCLUDED.release_notes,
  is_mandatory = false,
  updated_at = CURRENT_TIMESTAMP;

SELECT id, version_code, platform, sha256_hash, length(signature) as sig_len, status FROM app_versions WHERE version_code = '1.1.9+21';
`;

fs.writeFileSync('/tmp/update_11921.sql', sql);
console.log('SQL written to /tmp/update_11921.sql');
