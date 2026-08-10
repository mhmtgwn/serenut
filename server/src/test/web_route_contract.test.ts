import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  filterNavByEntitlements,
  resolveLandingModuleId,
  resolveLandingRoute,
} from '../config/app-shell';
import { BillingDomainService } from '../modules/billing/billing-domain.service';

const projectRoot = path.resolve(__dirname, '../..');

async function run() {
  const quoteFor = async (row: Record<string, unknown>, period: 'monthly' | 'yearly') =>
    BillingDomainService.quotePlan({ query: async () => ({ rows: [row] }) } as any, 'company-test', 'plan-test', period);
  const monthlyBase = { id: 'plan-test', name: 'Aylık', price: 100, effective_price: 100,
    currency: 'TRY', billing_interval: 'monthly', custom_price: null,
    override_billing_interval: null, device_limit: 1, store_limit: 1, user_limit: 1 };
  assert.equal((await quoteFor(monthlyBase, 'monthly')).amount, 100);
  assert.equal((await quoteFor(monthlyBase, 'yearly')).amount, 1020);
  const yearlyBase = { ...monthlyBase, name: 'Yıllık', price: 1020, effective_price: 1020, billing_interval: 'yearly' };
  assert.equal((await quoteFor(yearlyBase, 'yearly')).amount, 1020);
  assert.equal((await quoteFor(yearlyBase, 'monthly')).amount, 100);
  const lockedCompanyPrice = { ...monthlyBase, effective_price: 900, custom_price: 900,
    override_billing_interval: 'yearly' };
  const lockedQuote = await quoteFor(lockedCompanyPrice, 'monthly');
  assert.equal(lockedQuote.period, 'yearly');
  assert.equal(lockedQuote.amount, 900);

  const serverSource = fs.readFileSync(path.join(projectRoot, 'src/server.ts'), 'utf8');
  const appHtml = fs.readFileSync(path.join(projectRoot, 'public/app/index.html'), 'utf8');

  assert.doesNotMatch(appHtml, /login-form|register-form|reset-form|auth-view/, 'the application shell must not contain authentication screens');
  const authPages: Record<string, string> = {
    '/login': 'login.html',
    '/register': 'register.html',
    '/forgot-password': 'forgot-password.html',
    '/reset-password': 'reset-password.html',
  };
  for (const [route, file] of Object.entries(authPages)) {
    assert.match(serverSource, new RegExp(route.replace('/', '\\/')), `${route} must be declared by Express`);
    assert.ok(fs.existsSync(path.join(projectRoot, 'public/auth', file)), `${file} must exist`);
    const authHtml = fs.readFileSync(path.join(projectRoot, 'public/auth', file), 'utf8');
    assert.match(authHtml, /<img src="\/shared\/assets\/serenut-os-color\.svg"/, `${file} must use the horizontal Serenut OS wordmark`);
    assert.doesNotMatch(authHtml, /<img[^>]+(?:favicon|icon-(?:192|512)|logo-color\.svg)/, `${file} must not use an application icon as its brand heading`);
  }
  assert.doesNotMatch(serverSource, /['"]\/signup|['"]\/login\.html|['"]\/register\.html/, 'legacy authentication aliases must not be registered');
  assert.match(serverSource, /app\.get\(\/\^\\\/app\$\/.*res\.redirect\(301, '\/app\/'\)/s, 'only slashless /app must canonicalize to /app/');

  const websiteDir = path.join(projectRoot, 'public/website');
  const publicSources = fs.readdirSync(websiteDir, { recursive: true })
    .filter((entry) => /\.(html|js|css)$/.test(String(entry)))
    .map((entry) => fs.readFileSync(path.join(websiteDir, String(entry)), 'utf8'))
    .join('\n');

  assert.doesNotMatch(publicSources, /\/app\/#register/, 'marketing pages must use /register');
  assert.doesNotMatch(publicSources, /embed=1|auth-modal-iframe/, 'iframe authentication must stay removed');

  const runtime = fs.readFileSync(path.join(projectRoot, 'public/app/js/module-runtime.js'), 'utf8');
  const authRuntime = fs.readFileSync(path.join(projectRoot, 'public/auth/auth.js'), 'utf8');
  const forgotHtml = fs.readFileSync(path.join(projectRoot, 'public/auth/forgot-password.html'), 'utf8');
  assert.match(forgotHtml, /id="recovery-code"/, 'self-service recovery must require a recovery code');
  assert.match(forgotHtml, /id="recovery-claim-form"/, 'admin-assisted recovery must have a claim UI');
  assert.match(forgotHtml, /id="email-recovery-form"/, 'verified-email recovery must have a request UI');
  assert.match(authRuntime, /sessionStorage\.setItem\('serenut_password_reset_token'/, 'reset authorization must stay out of the URL');
  assert.match(authRuntime, /history\.replaceState/, 'email reset token must be removed from browser history immediately');
  assert.match(authRuntime, /const form = event\.currentTarget;/, 'async recovery submission must retain its form reference');
  assert.doesNotMatch(authRuntime, /event\.currentTarget\.reset\(\)/, 'async recovery submission must not dereference a cleared event currentTarget');
  assert.doesNotMatch(runtime, /body:\{new_password:/, 'admin UI must not set user passwords directly');
  assert.doesNotMatch(runtime, /Şifre Sıfırlama Linki|Geçici [Şş]ifre|new-user-password|company-admin-pw/, 'SMTP-free activation must not render legacy email or temporary-password controls');
  assert.match(runtime, /id="new-password"[^>]+minlength="10"/, 'account password form must match the backend password policy');
  assert.match(runtime, /recovery\/admin-assist/, 'tenant admin UI must use canonical recovery requests');
  for (const loader of [
    'company-stores', 'company-devices', 'company-licenses', 'company-downloads',
    'platform-companies', 'platform-subscriptions', 'platform-licenses', 'platform-devices',
    'platform-health', 'platform-maintenance', 'platform-security',
  ]) {
    assert.match(runtime, new RegExp(`'${loader}': async`), `${loader} loader must be registered`);
  }
  const adminController = fs.readFileSync(path.join(projectRoot, 'src/modules/admin/admin.controller.ts'), 'utf8');
  const supportController = fs.readFileSync(path.join(projectRoot, 'src/modules/support/support.controller.ts'), 'utf8');
  const portalController = fs.readFileSync(path.join(projectRoot, 'src/modules/portal/portal.controller.ts'), 'utf8');
  const mailController = fs.readFileSync(path.join(projectRoot, 'src/modules/mail/mail.controller.ts'), 'utf8');
  const billingController = fs.readFileSync(path.join(projectRoot, 'src/modules/billing/billing.controller.ts'), 'utf8');
  const billingDomain = fs.readFileSync(path.join(projectRoot, 'src/modules/billing/billing-domain.service.ts'), 'utf8');
  const releaseController = fs.readFileSync(path.join(projectRoot, 'src/modules/release/release.controller.ts'), 'utf8');
  assert.doesNotMatch(billingController, /mock-checkout|ENABLE_MOCK_PAYMENTS|SİMÜLE KART/i, 'mock payment routes and controls must not exist');
  assert.doesNotMatch(releaseController, /default-windows|default-android/, 'release history must never invent fallback releases');
  assert.match(billingController, /is_enabled: true/, 'enabled payment methods must expose an explicit enabled state');
  assert.match(billingController, /requirePermission\('billing:view'\).*request-bank-transfer/s, 'billing mutations must enforce billing permission');
  assert.match(billingController, /'\/subscribe', authenticateUser, requirePermission\('billing:view'\)/, 'card checkout must enforce billing permission');
  assert.match(billingController, /router\.post\('\/plans', authenticateUser, requireRole\('sysadmin'\)/, 'sysadmin must be able to create sales plans');
  assert.match(billingController, /monthly_price[\s\S]*yearly_price[\s\S]*locked_billing_period/, 'effective plans must expose canonical period prices');
  assert.match(billingDomain, /p\.billing_interval/, 'quote calculation must honor the configured plan price interval');
  assert.match(runtime, /reason:reason\.trim\(\)/, 'manual license creation must submit its audited reason');
  assert.match(runtime, /quote\.billing_period/, 'checkout summary must display the period returned by the canonical quote');
  assert.doesNotMatch(runtime, /method=>method\.id==='iyzico' && method\.is_enabled/, 'card availability must not reject the enabled-method API shape');
  assert.match(adminController, /\/maintenance\/preview/, 'maintenance preview endpoint must exist');
  assert.match(adminController, /\/maintenance\/cleanup/, 'maintenance cleanup endpoint must exist');
  assert.match(adminController, /\/companies\/:id\/manual-subscription/, 'sysadmin must be able to grant an audited subscription without a payment event');
  assert.match(runtime, /id="package-plan" required/, 'company package editor must expose its base plan selection');
  assert.match(runtime, /id="manual-subscription-form"/, 'company detail must distinguish manual activation from a payment-backed offer');
  assert.match(portalController, /runWithRoleCatalogAccess/, 'tenant role lists must use their restricted catalog helper');
  assert.match(portalController, /r\.company_id IS NULL OR r\.company_id = \$1/, 'tenant role lists must explicitly constrain global and company roles');
  assert.match(portalController, /const list = await runWithRoleCatalogAccess\([\s\S]*FROM users u/, 'tenant user lists must resolve global role names');
  assert.match(portalController, /Şube oluşturma yetkiniz yok/, 'branch creation must enforce management authorization');
  assert.doesNotMatch(supportController, /createInboundEmailRequest\(/, 'inbound email must not automatically create a support request');
  assert.match(mailController, /route-to-support/, 'mailbox must expose explicit support routing');
  assert.match(mailController, /router\.delete\('\/:id'/, 'mailbox must expose recoverable delete');
  assert.match(supportController, /guest-requests\/:id\/status/, 'guest support requests must expose workflow actions');
  assert.match(runtime, /Desteğe Yönlendir/, 'mail UI must make support routing explicit');
  assert.match(runtime, /Çöp Kutusu/, 'mail UI must expose its trash folder');
  assert.match(runtime, /id="mail-restore"/, 'mail UI must allow restoring deleted messages');
  assert.match(runtime, /showGuestRequest\(routed\.request\.id,'platform-mail'\)/, 'support routing must return to the mailbox');
  assert.match(runtime, /id="guest-email-reply"/, 'guest support replies must use the internal mail composer');
  assert.doesNotMatch(runtime, /href="#account-settings"/, 'sysadmin security must not link to a hidden company-scoped module');
  assert.match(runtime, /manual-subscription-form'[\s\S]*catch\(x\)\{notice\(x\.message\);b\.disabled=false\}\}\);/, 'company detail actions must be bound inside the detail click handler');
  assert.match(runtime, /Ön Destek Başvuruları/, 'support UI must distinguish pre-support intake from the mailbox');
  assert.match(adminController, /SUNUCUYU TEMIZLE/, 'maintenance cleanup must require an explicit confirmation phrase');

  const appSource = fs.readFileSync(path.join(projectRoot, 'public/app/js/app.js'), 'utf8');
  const themeSource = fs.readFileSync(path.join(projectRoot, 'public/app/css/theme.css'), 'utf8');
  assert.doesNotMatch(appSource, /module:\s*isSysadmin\s*\?/, 'frontend must preserve backend module kinds');
  assert.match(appSource, /item\.module === 'home'/, 'home must be a first-class shell view');
  assert.match(appSource, /landing_module_id/, 'frontend must use the canonical landing module id');
  assert.match(appSource, /addEventListener\('hashchange'/, 'browser back and forward navigation must update the active module');
  assert.doesNotMatch(appSource, /M5 5h14v14H5z/, 'navigation must not regress to square placeholder icons');
  assert.match(appSource, /const iconPaths = \{/, 'navigation must provide module-specific icons');
  assert.match(themeSource, /\.sidebar-brand:before\s*\{[^}]*content:none!important[^}]*display:none!important/s, 'the sidebar wordmark must not render a second pseudo-element logo');
  assert.match(appHtml, /id="boot-state"/, 'application shell must expose a non-empty loading state');
  assert.match(appHtml, /favicon\.ico\?v=20260730-icon4/, 'application shell must reference the current browser icon revision');

  const webManifest = fs.readFileSync(path.join(projectRoot, 'public/site.webmanifest'), 'utf8');
  assert.match(webManifest, /icon-maskable-192\.png/, 'web manifest must provide a 192px maskable icon');
  assert.match(webManifest, /icon-maskable-512\.png/, 'web manifest must provide a 512px maskable icon');
  for (const asset of ['favicon.ico', 'favicon-32.png', 'apple-touch-icon.png', 'icon-192.png', 'icon-512.png', 'icon-maskable-192.png', 'icon-maskable-512.png']) {
    assert.ok(fs.existsSync(path.join(projectRoot, 'public', asset)), `${asset} must exist`);
    assert.match(serverSource, new RegExp(`['"]${asset.replace('.', '\\.')}['"]`), `${asset} must be exposed from the public root`);
  }

  assert.equal(resolveLandingModuleId(['sysadmin'], []), 'platform-overview');
  assert.equal(resolveLandingModuleId(['owner'], ['billing:view']), 'billing-center');
  assert.equal(resolveLandingModuleId(['owner'], ['devices:view']), 'company-dashboard');
  assert.equal(resolveLandingModuleId(['owner'], []), 'workspace-home');
  assert.equal(resolveLandingRoute(['owner'], []), '/app/#home');

  const ownerHome = filterNavByEntitlements(['owner'], []);
  assert.ok(ownerHome.some((item) => item.id === 'workspace-home' && item.module === 'home'));
  const sysadminNav = filterNavByEntitlements(['sysadmin'], []);
  assert.ok(sysadminNav.some((item) => item.id === 'platform-overview' && item.module === 'admin'));
  assert.ok(sysadminNav.some((item) => item.id === 'platform-maintenance' && item.module === 'admin'));
  assert.ok(sysadminNav.some((item) => item.id === 'platform-support' && item.section === 'communication'));
  assert.ok(sysadminNav.some((item) => item.id === 'platform-mail' && item.section === 'communication'));
  assert.ok(!sysadminNav.some((item) => item.id === 'account-settings'), 'company-scoped account settings must not be shown to sysadmin');
  const ownerNavigation = filterNavByEntitlements(['owner'], ['billing:view']);
  assert.ok(ownerNavigation.some((item) => item.id === 'support-center' && item.section === 'communication'), 'customer support must be grouped under communication');
  for (const id of ['platform-subscriptions', 'platform-licenses', 'platform-devices']) {
    assert.ok(sysadminNav.some((item) => item.id === id && item.module === 'admin'), `${id} must be visible to sysadmin`);
  }

  console.log('Web route contract passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
