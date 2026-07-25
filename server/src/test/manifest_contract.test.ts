// server/src/test/manifest_contract.test.ts
import assert from 'assert';
import { validateReleaseManifestDTO } from '../modules/release_v2/models/release-manifest.dto';
import { validateBootstrapperManifestDTO } from '../modules/release_v2/models/bootstrapper-manifest.dto';
import { validateUpdateTelemetryEventDTO } from '../modules/release_v2/models/update-telemetry.dto';

console.log('🚀 Running Server-Side Manifest Contract Tests...\n');

// Test 1: Valid Release Manifest DTO
const validManifest = {
  schemaVersion: 1,
  manifestVersion: '1.0',
  releaseId: 'rel-2026.07.25.4',
  version: '1.2.0+22',
  channel: 'stable',
  publishedAt: '2026-07-25T18:20:00Z',
  buildMetadata: {
    commitHash: 'abc1234f567890',
    buildNumber: 22,
    buildDate: '2026-07-25T18:00:00Z',
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
      signature: 'MEUCIQDx7...RSA256_BASE64_SIG...'
    }
  ]
};

const v1Result = validateReleaseManifestDTO(validManifest);
assert(v1Result.valid, `Valid manifest should pass validation: ${v1Result.errors.join(', ')}`);
console.log('✅ Test 1 Passed: Valid Release Manifest DTO validation');

// Test 2: Invalid Schema Version
const invalidSchema = { ...validManifest, schemaVersion: 2 };
const v2Result = validateReleaseManifestDTO(invalidSchema);
assert(!v2Result.valid, 'Schema version != 1 should fail validation');
console.log('✅ Test 2 Passed: Invalid schemaVersion correctly rejected');

// Test 3: Invalid SHA256 Format
const invalidSha = {
  ...validManifest,
  artifacts: [
    {
      ...validManifest.artifacts[0],
      sha256: 'invalid-sha-length'
    }
  ]
};
const v3Result = validateReleaseManifestDTO(invalidSha);
assert(!v3Result.valid, 'Invalid SHA256 format should fail validation');
console.log('✅ Test 3 Passed: Invalid SHA256 format correctly rejected');

// Test 4: Valid Bootstrapper Manifest DTO
const validBootstrapper = {
  schemaVersion: 1,
  correlationId: 'upd-92a1-4f81',
  appPid: 14208,
  targetVersion: '1.2.0+22',
  installerPath: 'C:\\Users\\Temp\\installer.exe',
  targetDir: 'C:\\Users\\AppData\\SerenutOS',
  backupDir: 'C:\\Users\\AppData\\SerenutOS\\update_backups',
  postLaunchExe: 'serenutos.exe'
};
const bResult = validateBootstrapperManifestDTO(validBootstrapper);
assert(bResult.valid, 'Valid bootstrapper manifest should pass validation');
console.log('✅ Test 4 Passed: Valid Bootstrapper Manifest DTO validation');

// Test 5: Valid Telemetry DTO
const validTelemetry = {
  schemaVersion: 1,
  correlationId: 'upd-92a1-4f81',
  deviceId: 'dev-win-001',
  fromVersion: '1.1.9+21',
  toVersion: '1.2.0+22',
  eventType: 'INSTALL_SUCCESS',
  timestamp: '2026-07-25T18:22:10Z'
};
const tResult = validateUpdateTelemetryEventDTO(validTelemetry);
assert(tResult.valid, 'Valid telemetry event should pass validation');
console.log('✅ Test 5 Passed: Valid Telemetry Event DTO validation');

console.log('\n🎉 ALL SERVER MANIFEST CONTRACT TESTS PASSED SUCCESSFULY!');
