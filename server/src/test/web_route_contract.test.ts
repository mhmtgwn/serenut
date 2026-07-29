import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

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

  console.log('Web route contract passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
