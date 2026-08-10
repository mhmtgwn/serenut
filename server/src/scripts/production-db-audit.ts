import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { Client } from 'pg';

dotenv.config();

type Check = { name: string; ok: boolean; detail: string };
const checks: Check[] = [];
const pass = (name: string, detail: string) => checks.push({ name, ok: true, detail });
const fail = (name: string, detail: string) => checks.push({ name, ok: false, detail });

function expectedSchemaVersion(): number {
  const dbDir = path.resolve(__dirname, '../../db');
  return fs.readdirSync(dbDir).reduce((max, file) => {
    const match = /^schema_v(\d+)\.sql$/.exec(file);
    return match ? Math.max(max, Number(match[1])) : max;
  }, 0);
}

async function audit(): Promise<void> {
  const databaseUrl = process.env.PRODUCTION_DATABASE_URL;
  if (!databaseUrl) {
    throw new Error('PRODUCTION_DATABASE_URL açıkça verilmelidir; DATABASE_URL güvenlik nedeniyle kullanılmaz.');
  }

  const url = new URL(databaseUrl);
  console.log(`Production DB audit: ${url.hostname}:${url.port || '5432'}${url.pathname}`);
  const client = new Client({
    connectionString: databaseUrl,
    application_name: 'serenut-production-readonly-audit',
    statement_timeout: 30_000,
    query_timeout: 35_000,
  });

  await client.connect();
  try {
    await client.query('BEGIN TRANSACTION READ ONLY');

    const expected = expectedSchemaVersion();
    const migration = await client.query('SELECT COALESCE(MAX(version), 0)::int AS version FROM schema_migrations');
    const actual = Number(migration.rows[0].version);
    actual === expected
      ? pass('Migration seviyesi', `v${actual}`)
      : fail('Migration seviyesi', `veritabanı v${actual}, kod v${expected}`);

    const invalidIndexes = await client.query(`
      SELECT n.nspname || '.' || c.relname AS name
      FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND NOT i.indisvalid
    `);
    invalidIndexes.rowCount === 0
      ? pass('İndeks bütünlüğü', 'geçersiz indeks yok')
      : fail('İndeks bütünlüğü', invalidIndexes.rows.map(r => r.name).join(', '));

    const unvalidatedConstraints = await client.query(`
      SELECT conrelid::regclass::text AS table_name, conname
      FROM pg_constraint
      WHERE connamespace='public'::regnamespace AND NOT convalidated
    `);
    unvalidatedConstraints.rowCount === 0
      ? pass('Constraint bütünlüğü', 'doğrulanmamış constraint yok')
      : fail('Constraint bütünlüğü', unvalidatedConstraints.rows.map(r => `${r.table_name}.${r.conname}`).join(', '));

    const tenantTables = await client.query(`
      SELECT DISTINCT c.table_name
      FROM information_schema.columns c
      WHERE c.table_schema='public' AND c.column_name='company_id'
      ORDER BY c.table_name
    `);
    const rls = await client.query(`
      SELECT c.relname AS table_name, c.relrowsecurity, c.relforcerowsecurity,
             COUNT(p.policyname)::int AS policy_count
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      LEFT JOIN pg_policies p ON p.schemaname=n.nspname AND p.tablename=c.relname
      WHERE n.nspname='public' AND c.relkind='r'
      GROUP BY c.relname,c.relrowsecurity,c.relforcerowsecurity
    `);
    const rlsByTable = new Map(rls.rows.map(r => [r.table_name, r]));
    const rlsMissing = tenantTables.rows
      .map(r => r.table_name as string)
      .filter(table => {
        const row = rlsByTable.get(table);
        return !row || !row.relrowsecurity || !row.relforcerowsecurity || row.policy_count < 1;
      });
    rlsMissing.length === 0
      ? pass('Tenant RLS', `${tenantTables.rowCount} company_id tablosunda RLS + FORCE + policy mevcut`)
      : fail('Tenant RLS', `eksik tablolar: ${rlsMissing.join(', ')}`);

    const coreTables = ['companies', 'users', 'products', 'customers', 'sales', 'financial_transactions', 'audit_logs'];
    const existing = await client.query(`SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename=ANY($1)`, [coreTables]);
    const existingNames = new Set(existing.rows.map(r => r.tablename));
    const missingCore = coreTables.filter(table => !existingNames.has(table));
    missingCore.length === 0
      ? pass('Çekirdek tablolar', `${coreTables.length} tablo mevcut`)
      : fail('Çekirdek tablolar', `eksik: ${missingCore.join(', ')}`);

    const duplicateEmails = await client.query(`
      SELECT COUNT(*)::int AS count FROM (
        SELECT company_id, LOWER(email) FROM users WHERE email IS NOT NULL
        GROUP BY company_id, LOWER(email) HAVING COUNT(*) > 1
      ) duplicates
    `);
    Number(duplicateEmails.rows[0].count) === 0
      ? pass('Kullanıcı e-posta tekilliği', 'tenant içinde tekrar yok')
      : fail('Kullanıcı e-posta tekilliği', `${duplicateEmails.rows[0].count} tekrar grubu`);

    const inactiveOrphans = await client.query(`
      SELECT COUNT(*)::int AS count
      FROM users u LEFT JOIN companies c ON c.id=u.company_id
      WHERE c.id IS NULL
    `);
    Number(inactiveOrphans.rows[0].count) === 0
      ? pass('Tenant referans bütünlüğü', 'şirketsiz kullanıcı yok')
      : fail('Tenant referans bütünlüğü', `${inactiveOrphans.rows[0].count} şirketsiz kullanıcı`);

    const consentVersion = process.env.LEGAL_DOCUMENT_VERSION;
    consentVersion
      ? pass('Yasal belge sürümü', consentVersion)
      : fail('Yasal belge sürümü', 'LEGAL_DOCUMENT_VERSION tanımlı değil (önerilen: 2026-08-09)');

    await client.query('ROLLBACK');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    await client.end();
  }

  console.table(checks);
  const failures = checks.filter(check => !check.ok);
  if (failures.length) {
    console.error(`AUDIT FAILED: ${failures.length} satış engeli bulundu.`);
    process.exitCode = 1;
  } else {
    console.log('AUDIT PASSED: Salt-okunur production veritabanı kontrolleri başarılı.');
  }
}

audit().catch(error => {
  console.error('AUDIT ERROR:', error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
