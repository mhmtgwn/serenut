import 'package:sqflite/sqflite.dart';
import 'sync_v2_schema.dart';

class InboxDao {
  final Database db;

  InboxDao(this.db);

  Future<void> markProcessed(String clientMutationId, {Transaction? txn}) async {
    final executor = txn ?? db;
    await executor.insert(
      SyncV2Schema.tableInbox,
      {
        'client_mutation_id': clientMutationId,
        'processed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<bool> isProcessed(String clientMutationId) async {
    final res = await db.query(
      SyncV2Schema.tableInbox,
      where: 'client_mutation_id = ?',
      whereArgs: [clientMutationId],
      limit: 1,
    );
    return res.isNotEmpty;
  }
}
