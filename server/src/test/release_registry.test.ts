// server/src/test/release_registry.test.ts
import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { ReleaseRegistryService } from '../modules/release_v2/services/release-registry.service';
import { ReleaseFsmService } from '../modules/release_v2/services/release-fsm.service';
import { ReleaseAuditService } from '../modules/release_v2/services/release-audit.service';
import { ReleaseManifestDTO } from '../modules/release_v2/models/release-manifest.dto';
import assert from 'assert';
import crypto from 'crypto';

async function setup() {
  console.log('🔄 Setting up database for Release Registry V2 Test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  // Run all migrations including our new schema_v51.sql
  await runMigrations(pgPool);
}

async function runTests() {
  await setup();

  const registryService = new ReleaseRegistryService(pgPool);
  const fsmService = new ReleaseFsmService(pgPool);
  const auditService = new ReleaseAuditService(pgPool);
  const keys = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  process.env.RELEASE_SIGNING_PUBLIC_KEY = keys.publicKey.export({ type: 'spki', format: 'pem' }).toString();

  const testManifest: ReleaseManifestDTO = {
    schemaVersion: 1,
    manifestVersion: '1.0',
    releaseId: 'rel-1.2.0-test',
    version: '1.2.0+22',
    channel: 'stable',
    publishedAt: new Date().toISOString(),
    buildMetadata: {
      commitHash: 'abc1234f567890',
      buildNumber: 22,
      buildDate: new Date().toISOString(),
      signatureAlgorithm: 'RSA-SHA256'
    },
    compatibility: {
      minClientVersion: '1.0.0+1',
      minimumUpdaterVersion: '1.0.0',
      requiredBootstrapper: '1',
      requiredPreVersion: '1.1.0+0',
      migrationRequired: true,
      targetSchemaVersion: 4
    },
    rules: {
      isMandatory: false,
      allowRollback: true,
      minFreeDiskMb: 300,
      minRamMb: 2048,
      supportedArchitectures: ['x64']
    },
    artifacts: [
      {
        type: 'installer_windows',
        filename: 'SerenutOSSetup-1.2.0.exe',
        downloadUrl: '/api/v1/releases/artifacts/SerenutOSSetup-1.2.0.exe',
        sizeBytes: 48120890,
        sha256: '4dd4c7b462651ee66f2529bb561a5b17417d32095220cf1908ad94362407503c',
        signature: ''
      }
    ]
  };

  testManifest.artifacts[0].signature = crypto.sign(
    'RSA-SHA256',
    Buffer.from(testManifest.artifacts[0].sha256.toLowerCase(), 'utf8'),
    keys.privateKey,
  ).toString('base64');
  const canonicalManifestJson = JSON.stringify(testManifest);
  const manifestSig = crypto.sign(
    'RSA-SHA256', Buffer.from(canonicalManifestJson, 'utf8'), keys.privateKey,
  ).toString('base64');

  console.log('\n======================================================');
  console.log('🧪 ENTERPRISE RELEASE MANAGEMENT — INTEGRATION TESTS');
  console.log('======================================================\n');

  // --------------------------------------------------------------------------
  // TEST 1: Atomic Publish & ADR-011 Artifact Set Hash Check
  // --------------------------------------------------------------------------
  console.log('🔹 Test 1: Atomic Publish & ADR-011 Hash Check...');
  const pubResult = await registryService.publishRelease(
    testManifest,
    canonicalManifestJson,
    manifestSig,
    'abc1234f567890',
    'pipeline-88',
    'admin-user-01'
  );

  assert(pubResult.success, `Publish failed: ${pubResult.error}`);
  assert(pubResult.artifactSetHash.length === 64, 'Artifact set hash must be a 64-char hex string');
  console.log(`✅ Test 1 Passed! Artifact Set Hash: ${pubResult.artifactSetHash}`);

  // --------------------------------------------------------------------------
  // TEST 2: Verify Initial FSM State & DB Registry Record
  // --------------------------------------------------------------------------
  console.log('🔹 Test 2: Verify Initial State & Registry...');
  const dbRes = await pgPool.query('SELECT * FROM releases WHERE release_id = $1', [testManifest.releaseId]);
  assert(dbRes.rows.length === 1, 'Release record not found in DB');
  assert(dbRes.rows[0].current_state === 'draft', 'Initial state must be "draft"');
  assert(dbRes.rows[0].artifact_set_hash === pubResult.artifactSetHash, 'Artifact set hash mismatch');
  console.log('✅ Test 2 Passed!');

  // --------------------------------------------------------------------------
  // TEST 3: Attempt Illegal Transitions
  // --------------------------------------------------------------------------
  console.log('🔹 Test 3: Illegal FSM Transition Protection...');
  // Draft -> stable directly is prohibited by transition guards
  const badTransition = await fsmService.transition(testManifest.releaseId, 'stable', 'admin-user-01');
  assert(!badTransition.success, 'FSM allowed direct Draft -> stable transition!');
  assert(badTransition.error?.includes('Illegal state transition'), 'Wrong error message on invalid transition');
  console.log('✅ Test 3 Passed! Transition guard successfully blocked invalid state change.');

  // --------------------------------------------------------------------------
  // TEST 4: Execute Valid FSM Transition Sequence
  // --------------------------------------------------------------------------
  console.log('🔹 Test 4: Valid FSM Transition Sequence (Draft -> Built -> Signed)...');
  // Draft -> Built (Allowed)
  const step1 = await fsmService.transition(testManifest.releaseId, 'built', 'admin-user-01');
  assert(step1.success, `Draft -> Built failed: ${step1.error}`);

  // Built -> Signed (Requires Signature, which is set in releases)
  const step2 = await fsmService.transition(testManifest.releaseId, 'signed', 'admin-user-01');
  assert(step2.success, `Built -> Signed failed: ${step2.error}`);

  const checkState = await pgPool.query('SELECT current_state FROM releases WHERE release_id = $1', [testManifest.releaseId]);
  assert(checkState.rows[0].current_state === 'signed', 'Release should be in "signed" state');
  console.log('✅ Test 4 Passed! Transition sequence executed successfully.');

  // --------------------------------------------------------------------------
  // TEST 5: Canary Health Guard Test
  // --------------------------------------------------------------------------
  console.log('🔹 Test 5: Canary Health Guard Verification...');
  // Signed -> Verified -> Candidate -> Canary
  await fsmService.transition(testManifest.releaseId, 'verified', 'admin-user-01');
  await fsmService.transition(testManifest.releaseId, 'candidate', 'admin-user-01');
  await fsmService.transition(testManifest.releaseId, 'canary', 'admin-user-01');

  // Attempt Canary -> Stable (Requires Health Snapshot score >= 0.95)
  const prematureStable = await fsmService.transition(testManifest.releaseId, 'stable', 'admin-user-01');
  assert(!prematureStable.success, 'Canary -> Stable allowed without health score!');

  // Insert low health snapshot (0.90)
  await pgPool.query(`
    INSERT INTO release_health_snapshots (release_id, rollout_percent, devices, success_rate, rollback_rate, crash_rate, health_score)
    VALUES ($1, 10, 100, 90.00, 2.00, 3.00, 0.90)
  `, [testManifest.releaseId]);

  const lowHealthStable = await fsmService.transition(testManifest.releaseId, 'stable', 'admin-user-01');
  assert(!lowHealthStable.success, 'Canary -> Stable allowed with low health score (0.90)!');

  // Insert high health snapshot (0.98)
  await pgPool.query(`
    INSERT INTO release_health_snapshots (release_id, rollout_percent, devices, success_rate, rollback_rate, crash_rate, health_score)
    VALUES ($1, 10, 150, 98.50, 0.50, 0.20, 0.98)
  `, [testManifest.releaseId]);

  const healthyStable = await fsmService.transition(testManifest.releaseId, 'stable', 'admin-user-01');
  assert(healthyStable.success, `Canary -> Stable failed with high health score (0.98): ${healthyStable.error}`);
  console.log('✅ Test 5 Passed! Canary health verification guard functioning perfectly.');

  // --------------------------------------------------------------------------
  // TEST 6: Immutable Cryptographic Hash-Chain Audit Log
  // --------------------------------------------------------------------------
  console.log('🔹 Test 6: Audit Chain Integrity & Tamper-Evidence...');
  // Verify entire audit chain initially
  const initialVerify = await auditService.verifyAuditChain();
  assert(initialVerify.valid, 'Initial audit chain integrity verification failed!');

  // Fetch count of audit records
  const auditCount = await pgPool.query('SELECT COUNT(*) FROM release_audit');
  assert(parseInt(auditCount.rows[0].count, 10) > 0, 'Audit records must exist');

  // Tamper with a record by modifying its action string directly in DB
  console.log('   [Simulating Tampering] Modifying action column in DB...');
  await pgPool.query("UPDATE release_audit SET action = 'YANKED' WHERE action = 'PUBLISH'");

  const postTamperVerify = await auditService.verifyAuditChain();
  assert(!postTamperVerify.valid, 'Audit chain validator failed to detect database record manipulation!');
  console.log(`✅ Test 6 Passed! Compromise successfully detected at ID: ${postTamperVerify.compromisedId}`);

  console.log('\n🎉 ALL SPRINT 2B DATABASE & SERVICE INTEGRATION TESTS PASSED!');
}

runTests()
  .then(() => {
    pgPool.end();
    process.exit(0);
  })
  .catch(err => {
    console.error('❌ Integration tests failed:', err);
    pgPool.end();
    process.exit(1);
  });
