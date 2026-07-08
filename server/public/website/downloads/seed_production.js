const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});
const query = `
  -- Deactivate all other windows releases to avoid mismatch
  UPDATE app_versions 
  SET status = 'inactive' 
  WHERE platform = 'windows' AND id <> 'win-v1-stable';

  -- Upsert win-v1-stable release with fresh created_at timestamp
  INSERT INTO app_versions (
    id, version_code, platform, download_url, sha256_hash, 
    file_path, status, channel, is_mandatory, rollout_percentage, 
    file_size_bytes, release_notes, created_at
  ) VALUES (
    'win-v1-stable', '1.0.0', 'windows', '/api/v1/updates/download/windows/latest', 
    '4E36E6D63BBB9B903C7F30DBE73FDD686B29CE1FDE199DFF54EDDA6173925587', 
    'public/website/downloads/SerenutOSSetup.exe', 
    'active', 'stable', true, 100, 9214299, 'RC1 Release Build', NOW()
  ) ON CONFLICT (id) DO UPDATE SET 
    file_path = EXCLUDED.file_path, 
    version_code = EXCLUDED.version_code,
    sha256_hash = EXCLUDED.sha256_hash,
    file_size_bytes = EXCLUDED.file_size_bytes,
    status = 'active',
    created_at = NOW();
`;
console.log('🚀 Seeding live VPS database and clean-deactivating legacy MSI versions...');
pool.query(query)
  .then(() => {
    console.log('✅ Successfully seeded windows release to app_versions!');
    process.exit(0);
  })
  .catch(err => {
    console.error('❌ Seeding error:', err);
    process.exit(1);
  });
