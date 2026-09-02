import { Pool } from 'pg';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

export async function runMigrations(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    console.log('🔒 Configuring database migration lock timeout (10s)...');
    await client.query("SET lock_timeout = '10s'");
    // Schema and PL/pgSQL compilation can legitimately exceed the ordinary
    // request-query timeout on slow CI/test hosts. This applies only to this
    // dedicated migration connection and is reset before it returns to pool.
    await client.query('SET statement_timeout = 0');
    console.log('🔒 Acquiring database migration lock...');
    await client.query('SELECT pg_advisory_lock(7429185)');
    console.log('🔄 Running database migrations...');
    await client.query('SET search_path TO public');
    
    // Create schema_migrations table if not exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        checksum VARCHAR(64),
        applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    `);
    await client.query('ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum VARCHAR(64)');

    // Check if migration version 1 has been applied
    // 1. Fetch all applied versions
    const dbVersionsRes = await client.query('SELECT version, checksum FROM schema_migrations');
    const appliedVersionsMap = new Map<number, string>();
    for (const row of dbVersionsRes.rows) {
      appliedVersionsMap.set(row.version, row.checksum);
    }

    // 2. Scan db directory for migration files
    const dbDir = path.join(__dirname, '../db');
    const files = fs.readdirSync(dbDir);
    const migrationsToRun: { version: number; file: string; path: string }[] = [];

    for (const file of files) {
      if (file === 'schema.sql') {
        migrationsToRun.push({ version: 1, file, path: path.join(dbDir, file) });
      } else {
        const match = file.match(/^schema_v(\d+)\.sql$/);
        if (match) {
          migrationsToRun.push({ version: parseInt(match[1], 10), file, path: path.join(dbDir, file) });
        }
      }
    }

    // Sort migrations by version ascending to ensure correct order
    migrationsToRun.sort((a, b) => a.version - b.version);

    // 3. Process migrations
    for (const migration of migrationsToRun) {
      const sqlContent = fs.readFileSync(migration.path, 'utf8');
      // Normalize line endings to prevent checksum mismatch across Windows/Linux git checkouts
      const normalizedSql = sqlContent.replace(/\r\n/g, '\n');
      const fileChecksum = crypto.createHash('sha256').update(normalizedSql).digest('hex');

      if (appliedVersionsMap.has(migration.version)) {
        // Verify Checksum Drift
        const dbChecksum = appliedVersionsMap.get(migration.version);
        if (dbChecksum && dbChecksum !== fileChecksum) {
          // v83 and v91 were deployed during emergency production rollouts before their
          // canonical files reached Git. Their SQL is intentionally idempotent
          // (DROP POLICY IF EXISTS / IF NOT EXISTS plus policy recreation), so replay
          // once to converge the schema and record the reviewed canonical checksum.
          // No other migration is allowed to self-reconcile checksum drift.
          if (migration.version !== 83 && migration.version !== 91) {
            throw new Error(
              `🚨 MIGRATION CHECKSUM DRIFT DETECTED (version ${migration.version})!\n` +
              `  Database stored checksum: ${dbChecksum}\n` +
              `  Local file checksum:      ${fileChecksum}\n` +
              `  File: ${migration.file}\n` +
              `  Please do not modify applied migration files in production.`
            );
          }
          console.warn(
            `⚠️ Reconciling reviewed idempotent migration v${migration.version} checksum drift.`,
          );
          await client.query('BEGIN');
          try {
            await client.query('SET search_path TO public');
            await client.query(normalizedSql);
            await client.query(
              'UPDATE schema_migrations SET checksum = $1 WHERE version = $2',
              [fileChecksum, migration.version],
            );
            await client.query('COMMIT');
            appliedVersionsMap.set(migration.version, fileChecksum);
          } catch (reconcileError) {
            await client.query('ROLLBACK');
            throw reconcileError;
          }
          console.log('✅ Migration version 83 schema and checksum reconciled.');
          continue;
        }
        console.log(`✅ Migration version ${migration.version} (${migration.file}) checksum verified.`);
      } else {
        console.log(`🔄 Applying database migration version ${migration.version} (${migration.file})...`);

        await client.query('BEGIN');
        try {
          await client.query('SET search_path TO public');
          await client.query(normalizedSql);
          await client.query('INSERT INTO schema_migrations (version, checksum) VALUES ($1, $2)', [migration.version, fileChecksum]);
          await client.query('COMMIT');
        } catch (execErr) {
          await client.query('ROLLBACK');
          throw execErr;
        }
        console.log(`✅ Migration version ${migration.version} (${migration.file}) applied successfully.`);
      }
    }

  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  } finally {
    try {
      console.log('🔓 Releasing database migration lock...');
      await client.query('SELECT pg_advisory_unlock(7429185)');
    } catch (unlockErr: any) {
      console.error('⚠️ Failed to release migration lock:', unlockErr.message);
    }
    await client.query('RESET statement_timeout').catch(() => {});
    await client.query('RESET lock_timeout').catch(() => {});
    client.release();
  }
}
