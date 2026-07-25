import 'package:sqflite/sqflite.dart';

/// Enterprise Sync Engine v2 — Local SQLite Schema Definition
class SyncV2Schema {
  static const String tableOutbox = 'sync_outbox';
  static const String tableInbox = 'sync_inbox';
  static const String tableSyncState = 'sync_state';
  static const String tableMetadata = 'sync_metadata';

  static Future<void> createTables(Database db) async {
    // 1. Enable Write-Ahead Logging (WAL) and Foreign Keys
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA foreign_keys = ON;');

    // 2. Outbox Queue Table (Mutations waiting to be pushed)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableOutbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_mutation_id TEXT UNIQUE NOT NULL,
        tenant_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        domain TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        op_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        client_timestamp INTEGER NOT NULL,
        base_revision INTEGER NOT NULL,
        priority INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'PENDING',
        attempts INTEGER DEFAULT 0,
        last_error TEXT
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_status_priority ON $tableOutbox(status, priority ASC, id ASC);',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_outbox_mutation_id ON $tableOutbox(client_mutation_id);',
    );

    // 3. Inbox Table (Idempotency Tracking)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableInbox (
        client_mutation_id TEXT PRIMARY KEY,
        processed_at INTEGER NOT NULL
      );
    ''');

    // 4. Sync State Key-Value Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSyncState (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    // 5. Local Entity Metadata Tracking
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableMetadata (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        domain TEXT NOT NULL,
        local_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'SYNCED',
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (entity_type, entity_id)
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_metadata_domain ON $tableMetadata(domain, sync_status);',
    );
  }
}
