import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'sync_v2_schema.dart';

class SyncStateDao {
  final Database db;

  SyncStateDao(this.db);

  Future<void> setVector(String domain, int revision, {Transaction? txn}) async {
    final executor = txn ?? db;
    await executor.insert(
      SyncV2Schema.tableSyncState,
      {
        'key': 'vector_$domain',
        'value': revision.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getVector(String domain) async {
    final res = await db.query(
      SyncV2Schema.tableSyncState,
      where: 'key = ?',
      whereArgs: ['vector_$domain'],
      limit: 1,
    );
    if (res.isEmpty) return 0;
    return int.tryParse(res.first['value'] as String) ?? 0;
  }

  Future<Map<String, int>> getAllVectors() async {
    final res = await db.query(
      SyncV2Schema.tableSyncState,
      where: 'key LIKE ?',
      whereArgs: ['vector_%'],
    );
    final vectors = <String, int>{};
    for (final row in res) {
      final key = row['key'] as String;
      final domain = key.replaceFirst('vector_', '');
      vectors[domain] = int.tryParse(row['value'] as String) ?? 0;
    }
    return vectors;
  }
}
