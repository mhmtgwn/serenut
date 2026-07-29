import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  filterNavByEntitlements,
  resolveLandingModuleId,
  resolveLandingRoute,
} from '../config/app-shell';

const projectRoot = path.resolve(__dirname, '../..');

async function run() {
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
  for (const loader of ['platform-companies', 'platform-health', 'platform-security']) {
    assert.match(runtime, new RegExp(`'${loader}': async`), `${loader} loader must be registered`);
  }

  const appSource = fs.readFileSync(path.join(projectRoot, 'public/app/js/app.js'), 'utf8');
  assert.doesNotMatch(appSource, /module:\s*isSysadmin\s*\?/, 'frontend must preserve backend module kinds');
  assert.match(appSource, /item\.module === 'home'/, 'home must be a first-class shell view');
  assert.match(appSource, /landing_module_id/, 'frontend must use the canonical landing module id');
  assert.match(appHtml, /id="boot-state"/, 'application shell must expose a non-empty loading state');

  assert.equal(resolveLandingModuleId(['sysadmin'], []), 'platform-overview');
  assert.equal(resolveLandingModuleId(['owner'], ['billing:view']), 'billing-center');
  assert.equal(resolveLandingModuleId(['owner'], ['devices:view']), 'company-dashboard');
  assert.equal(resolveLandingModuleId(['owner'], []), 'workspace-home');
  assert.equal(resolveLandingRoute(['owner'], []), '/app/#home');

  const ownerHome = filterNavByEntitlements(['owner'], []);
  assert.ok(ownerHome.some((item) => item.id === 'workspace-home' && item.module === 'home'));
  const sysadminNav = filterNavByEntitlements(['sysadmin'], []);
  assert.ok(sysadminNav.some((item) => item.id === 'platform-overview' && item.module === 'admin'));

  console.log('Web route contract passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
