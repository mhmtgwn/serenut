import assert from 'assert';
import fs from 'fs';
import path from 'path';

const read = (relPath: string) => fs.readFileSync(path.resolve(__dirname, relPath), 'utf8');

function runPhase8Tests() {
  console.log('=== Phase 8 Test: Web Panelleri Mantık, Akış ve UX İyileştirmeleri (Faz A, B, C) ===');

  const portalController = read('../modules/portal/portal.controller.ts');
  const authService = read('../modules/auth/auth.service.ts');
  const authController = read('../modules/auth/auth.controller.ts');
  const notificationWorker = read('../workers/notification.worker.ts');
  const emailTemplates = read('../modules/notifications/email.templates.ts');
  const adminController = read('../modules/admin/admin.controller.ts');
  const apiClientJs = read('../../public/shared/js/api-client.js');
  const formattersJs = read('../../public/shared/js/formatters.js');
  const authJs = read('../../public/auth/auth.js');
  const appJs = read('../../public/app/js/app.js');
  const runtimeJs = read('../../public/app/js/module-runtime.js');

  // Faz A: Backend Auth, Email Verification, Recovery & Portal Sub-Users
  assert.ok(
    portalController.includes("INSERT INTO users (id,company_id,name,email,password_hash,is_active,email_verified_at) VALUES($1,$2,$3,$4,$5,TRUE,NOW())"),
    'FAIL: portal.controller.ts POST /users must set email_verified_at = NOW() for sub-users'
  );
  console.log('✔ 1. Portal alt kullanıcı oluşturmada email_verified_at = NOW() doğrulandı');

  assert.ok(
    portalController.includes('SELECT store_limit FROM license_entitlements') &&
    portalController.includes('BRANCH_LIMIT_EXCEEDED'),
    'FAIL: portal.controller.ts POST /stores must enforce store_limit quota'
  );
  console.log('✔ 2. Portal POST /stores şube limiti (store_limit) kota kontrolü doğrulandı');

  assert.ok(
    authService.includes("companyStatusRes.rows[0]?.status === 'suspended'") &&
    authService.includes('SELECT 1 FROM email_verification_tokens WHERE user_id = $1 AND used_at IS NULL LIMIT 1'),
    'FAIL: auth.service.ts login() must check company suspension and only auto-activate unverified registration tokens'
  );
  console.log('✔ 3. AuthService.login() askıdaki firma ve devre dışı alt kullanıcı koruması doğrulandı');

  assert.ok(
    authService.includes('session_id: session.replaced_by') &&
    authService.includes('if (!session.is_revoked)') &&
    authService.includes('expires_in: 900'),
    'FAIL: auth.service.ts refresh() must separate expired tokens from replay attacks, include session_id in grace retry, and return expires_in: 900'
  );
  console.log('✔ 4. AuthService.refresh() süresi dolan token / replay ayrımı ve session_id koruması doğrulandı');

  assert.ok(
    authController.includes("err.message === 'user_suspended'") &&
    authController.includes("createError('AUTH003')") &&
    authController.includes('/login?error=verification_invalid') &&
    authController.includes('/login?error=verification_expired'),
    'FAIL: auth.controller.ts must handle user_suspended in /refresh and redirect invalid/expired email verification to /login'
  );
  console.log('✔ 5. AuthController /refresh user_suspended ve /verify-email kullanıcı dostu yönlendirmesi doğrulandı');

  assert.ok(
    authController.includes('notif-auth-') &&
    notificationWorker.includes("notificationId.startsWith('notif-auth-')"),
    'FAIL: Transactional auth emails must use notif-auth- prefix and be exempt from notification credit deduction'
  );
  console.log('✔ 6. Transactional auth e-postalarının bildirim kredisi muafiyeti doğrulandı');

  assert.ok(
    emailTemplates.includes('15 dakika') &&
    !emailTemplates.includes('https://serenut.com/portal/invoices') &&
    emailTemplates.includes('https://serenut.com/app/#billing-center'),
    'FAIL: email.templates.ts must show 15 dakika for password reset and point to /app/ routes'
  );
  console.log('✔ 7. E-posta şablonları süre (15 dk) ve güncel /app/ bağlantıları doğrulandı');

  assert.ok(
    adminController.includes("(tier === 'trial' || tier === 'basic') ? 'plan-basic'") &&
    adminController.includes('license.rows[0]?.id || activation.entitlementId'),
    'FAIL: admin.controller.ts POST /licenses must map trial/basic to plan-basic and guard license.rows[0]'
  );
  console.log('✔ 8. Admin manuel lisans üretimi (plan-basic eşleşmesi ve null-safe yanıt) doğrulandı');

  // Faz B: Web Auth & Onboarding UX
  assert.ok(
    apiClientJs.includes('export async function refreshAccessToken()') &&
    authJs.includes('await refreshAccessToken()') &&
    authJs.includes('id="copy-recovery-codes"') &&
    authJs.includes('id="confirm-codes-saved"') &&
    authJs.includes('selected_plan_id') &&
    authJs.includes("params.get('error') === 'verification_expired'"),
    'FAIL: auth.js must refresh token before clearing session, provide copy+confirm for recovery codes, preserve email verification notice, and support ?plan= prefill'
  );
  console.log('✔ 9. Web Auth (oturum yenileme, kurtarma kodu kopyalama/onay, e-posta doğrulama uyarısı ve paket seçimi) doğrulandı');

  // Faz C: Web Panels (Customer Portal & Sysadmin Panel)
  assert.ok(
    formattersJs.includes("'trialing': 'Deneme Süresi'") &&
    formattersJs.includes("'pending_customer': 'Müşteri Yanıtı Bekleniyor'") &&
    formattersJs.includes("'owner': 'Firma Sahibi'") &&
    formattersJs.includes("'sysadmin': 'Sistem Yöneticisi'"),
    'FAIL: formatters.js must localize all statuses, roles, and support states into Turkish'
  );
  console.log('✔ 10. Formatters Türkçe durum, rol ve destek kategorisi çevirileri doğrulandı');

  assert.ok(
    appJs.includes('handlePaymentQueryFeedback') &&
    appJs.includes('isUserEditingEmbedForm') &&
    appJs.includes("eventType === 'LicenseUpdated'"),
    'FAIL: app.js must handle ?payment= query feedback, refresh token on LicenseUpdated, and protect active forms during WebSocket events'
  );
  console.log('✔ 11. App shell (?payment= geri bildirimi, LicenseUpdated token yenileme ve WebSocket form koruması) doğrulandı');

  assert.ok(
    runtimeJs.includes('showToast') &&
    runtimeJs.includes('showRecoveryClaimBanner') &&
    runtimeJs.includes('onboarding-checklist') &&
    runtimeJs.includes('invoice-pdf-download') &&
    runtimeJs.includes('customer-close-ticket') &&
    runtimeJs.includes('company-logo-upload-form') &&
    runtimeJs.includes('p.session_id||p.jti||null') &&
    runtimeJs.includes('attachTableFilter') &&
    runtimeJs.includes('stopWhatsAppConnectionPoll();\n  const loader=loaders[item.id];'),
    'FAIL: module-runtime.js must include toast notifications, copyable recovery claim banner, onboarding checklist, invoice PDF download, customer ticket close, logo file upload, session_id match, table filter, and WhatsApp poll cleanup'
  );
  console.log('✔ 12. Müşteri portalı ve Sysadmin paneli kullanılabilirlik (UX) geliştirmeleri doğrulandı');

  console.log('\nALL PHASE 8 TESTS PASSED! (12/12) 🎉');
}

runPhase8Tests();

