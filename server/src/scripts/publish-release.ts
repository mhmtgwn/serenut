import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { pgPool } from '../config/database';

async function sha256(filePath: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('data', chunk => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

async function main() {
  const [platform, versionCode, incomingPath] = process.argv.slice(2);
  if (!['android', 'windows'].includes(platform) || !versionCode || !incomingPath) {
    throw new Error('Usage: publish-release <android|windows> <version> <file>');
  }

  const privateKey = process.env.RSA_PRIVATE_KEY;
  if (!privateKey) throw new Error('RSA_PRIVATE_KEY is required');
  if (!fs.existsSync(incomingPath)) throw new Error(`Release file not found: ${incomingPath}`);

  const ext = path.extname(incomingPath).toLowerCase();
  const expectedExt = platform === 'android' ? '.apk' : '.exe';
  if (ext !== expectedExt) throw new Error(`Expected ${expectedExt}, received ${ext}`);

  const releaseDir = path.join(process.env.RELEASES_DIR || '/var/www/serenut-api/releases', platform, 'stable');
  fs.mkdirSync(releaseDir, { recursive: true });
  const finalPath = path.join(releaseDir, `SerenutOS-${versionCode}${ext}`);
  fs.copyFileSync(incomingPath, finalPath);

  const hash = await sha256(finalPath);
  const signer = crypto.createSign('SHA256');
  signer.update(hash);
  signer.end();
  const signature = signer.sign(privateKey, 'base64');
  const size = fs.statSync(finalPath).size;
  const id = `rel-${platform}-${versionCode.replace(/[^a-zA-Z0-9]/g, '-')}`;
  const notes = 'Serenut OS 1.0.2: hesaplama, sipariş düzenleme/iptal, senkronizasyon, hesap ve lisans akışı iyileştirmeleri.';

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query(`
      INSERT INTO app_versions (
        id, version_code, platform, channel, download_url, file_path,
        sha256_hash, signature, digital_signature, file_size_bytes,
        is_mandatory, min_required_version, release_notes, status,
        rollout_percentage, created_at, updated_at
      ) VALUES ($1, $2, $3, 'stable', $4, $5, $6, $7, $7, $8,
                false, NULL, $9, 'active', 100, NOW(), NOW())
      ON CONFLICT (version_code, platform, channel) DO UPDATE SET
        download_url = EXCLUDED.download_url,
        file_path = EXCLUDED.file_path,
        sha256_hash = EXCLUDED.sha256_hash,
        signature = EXCLUDED.signature,
        digital_signature = EXCLUDED.digital_signature,
        file_size_bytes = EXCLUDED.file_size_bytes,
        release_notes = EXCLUDED.release_notes,
        status = 'active', rollout_percentage = 100, updated_at = NOW()
    `, [
      id, versionCode, platform,
      `/api/v1/updates/download/${platform}/latest`, finalPath,
      hash, signature, size, notes
    ]);
    await client.query('COMMIT');
    console.log(JSON.stringify({ platform, versionCode, finalPath, sha256: hash, size }));
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pgPool.end();
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
