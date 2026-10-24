// core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart
import 'package:sqflite/sqflite.dart';
import '../../domain/models/core_entities.dart';
import '../../domain/models/money_cents.dart';
import '../../domain/services/ledger_service.dart';

class SqliteLedgerRepository implements ILedgerRepository {
  final DatabaseExecutor _db;

  const SqliteLedgerRepository(this._db);

  @override
  Future<CustomerEntity?> getCustomer(String customerId) async {
    final rows = await _db.query(
      'customers',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return CustomerEntity.fromMap(rows.first);
  }

  @override
  Future<void> updateCustomerBalance(
      String customerId, MoneyCents newBalance) async {
    await _db.update(
      'customers',
      {
        'balance_cents': newBalance.value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  @override
  Future<void> insertLedgerEntry(LedgerEntryEntity entry) async {
    await _db.insert(
      'ledger_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Belirli bir müşterinin tüm defter hareketlerini getirir (Ekstre)
  Future<List<LedgerEntryEntity>> getCustomerLedgerHistory(
      String customerId) async {
    final rows = await _db.query(
      'ledger_entries',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );

    return rows.map(LedgerEntryEntity.fromMap).toList();
  }
}
