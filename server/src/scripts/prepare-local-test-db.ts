import dotenv from 'dotenv';
import { Client } from 'pg';
import fs from 'fs';
import path from 'path';

dotenv.config();

async function main() {
  const source = process.env.DATABASE_URL;
  if (!source) throw new Error('DATABASE_URL is required.');

  const url = new URL(source);
  if (!['localhost', '127.0.0.1'].includes(url.hostname)) {
    throw new Error('Refusing to create a test database on a non-local host.');
  }

  const testDatabase = `${url.pathname.replace(/^\//, '')}_test`;
  if (!/^[a-zA-Z0-9_]+_test$/.test(testDatabase)) {
    throw new Error('Unsafe test database name.');
  }

  const adminUrl = new URL(source);
  adminUrl.pathname = '/postgres';
  const admin = new Client({ connectionString: adminUrl.toString() });
  await admin.connect();
  try {
    const exists = await admin.query(
      'SELECT 1 FROM pg_database WHERE datname = $1',
      [testDatabase],
    );
    if (exists.rowCount === 0) {
      await admin.query(`CREATE DATABASE "${testDatabase}"`);
      console.log(`Created local test database: ${testDatabase}`);
    } else {
      console.log(`Local test database already exists: ${testDatabase}`);
    }
  } finally {
    await admin.end();
  }

  url.pathname = `/${testDatabase}`;
  const envPath = path.join(__dirname, '../../.env');
  const current = fs.readFileSync(envPath, 'utf8');
  const escapedUrl = url.toString().replace(/"/g, '\\"');
  const line = `TEST_DATABASE_URL="${escapedUrl}"`;
  const updated = /^TEST_DATABASE_URL=.*$/m.test(current)
    ? current.replace(/^TEST_DATABASE_URL=.*$/m, line)
    : `${current.trimEnd()}\n${line}\n`;
  fs.writeFileSync(envPath, updated, { mode: 0o600 });
  console.log('Updated server/.env with the local test database URL.');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
