// server/src/test/seed_release.ts
import dotenv from 'dotenv';
dotenv.config();

import { pgPool } from '../config/database';

async function seed() {
  const query = `
    INSERT INTO app_versions (
      id, version_code, platform, download_url, sha256_hash, 
      file_path, status, channel, is_mandatory, rollout_percentage, 
      file_size_bytes, release_notes
    ) VALUES (
      'win-v1-stable', '1.0.1', 'windows', '/api/v1/updates/download/windows/latest', 
      '4E36E6D63BBB9B903C7F30DBE73FDD686B29CE1FDE199DFF54EDDA6173925587', 
      'public/website/downloads/SerenutOSSetup.exe', 
      'active', 'stable', true, 100, 9214299, 'RC1 Release Build'
    ) ON CONFLICT (id) DO UPDATE SET 
      file_path = EXCLUDED.file_path, 
      version_code = EXCLUDED.version_code,
      sha256_hash = EXCLUDED.sha256_hash,
      file_size_bytes = EXCLUDED.file_size_bytes;
  `;

  try {
    const client = await pgPool.connect();
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query(query);
    await client.query('COMMIT');
    client.release();
    console.log('✅ Successfully seeded windows release to app_versions table!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Database seeding failed:', err);
    process.exit(1);
  }
}

seed();
