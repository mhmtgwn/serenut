// server/src/scripts/run-migrations.ts
import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';

async function main() {
  try {
    await runMigrations(pgPool);
    console.log('🎉 Migrations finished successfully!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migrations failed:', err);
    process.exit(1);
  }
}

main();
