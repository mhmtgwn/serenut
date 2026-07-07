import { Pool } from 'pg';
import fs from 'fs';
import path from 'path';

export async function runMigrations(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    console.log('🔒 Configuring database migration lock timeout (10s)...');
    await client.query("SET lock_timeout = '10s'");
    console.log('🔒 Acquiring database migration lock...');
    await client.query('SELECT pg_advisory_lock(7429185)');
    console.log('🔄 Running database migrations...');
    
    // Create schema_migrations table if not exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Check if migration version 1 has been applied
    const res = await client.query('SELECT version FROM schema_migrations WHERE version = 1');
    if (res.rows.length === 0) {
      console.log('Migration version 1 is not applied. Applying now...');
      
      const schemaPath = path.join(__dirname, '../db/schema.sql');
      const schemaSql = fs.readFileSync(schemaPath, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql);
      await client.query('INSERT INTO schema_migrations (version) VALUES (1)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 1 applied successfully!');
    } else {
      console.log('✅ Database is version 1.');
    }

    // Check if migration version 2 has been applied
    const res2 = await client.query('SELECT version FROM schema_migrations WHERE version = 2');
    if (res2.rows.length === 0) {
      console.log('Migration version 2 is not applied. Applying now...');
      
      const schemaPath2 = path.join(__dirname, '../db/schema_v2.sql');
      const schemaSql2 = fs.readFileSync(schemaPath2, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql2);
      await client.query('INSERT INTO schema_migrations (version) VALUES (2)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 2 applied successfully!');
    } else {
      console.log('✅ Database is up to date (version 2).');
    }

    // Check if migration version 3 has been applied
    const res3 = await client.query('SELECT version FROM schema_migrations WHERE version = 3');
    if (res3.rows.length === 0) {
      console.log('Migration version 3 is not applied. Applying now...');
      
      const schemaPath3 = path.join(__dirname, '../db/schema_v3.sql');
      const schemaSql3 = fs.readFileSync(schemaPath3, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql3);
      await client.query('INSERT INTO schema_migrations (version) VALUES (3)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 3 applied successfully! (Release Management Platform)');
    } else {
      console.log('✅ Database is up to date (version 3).');
    }

    // Check if migration version 4 has been applied
    const res4 = await client.query('SELECT version FROM schema_migrations WHERE version = 4');
    if (res4.rows.length === 0) {
      console.log('Migration version 4 is not applied. Applying now...');
      
      const schemaPath4 = path.join(__dirname, '../db/schema_v4.sql');
      const schemaSql4 = fs.readFileSync(schemaPath4, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql4);
      await client.query('INSERT INTO schema_migrations (version) VALUES (4)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 4 applied successfully! (Analytics Performance Indexes)');
    } else {
      console.log('✅ Database is up to date (version 4).');
    }

    // Check if migration version 5 has been applied
    const res5 = await client.query('SELECT version FROM schema_migrations WHERE version = 5');
    if (res5.rows.length === 0) {
      console.log('Migration version 5 is not applied. Applying now...');
      
      const schemaPath5 = path.join(__dirname, '../db/schema_v5.sql');
      const schemaSql5 = fs.readFileSync(schemaPath5, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql5);
      await client.query('INSERT INTO schema_migrations (version) VALUES (5)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 5 applied successfully! (Billing Platform)');
    } else {
      console.log('✅ Database is up to date (version 5).');
    }

    // Check if migration version 6 has been applied
    const res6 = await client.query('SELECT version FROM schema_migrations WHERE version = 6');
    if (res6.rows.length === 0) {
      console.log('Migration version 6 is not applied. Applying now...');
      
      const schemaPath6 = path.join(__dirname, '../db/schema_v6.sql');
      const schemaSql6 = fs.readFileSync(schemaPath6, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql6);
      await client.query('INSERT INTO schema_migrations (version) VALUES (6)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 6 applied successfully! (Notification Platform)');
    } else {
      console.log('✅ Database is up to date (version 6).');
    }

    // Check if migration version 7 has been applied
    const res7 = await client.query('SELECT version FROM schema_migrations WHERE version = 7');
    if (res7.rows.length === 0) {
      console.log('Migration version 7 is not applied. Applying now...');
      
      const schemaPath7 = path.join(__dirname, '../db/schema_v7.sql');
      const schemaSql7 = fs.readFileSync(schemaPath7, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql7);
      await client.query('INSERT INTO schema_migrations (version) VALUES (7)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 7 applied successfully! (Production Hardening)');
    } else {
      console.log('✅ Database is up to date (version 7).');
    }

    // Check if migration version 8 has been applied
    const res8 = await client.query('SELECT version FROM schema_migrations WHERE version = 8');
    if (res8.rows.length === 0) {
      console.log('Migration version 8 is not applied. Applying now...');
      
      const schemaPath8 = path.join(__dirname, '../db/schema_v8.sql');
      const schemaSql8 = fs.readFileSync(schemaPath8, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql8);
      await client.query('INSERT INTO schema_migrations (version) VALUES (8)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 8 applied successfully! (Admin Operations & Hardening)');
    } else {
      console.log('✅ Database is up to date (version 8).');
    }

    // Check if migration version 9 has been applied
    const res9 = await client.query('SELECT version FROM schema_migrations WHERE version = 9');
    if (res9.rows.length === 0) {
      console.log('Migration version 9 is not applied. Applying now...');
      
      const schemaPath9 = path.join(__dirname, '../db/schema_v9.sql');
      const schemaSql9 = fs.readFileSync(schemaPath9, 'utf8');
      
      await client.query('BEGIN');
      await client.query(schemaSql9);
      await client.query('INSERT INTO schema_migrations (version) VALUES (9)');
      await client.query('COMMIT');
      
      console.log('✅ Migration version 9 applied successfully! (Password Reset Fields)');
    } else {
      console.log('✅ Database is up to date (version 9).');
    }

    // Check if migration version 10 has been applied
    const res10 = await client.query('SELECT version FROM schema_migrations WHERE version = 10');
    if (res10.rows.length === 0) {
      console.log('Migration version 10 is not applied. Applying now...');

      const schemaPath10 = path.join(__dirname, '../db/schema_v10.sql');
      const schemaSql10 = fs.readFileSync(schemaPath10, 'utf8');

      await client.query('BEGIN');
      await client.query(schemaSql10);
      await client.query('INSERT INTO schema_migrations (version) VALUES (10)');
      await client.query('COMMIT');

      console.log('✅ Migration version 10 applied successfully! (Audit Log Retention & Archive)');
    } else {
      console.log('✅ Database is up to date (version 10).');
    }

    // Check if migration version 11 has been applied
    const res11 = await client.query('SELECT version FROM schema_migrations WHERE version = 11');
    if (res11.rows.length === 0) {
      console.log('Migration version 11 is not applied. Applying now...');

      const schemaPath11 = path.join(__dirname, '../db/schema_v11.sql');
      const schemaSql11 = fs.readFileSync(schemaPath11, 'utf8');

      await client.query('BEGIN');
      await client.query(schemaSql11);
      await client.query('INSERT INTO schema_migrations (version) VALUES (11)');
      await client.query('COMMIT');

      console.log('✅ Migration version 11 applied successfully! (OTA App Releases Table)');
    } else {
      console.log('✅ Database is up to date (version 11).');
    }

    // Check if migration version 12 has been applied
    const res12 = await client.query('SELECT version FROM schema_migrations WHERE version = 12');
    if (res12.rows.length === 0) {
      console.log('Migration version 12 is not applied. Applying now...');

      const schemaPath12 = path.join(__dirname, '../db/schema_v12.sql');
      const schemaSql12 = fs.readFileSync(schemaPath12, 'utf8');

      // Index CONCURRENTLY cannot run inside a transaction block (BEGIN/COMMIT)
      // So we execute it directly on the client
      await client.query(schemaSql12);
      await client.query('INSERT INTO schema_migrations (version) VALUES (12)');

      console.log('✅ Migration version 12 applied successfully! (Performance Indexing)');
    } else {
      console.log('✅ Database is up to date (version 12).');
    }

    // Check if migration version 13 has been applied
    const res13 = await client.query('SELECT version FROM schema_migrations WHERE version = 13');
    if (res13.rows.length === 0) {
      console.log('Migration version 13 is not applied. Applying now...');

      const schemaPath13 = path.join(__dirname, '../db/schema_v13.sql');
      const schemaSql13 = fs.readFileSync(schemaPath13, 'utf8');

      await client.query('BEGIN');
      await client.query(schemaSql13);
      await client.query('INSERT INTO schema_migrations (version) VALUES (13)');
      await client.query('COMMIT');

      console.log('✅ Migration version 13 applied successfully! (Support Tickets + FSM Columns)');
    } else {
      console.log('✅ Database is up to date (version 13).');
    }

    // Check if migration version 14 has been applied
    const res14 = await client.query('SELECT version FROM schema_migrations WHERE version = 14');
    if (res14.rows.length === 0) {
      console.log('Migration version 14 is not applied. Applying now...');

      const schemaPath14 = path.join(__dirname, '../db/schema_v14.sql');
      const schemaSql14 = fs.readFileSync(schemaPath14, 'utf8');

      await client.query('BEGIN');
      await client.query(schemaSql14);
      await client.query('INSERT INTO schema_migrations (version) VALUES (14)');
      await client.query('COMMIT');

      console.log('✅ Migration version 14 applied successfully! (Branches + Sale FSM)');
    } else {
      console.log('✅ Database is up to date (version 14).');
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
    client.release();
  }
}
