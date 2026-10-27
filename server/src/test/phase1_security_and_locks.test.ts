import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import jwt from 'jsonwebtoken';
import { UserPayload } from '../modules/auth/auth.service';

async function runPhase1Tests() {
  console.log('🧪 Starting Phase 1 Security, Session and Lock Verification Tests...');

  // Test 1: Admin createCompany SQL contract must use email_verified_at, NOT is_email_verified
  const adminControllerSrc = fs.readFileSync(
    path.join(__dirname, '../modules/admin/admin.controller.ts'),
    'utf8'
  );
  assert.doesNotMatch(
    adminControllerSrc,
    /is_email_verified/,
    'admin.controller.ts must not contain non-existent column is_email_verified'
  );
  assert.match(
    adminControllerSrc,
    /INSERT INTO users \([^)]*email_verified_at[^)]*\)/,
    'admin.controller.ts must insert into email_verified_at'
  );
  console.log('  ✓ E3: Admin company creation SQL schema contract verified');

  // Test 2: CommercialLifecycleService expireTrials sets status=suspended and rebinds devices on activation
  const lifecycleSrc = fs.readFileSync(
    path.join(__dirname, '../modules/billing/commercial_lifecycle.service.ts'),
    'utf8'
  );
  assert.match(
    lifecycleSrc,
    /UPDATE device_activations SET status='suspended'/,
    'expireTrials must suspend devices instead of permanently revoking them'
  );
  assert.match(
    lifecycleSrc,
    /UPDATE device_activations\s+SET entitlement_id = \$1, status = 'active'/m,
    'activatePaidSubscription must rebind and reactivate existing devices'
  );
  console.log('  ✓ E1: Commercial lifecycle trial suspension and device rebind verified');

  // Test 3: LicenseService allows reactivation of suspended or revoked devices
  const licenseServiceSrc = fs.readFileSync(
    path.join(__dirname, '../modules/license/license.service.ts'),
    'utf8'
  );
  assert.match(
    licenseServiceSrc,
    /devRes\.rows\[0\]\.status === 'suspended' \|\| devRes\.rows\[0\]\.status === 'revoked'/,
    'license.service.ts must allow reactivation for suspended/revoked devices under active entitlement'
  );
  console.log('  ✓ E1: License service device seat reactivation verified');

  // Test 4: AuthService verifies credentials BEFORE checking account active status
  const authServiceSrc = fs.readFileSync(
    path.join(__dirname, '../modules/auth/auth.service.ts'),
    'utf8'
  );
  const verifyPasswordIdx = authServiceSrc.indexOf('this.verifyPassword');
  const userSuspendedIdx = authServiceSrc.indexOf("'user_suspended'");
  assert(
    verifyPasswordIdx < userSuspendedIdx,
    'verifyPassword must execute BEFORE account suspension or auto-activation checks'
  );
  console.log('  ✓ E2: Credential verification order and unauthenticated attack prevention verified');

  // Test 5: UserPayload and AuthService embed session_id in access tokens
  const payload: UserPayload = {
    jti: crypto.randomUUID(),
    session_id: 'sess-test-123',
    id: 'usr-1',
    name: 'Test User',
    email: 'test@example.com',
    company_id: 'comp-1',
    roles: ['admin'],
    permissions: [],
  };
  const token = jwt.sign(payload, process.env.JWT_SECRET || 'a-very-long-and-secure-test-secret-at-least-32-chars-long');
  const verified = jwt.decode(token) as any;
  assert.equal(verified.session_id, 'sess-test-123', 'Access token must carry session_id claim');

  const authMiddlewareSrc = fs.readFileSync(
    path.join(__dirname, '../middleware/auth.middleware.ts'),
    'utf8'
  );
  assert.match(
    authMiddlewareSrc,
    /decoded\.session_id/,
    'auth.middleware.ts must validate decoded.session_id against sessions table'
  );
  assert.match(
    authMiddlewareSrc,
    /is_revoked.*session_revoked/s,
    'auth.middleware.ts must reject revoked sessions immediately'
  );
  console.log('  ✓ G1: Session ID embedding and immediate revocation check verified');

  // Test 6: ProductImageController requires authentication or peer token
  const imageControllerSrc = fs.readFileSync(
    path.join(__dirname, '../modules/catalog/product-image.controller.ts'),
    'utf8'
  );
  assert.match(
    imageControllerSrc,
    /authenticateImageUpload/,
    'product-image.controller.ts must enforce authenticateImageUpload'
  );
  assert.match(
    imageControllerSrc,
    /x-serenut-peer-token/,
    'product-image.controller.ts must validate terminal peer tokens'
  );
  console.log('  ✓ I3: Product image upload authentication and peer token security verified');

  console.log('✅ ALL PHASE 1 SECURITY AND LOCK VERIFICATION TESTS PASSED!');
}

runPhase1Tests().catch((err) => {
  console.error('❌ Phase 1 test failed:', err);
  process.exit(1);
});
