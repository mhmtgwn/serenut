// lib/infrastructure/database/migration_manager.dart
// Serenut Platform — Database Migration and Rollback Manager
// Executes database schema upgrades, automatic backups, WAL checkpoints, and transaction-safe rollbacks.
// Created: 04 Jul 2026

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/backup_service.dart';

class MigrationStep {
  final int version;
  final List<String> sqlStatements;

  const MigrationStep({
    required this.version,
    required this.sqlStatements,
  });
}

class MigrationManager {
  final DatabaseManager _dbManager;
  final BackupService _backupService;
  final List<MigrationStep> _steps = [];

  MigrationManager({
    DatabaseManager? dbManager,
    BackupService? backupService,
  })  : _dbManager = dbManager ?? DatabaseManager(),
        _backupService = backupService ?? BackupService();

  /// Register a migration version step.
  void registerStep(MigrationStep step) {
    _steps.add(step);
    _steps.sort((a, b) => a.version.compareTo(b.version));
  }

  /// Initialize metadata table for migrations.
  Future<void> _initMigrationTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS migration_history_logs (
        id TEXT PRIMARY KEY,
        version INTEGER NOT NULL,
        status TEXT NOT NULL,
        applied_at TEXT NOT NULL,
        error_message TEXT
      )
    ''');
  }

  /// Gets the highest successfully applied version.
  Future<int> getCurrentAppliedVersion(Database db) async {
    await _initMigrationTable(db);
    final List<Map<String, dynamic>> res = await db.rawQuery('''
      SELECT MAX(version) as max_version 
      FROM migration_history_logs 
      WHERE status = 'success'
    ''');

    if (res.isEmpty || res.first['max_version'] == null) {
      return 0;
    }
    return res.first['max_version'] as int;
  }

  /// Runs all pending migrations.
  Future<void> runMigrations() async {
    final db = await _dbManager.getDatabase();
    await _initMigrationTable(db);

    final currentVer = await getCurrentAppliedVersion(db);
    final pendingSteps =
        _steps.where((step) => step.version > currentVer).toList();

    if (pendingSteps.isEmpty) {
      return; // Database up to date
    }

    for (final step in pendingSteps) {
      String? backupPath;
      try {
        // 1. Take a safe hot backup before executing migration
        backupPath = await _backupService.backupDatabase();
      } catch (e) {
        // Log backup failure and abort migration to be safe
        throw Exception(
            'Migration backup failed. Aborting migrations. Error: $e');
      }

      final logId = const Uuid().v4();
      try {
        // 2. Run migration statements in a single transaction block
        await db.transaction((txn) async {
          for (final statement in step.sqlStatements) {
            await txn.execute(statement);
          }

          // 3. Log success in history within the transaction
          await txn.insert('migration_history_logs', {
            'id': logId,
            'version': step.version,
            'status': 'success',
            'applied_at': DateTime.now().toIso8601String(),
            'error_message': null,
          });
        });
      } catch (e) {
        // 4. In case of failure, transaction automatically rolls back.
        // We log the error metadata separately.
        await db.insert('migration_history_logs', {
          'id': logId,
          'version': step.version,
          'status': 'failed',
          'applied_at': DateTime.now().toIso8601String(),
          'error_message': e.toString(),
        });

        // 5. Restore DB from physical backup file
        await _performPhysicalRollback(backupPath);

        rethrow;
      }
    }
  }

  /// Restores database file directly from physical backup on critical failures.
  Future<void> _performPhysicalRollback(String backupPath) async {
    final activeDbPath = DatabaseManager.overrideDatabasePath ??
        await _dbManager.getDatabasesPath();

    if (activeDbPath == ':memory:') {
      return; // Skip physical file rollback in memory tests
    }

    final activeDbFile = File(activeDbPath);
    final backupFile = File(backupPath);

    if (await backupFile.exists()) {
      // Release existing SQLite locks/spooler connections if possible
      final db = await _dbManager.getDatabase();
      await db.close();

      // Overwrite corrupt db with backup
      await backupFile.copy(activeDbFile.path);
    }
  }
}
