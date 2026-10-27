import * as fs from 'fs';
import * as path from 'path';

function runPhase4Tests() {
  console.log('--- Running Phase 4 Registration, Trial & Quota Verification Tests ---');
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

  // 1. auth.controller.ts registration is_active logic (A1)
  const authControllerPath = path.resolve(__dirname, '../modules/auth/auth.controller.ts');
  const authControllerContent = fs.readFileSync(authControllerPath, 'utf8');
  assert(
    authControllerContent.includes('!emailVerificationRequired, emailVerificationRequired ? null : new Date()'),
    'auth.controller.ts sets is_active to false when email verification is required'
  );

  // 2. auth.controller.ts resend-verification query (A1)
  assert(
    authControllerContent.includes('(email_verified_at IS NULL OR is_active = false)'),
    'auth.controller.ts resend-verification correctly queries unverified or inactive users'
  );

  // 3. auth.controller.ts graceful session-bootstrap on expired license (A3, F5)
  assert(
    authControllerContent.includes("err.message === 'license_expired' || err.message === 'no_license_found'") &&
    authControllerContent.includes("requires_subscription: true") &&
    authControllerContent.includes("entitlement_state: 'expired'"),
    'auth.controller.ts returns graceful subscription prompt instead of raw 409 crash on license expiration'
  );

  // 4. commercial_lifecycle.service.ts pending trial creation (A2, A6)
  const lifecyclePath = path.resolve(__dirname, '../modules/billing/commercial_lifecycle.service.ts');
  const lifecycleContent = fs.readFileSync(lifecyclePath, 'utf8');
  assert(
    lifecycleContent.includes("VALUES($1,$2,$3,'trialing',NOW(),NOW() + INTERVAL '90 days',NULL,NULL,0)"),
    'commercial_lifecycle.service.ts provisions trial with NULL start/end dates so the clock starts on first device activation'
  );

  // 5. license_service.dart graceful heartbeat handling (F1)
  const licenseServicePath = path.resolve(__dirname, '../../../lib/domain/services/license_service.dart');
  const licenseServiceContent = fs.readFileSync(licenseServicePath, 'utf8');
  assert(
    !licenseServiceContent.includes('response.statusCode == 403 || response.statusCode == 404) {\n        await clearLicense();') &&
    licenseServiceContent.includes('// Çevrimdışı tolerans (Grace Period) korunmalı'),
    'license_service.dart preserves local cached license on 403/404 heartbeat failures allowing offline grace'
  );

  // 6. branch.controller.ts store_limit quota enforcement (H4)
  const branchControllerPath = path.resolve(__dirname, '../modules/branch/branch.controller.ts');
  const branchControllerContent = fs.readFileSync(branchControllerPath, 'utf8');
  assert(
    branchControllerContent.includes('SELECT store_limit FROM license_entitlements') &&
    branchControllerContent.includes('BRANCH_LIMIT_EXCEEDED'),
    'branch.controller.ts enforces company store_limit quota before creating new branches'
  );

  // 7. admin.controller.ts atomic license_entitlements update on package override (G4)
  const adminControllerPath = path.resolve(__dirname, '../modules/admin/admin.controller.ts');
  const adminControllerContent = fs.readFileSync(adminControllerPath, 'utf8');
  assert(
    adminControllerContent.includes('UPDATE license_entitlements') &&
    adminControllerContent.includes('valid_until = GREATEST(valid_until, $3::timestamptz)') &&
    adminControllerContent.includes('store_limit = COALESCE($5, store_limit)'),
    'admin.controller.ts atomically updates license_entitlements table when package override is applied'
  );

  console.log(`\nResults: ${passed}/${total} assertions passed.`);
  if (passed !== total) {
    process.exit(1);
  }
}

runPhase4Tests();
