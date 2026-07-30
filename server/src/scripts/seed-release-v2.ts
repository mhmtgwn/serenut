// server/src/scripts/seed-release-v2.ts
import { pgPool } from '../config/database';
import crypto from 'crypto';
import { runMigrations } from '../migrations';

function canonicalizeJson(obj: any): string {
  if (obj === null || obj === undefined) return '{}';
  if (typeof obj !== 'object') return JSON.stringify(obj);
  if (Array.isArray(obj)) {
    return '[' + obj.map(canonicalizeJson).join(',') + ']';
  }
  const keys = Object.keys(obj).sort();
  const parts = keys.map(k => `${JSON.stringify(k)}:${canonicalizeJson(obj[k])}`);
  return '{' + parts.join(',') + '}';
}

async function runPublish() {
  console.log('🔄 Checking database migrations...');
  await runMigrations(pgPool);

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // 1. Resolve RSA Private key for signing
    // Generate temporary RSA key pair if not defined in env to prevent exceptions
    let privateKey = process.env.RSA_PRIVATE_KEY;

    if (!privateKey) {
      console.log('🔑 No signing key found in env. Generating temporary RSA key pair...');
      const pair = crypto.generateKeyPairSync('rsa', {
        modulusLength: 2048,
        publicKeyEncoding: { type: 'spki', format: 'pem' },
        privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
      });
      privateKey = pair.privateKey;
      console.log('Public key generated for validation: ' + pair.publicKey.substring(0, 50).replace(/\n/g, '') + '...');
    }

    const version = '1.2.1';
    const buildNum = 58;
    const releaseId = `rel-${version}-b${buildNum}`;
    const winSha256 = '78497231227069dbab0cb6a41f0acf283ec728fcb6430d321a2bee66581a108d';
    const apkSha256 = '1bef547a2294ab63a050d21231ee46eefea1ecd3ef4c9e4e8f46006f4e727971';

    // 2. Sign Artifacts
    const signWin = crypto.createSign('SHA256');
    signWin.update(winSha256);
    signWin.end();
    const winSig = signWin.sign(privateKey, 'base64');

    const signApk = crypto.createSign('SHA256');
    signApk.update(apkSha256);
    signApk.end();
    const apkSig = signApk.sign(privateKey, 'base64');

    // 3. Construct V2 Manifest
    const manifest = {
      schemaVersion: 1,
      manifestVersion: '1.0',
      releaseId,
      version: `${version}+${buildNum}`,
      channel: 'stable',
      publishedAt: new Date().toISOString(),
      buildMetadata: {
        commitHash: 'abc1234f567890',
        buildNumber: buildNum,
        buildDate: new Date().toISOString(),
        signatureAlgorithm: 'RSA-SHA256'
      },
      compatibility: {
        minClientVersion: '1.0.0+1',
        minimumUpdaterVersion: '1.0.0',
        requiredBootstrapper: '1',
        requiredPreVersion: '1.1.0+0',
        migrationRequired: false,
        targetSchemaVersion: 1
      },
      rules: {
        isMandatory: false,
        allowRollback: true,
        minFreeDiskMb: 300,
        minRamMb: 2048,
        supportedArchitectures: ['x64', 'arm64']
      },
      artifacts: [
        {
          type: 'installer_windows',
          filename: `SerenutOSSetup-${version}.exe`,
          downloadUrl: `/api/v1/updates/download/windows/latest`,
          sizeBytes: 14917025,
          sha256: winSha256,
          signature: winSig
        },
        {
          type: 'apk_android',
          filename: `serenut-${version}.apk`,
          downloadUrl: `/api/v1/updates/download/android/latest`,
          sizeBytes: 49837016,
          sha256: apkSha256,
          signature: apkSig
        }
      ]
    };

    // 4. Canonicalize & Sign Manifest
    const canonicalJson = canonicalizeJson(manifest);
    const signManifest = crypto.createSign('SHA256');
    signManifest.update(canonicalJson);
    signManifest.end();
    const manifestSignature = signManifest.sign(privateKey, 'base64');
    const manifestHash = crypto.createHash('sha256').update(canonicalJson).digest('hex');

    // Calculate artifact set hash
    const compositeHashData = [manifestHash, winSha256, apkSha256].join('|');
    const artifactSetHash = crypto.createHash('sha256').update(compositeHashData).digest('hex');

    console.log(`🚀 Seeding Release v${version}+${buildNum} (Hash: ${artifactSetHash})`);

    // 5. Delete existing to override cleanly
    await client.query('DELETE FROM releases WHERE release_id = $1', [releaseId]);

    // 6. Insert releases (V2)
    await client.query(`
      INSERT INTO releases (
        release_id, version_code, channel, current_state, manifest_sha256, manifest_signature, build_commit, build_pipeline_id, artifact_set_hash
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    `, [
      releaseId,
      `${version}+${buildNum}`,
      'stable',
      'stable', // Mark as stable so it is live immediately
      manifestHash,
      manifestSignature,
      'abc1234f567890',
      'seed-script',
      artifactSetHash
    ]);

    // 7. Insert release_artifacts
    await client.query(`
      INSERT INTO release_artifacts (
        release_id, type, filename, download_url, size_bytes, sha256, signature
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
    `, [
      releaseId,
      'installer_windows',
      `SerenutOSSetup-${version}.exe`,
      `/api/v1/updates/download/windows/latest`,
      14917025,
      winSha256,
      winSig
    ]);

    // 8. Insert release_manifest_store
    await client.query(`
      INSERT INTO release_manifest_store (
        release_id, canonical_manifest_json, manifest_sha256, manifest_signature
      ) VALUES ($1, $2, $3, $4)
    `, [
      releaseId,
      canonicalJson,
      manifestHash,
      manifestSignature
    ]);

    // 9. Insert release_promotions
    await client.query(`
      INSERT INTO release_promotions (release_id, rollout_percentage)
      VALUES ($1, 100)
    `, [releaseId]);

    // 10. Audit Chain logging
    const lastRes = await client.query('SELECT record_hash FROM release_audit ORDER BY id DESC LIMIT 1');
    const previousHash = lastRes.rows.length > 0 ? lastRes.rows[0].record_hash : '0000000000000000000000000000000000000000000000000000000000000000';
    
    const payloadStr = canonicalizeJson({ seeded: true, version });
    const dataToHash = [
      previousHash,
      releaseId,
      'system-admin',
      'PUBLISH',
      '',
      'stable',
      payloadStr
    ].join('|');
    const recordHash = crypto.createHash('sha256').update(dataToHash).digest('hex');

    await client.query(`
      INSERT INTO release_audit (
        release_id, actor_id, action, from_state, to_state, payload, previous_record_hash, record_hash
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    `, [
      releaseId,
      'system-admin',
      'PUBLISH',
      null,
      'stable',
      { seeded: true, version },
      previousHash,
      recordHash
    ]);

    // 11. Insert legacy app_versions for legacy devices & downloads page compatibility
    console.log('📌 Seeding legacy app_versions table entries...');
    
    // Windows
    const winLegacyId = `win-${version}`;
    await client.query('DELETE FROM app_versions WHERE id = $1 OR version_code = $2', [winLegacyId, `${version}+${buildNum}`]);
    await client.query(`
      INSERT INTO app_versions (
        id, version_code, platform, download_url, sha256_hash, is_mandatory, release_notes, signature, file_size_bytes, channel, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    `, [
      winLegacyId,
      `${version}+${buildNum}`,
      'windows',
      `/api/v1/updates/download/windows/latest`,
      winSha256,
      false,
      'Yeni Serenut OS 1.2.1 güncellemesi yayınlandı! Müşteri filtreleme ve yazıcı logosu/etiket tasarımı iyileştirmeleri.',
      winSig,
      14949628,
      'stable',
      'active'
    ]);

    // Android
    const apkLegacyId = `apk-${version}`;
    await client.query('DELETE FROM app_versions WHERE id = $1 OR version_code = $2', [apkLegacyId, `${version}+${buildNum}`]);
    await client.query(`
      INSERT INTO app_versions (
        id, version_code, platform, download_url, sha256_hash, is_mandatory, release_notes, signature, file_size_bytes, channel, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    `, [
      apkLegacyId,
      `${version}+${buildNum}`,
      'android',
      `/api/v1/updates/download/android/latest`,
      apkSha256,
      false,
      'Mobil cihazlar için yeni Serenut OS 1.2.1 Android APK sürümü.',
      apkSig,
      50029356,
      'stable',
      'active'
    ]);

    await client.query('COMMIT');
    console.log(`🎉 Sürüm ${version}+${buildNum} hem v2 registry hem de legacy indirme sayfaları için başarıyla yayınlandı!`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Seeding failed:', err);
  } finally {
    client.release();
    pgPool.end();
  }
}

runPublish();
