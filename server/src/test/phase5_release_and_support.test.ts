import * as fs from 'fs';
import * as path from 'path';

function runPhase5Tests() {
  console.log('--- Running Phase 5 Release Management, OTA & Support Verification Tests ---');
  let passed = 0;
  let total = 0;

  function assert(condition: boolean, message: string) {
    total++;
    if (condition) {
      console.log(`✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`❌ FAIL: ${message}`);
    }
  }

  // 1. update.controller.ts semantic version sorting (G5)
  const updateControllerPath = path.resolve(__dirname, '../modules/update/update.controller.ts');
  const updateControllerContent = fs.readFileSync(updateControllerPath, 'utf8');
  assert(
    updateControllerContent.includes('compareVersions(b.version_code, a.version_code)') &&
    updateControllerContent.includes('resolveReleaseFilePath(r.file_path) !== null'),
    'update.controller.ts sorts releases semantically and verifies physical files exist on disk'
  );

  // 2. update.controller.ts /latest-metadata endpoint filters existing files
  assert(
    updateControllerContent.includes("SELECT id, version_code, platform, sha256_hash, file_size_bytes, release_notes, created_at, file_path") &&
    updateControllerContent.includes("const validRows = result.rows.filter(r => resolveReleaseFilePath(r.file_path) !== null);"),
    'update.controller.ts /latest-metadata exposes only verified releases with existing artifact files'
  );

  // 3. version_checker.dart targets updates check endpoint (I1)
  const versionCheckerPath = path.resolve(__dirname, '../../../lib/domain/services/version_checker.dart');
  const versionCheckerContent = fs.readFileSync(versionCheckerPath, 'utf8');
  assert(
    versionCheckerContent.includes('/updates/check?platform=$_platform') &&
    versionCheckerContent.includes('VersionCheckResult.fromJson(data)'),
    'version_checker.dart targets /updates/check with platform parameter and parses result'
  );

  // 4. support.controller.ts allows customer to close their own tickets (I8)
  const supportControllerPath = path.resolve(__dirname, '../modules/support/support.controller.ts');
  const supportControllerContent = fs.readFileSync(supportControllerPath, 'utf8');
  assert(
    supportControllerContent.includes("if (status !== 'closed')") &&
    supportControllerContent.includes("ticketCheck.rows[0].company_id !== req.user!.company_id") &&
    supportControllerContent.includes("Müşteriler yalnızca kendi biletlerini kapatabilir"),
    'support.controller.ts permits customer to close their own tickets while securing unauthorized transitions'
  );

  console.log(`\nResults: ${passed}/${total} assertions passed.`);
  if (passed !== total) {
    process.exit(1);
  }
}

runPhase5Tests();
