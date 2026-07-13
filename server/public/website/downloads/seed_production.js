const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

function getFileInfo(relativePath) {
  const resolved = path.resolve(process.cwd(), relativePath);
  if (!fs.existsSync(resolved)) {
    console.warn(`⚠️ Warning: Release file not found at ${resolved}. Using fallback metadata.`);
    if (relativePath.includes('SerenutOSSetup.exe')) {
      return {
        size: 14009885,
        hash: '94DACCA2B0C5605F960C6DE74D8B23A8B44D59AEAB79DC9A3C91EA3A19859B9D'
      };
    } else if (relativePath.includes('serenut.apk')) {
      return {
        size: 142629988,
        hash: '36DA4BD533E1973B9A3A1ECFC1A59EE8F1D9B54F629857ADE78FBAC99D172C9B'
      };
    }
    return {
      size: 0,
      hash: '0000000000000000000000000000000000000000000000000000000000000000'
    };
  }
  const stats = fs.statSync(resolved);
  const size = stats.size;
  
  const content = fs.readFileSync(resolved);
  const hash = crypto.createHash('sha256').update(content).digest('hex').toUpperCase();
  return { size, hash };
}

async function main() {
  console.log('🚀 Computing dynamic file size and SHA-256 hashes for releases...');
  
  let winInfo, androidInfo;
  try {
    winInfo = getFileInfo('public/website/downloads/SerenutOSSetup.exe');
    androidInfo = getFileInfo('public/website/downloads/serenut.apk');
    console.log(`🖥️ Windows: Size=${winInfo.size} bytes, Hash=${winInfo.hash}`);
    console.log(`📱 Android: Size=${androidInfo.size} bytes, Hash=${androidInfo.hash}`);
  } catch (err) {
    console.error('❌ Failed to read release files:', err.message);
    process.exit(1);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    console.log('🚀 Deactivating legacy app versions...');
    await client.query(`
      UPDATE app_versions 
      SET status = 'inactive' 
      WHERE (platform = 'windows' AND id <> 'win-v1-stable')
         OR (platform = 'android' AND id <> 'android-v1-stable');
    `);

    console.log('🚀 Upserting Windows stable release...');
    await client.query(`
      INSERT INTO app_versions (
        id, version_code, platform, download_url, sha256_hash, 
        file_path, status, channel, is_mandatory, rollout_percentage, 
        file_size_bytes, release_notes, created_at
      ) VALUES (
        'win-v1-stable', '1.0.0', 'windows', '/api/v1/updates/download/windows/latest', 
        $1, 'public/website/downloads/SerenutOSSetup.exe', 
        'active', 'stable', true, 100, $2, 'RC1 Release Build — Inno Setup Installer', NOW()
      ) ON CONFLICT (id) DO UPDATE SET 
        file_path = EXCLUDED.file_path, 
        version_code = EXCLUDED.version_code,
        sha256_hash = EXCLUDED.sha256_hash,
        file_size_bytes = EXCLUDED.file_size_bytes,
        status = 'active',
        created_at = NOW();
    `, [winInfo.hash, winInfo.size]);

    console.log('🚀 Upserting Android stable release...');
    await client.query(`
      INSERT INTO app_versions (
        id, version_code, platform, download_url, sha256_hash, 
        file_path, status, channel, is_mandatory, rollout_percentage, 
        file_size_bytes, release_notes, created_at
      ) VALUES (
        'android-v1-stable', '1.0.0', 'android', '/api/v1/updates/download/android/latest', 
        $1, 'public/website/downloads/serenut.apk', 
        'active', 'stable', true, 100, $2, 'RC1 Release Build — Android Application Package', NOW()
      ) ON CONFLICT (id) DO UPDATE SET 
        file_path = EXCLUDED.file_path, 
        version_code = EXCLUDED.version_code,
        sha256_hash = EXCLUDED.sha256_hash,
        file_size_bytes = EXCLUDED.file_size_bytes,
        status = 'active',
        created_at = NOW();
    `, [androidInfo.hash, androidInfo.size]);

    await client.query('COMMIT');
    console.log('✅ Successfully seeded windows and android releases to app_versions!');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Seeding database failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

main();
