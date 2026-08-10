// server/src/scripts/run-migrations.ts
import { Pool } from 'pg';
import { runMigrations } from '../migrations';

// Production application traffic uses a restricted RLS role. Schema changes
// must use the separately managed privileged migration role; tests and legacy
// development environments may safely fall back to DATABASE_URL.
const migrationDatabaseUrl =
  process.env.MIGRATION_DATABASE_URL || process.env.DATABASE_URL;

if (!migrationDatabaseUrl) {
  throw new Error('MIGRATION_DATABASE_URL or DATABASE_URL is required.');
}

const migrationPool = new Pool({
  connectionString: migrationDatabaseUrl,
  max: 1,
  idleTimeoutMillis: 1000,
  connectionTimeoutMillis: 10000,
});

async function main() {
  try {
    await runMigrations(migrationPool);
    console.log('🎉 Migrations finished successfully!');
    await migrationPool.end();
    process.exit(0);
  } catch (err) {
    console.error('❌ Migrations failed:', err);
    await migrationPool.end().catch(() => {});
    process.exit(1);
  }
}

main();
