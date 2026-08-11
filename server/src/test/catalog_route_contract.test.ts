import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(__dirname, '../..');
const controller = fs.readFileSync(
  path.join(root, 'src/modules/catalog/catalog.controller.ts'),
  'utf8',
);
const server = fs.readFileSync(path.join(root, 'src/server.ts'), 'utf8');
const compose = fs.readFileSync(path.join(root, 'docker-compose.prod.yml'), 'utf8');

assert.match(server, /app\.use\('\/api\/v1\/catalogs', catalogRouter\)/);
assert.match(controller, /router\.get\('\/ready'/);
assert.match(controller, /router\.get\('\/ready\/download'/);
assert.match(controller, /Content-Length/);
assert.match(controller, /sha256: checksum/);
assert.match(controller, /application\/zip/);
assert.match(compose, /\.\/catalogs:\/app\/catalogs:ro/);

console.log('catalog route contract: PASS');
