// core_next/client_core/lib/infrastructure/repositories/core_next_financial_transaction_repository.dart
// SERENUT OS — STAGE 10.8.11
// Authoritative Core Next Financial Transaction & Ledger Repository Bridge
// Implements IFinancialTransactionRepository over serenut_core_v2.db

import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import '../database/app_database.dart';
import '../sync/sync_v4_payload_adapter.dart';
import '../../domain/models/money_cents.dart';

class CoreNextFinancialTransactionRepository
    implements IFinancialTransactionRepository {
  final DatabaseExecutor _db;

  CoreNextFinancialTransactionRepository(this._db);

  factory CoreNextFinancialTransactionRepository.fromCoreAppDatabase(
      CoreAppDatabase coreDb) {
    return CoreNextFinancialTransactionRepository(coreDb.db);
  }

  static int? _parseTimestamp(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is String) {
      final parsedNum = int.tryParse(val);
      if (parsedNum != null) return parsedNum;
      final parsedDate = DateTime.tryParse(val);
      if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
    }
    return null;
  }

  FinancialTransactionEntity _rowToEntity(Map<String, dynamic> row) {
    final amountCents = (row['amount_cents'] as num?)?.toInt() ?? 0;
    final balanceAfterCents = (row['balance_after_cents'] as num?)?.toInt() ?? 0;
    final createdAtMs = _parseTimestamp(row['created_at']) ??
        DateTime.now().millisecondsSinceEpoch;
    final entryType = (row['entry_type'] ?? 'payment').toString().toUpperCase();
    final hasSaleRef = row['reference_sale_id'] != null && row['reference_sale_id'].toString().trim().isNotEmpty;

    final isPayment = entryType.contains('PAYMENT') ||
        entryType.contains('COLLECTION') ||
        entryType.contains('CREDIT');
    final isDebt = entryType.contains('DEBIT') ||
        entryType.contains('SALE') ||
        entryType.contains('BORC');

    final amount = amountCents / 100.0;
    final paidAmount = isPayment ? amount : 0.0;
    final debtAmount = isDebt ? amount : 0.0;

    String mappedType = 'payment';
    if (entryType.contains('COLLECTION')) {
      mappedType = 'collection';
    } else if (entryType.contains('SALE') || hasSaleRef) {
      mappedType = 'sale';
    } else if (entryType.contains('REFUND')) {
      mappedType = 'refund';
    } else if (entryType.contains('CANCEL')) {
      mappedType = 'cancellation';
    } else if (entryType.contains('DEBIT') || entryType.contains('BORC') || entryType == 'DEBT') {
      mappedType = 'manual_debt';
    }

    return FinancialTransactionEntity(
      id: row['id']?.toString() ?? '',
      type: mappedType,
      customerId: row['customer_id']?.toString() ?? '',
      amount: amount,
      paidAmount: paidAmount,
      debtAmount: debtAmount,
      date: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      referenceId: row['reference_sale_id']?.toString(),
      metadata: {
        'description': row['description'],
        'balance_after': balanceAfterCents / 100.0,
      },
      logicalClock: createdAtMs,
    );
  }

  @override
  Future<List<FinancialTransactionEntity>> findAll() async {
    final rows = await _db.query(
      'ledger_entries',
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<FinancialTransactionEntity?> findById(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return null;
    final rows = await _db.query(
      'ledger_entries',
      where: 'id = ?',
      whereArgs: [cleanId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  @override
  Future<List<FinancialTransactionEntity>> getByCustomerId(
      String customerId) async {
    final cleanId = customerId.trim();
    if (cleanId.isEmpty) return [];
    final rows = await _db.query(
      'ledger_entries',
      where: 'customer_id = ?',
      whereArgs: [cleanId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<FinancialTransactionEntity>> getByType(String type) async {
    final clean = type.trim().toUpperCase();
    final String queryPattern;
    if (clean == 'DEBT' || clean == 'MANUAL_DEBT') {
      queryPattern = '%DEB%';
    } else {
      queryPattern = '%$clean%';
    }
    final rows = await _db.query(
      'ledger_entries',
      where: 'entry_type LIKE ?',
      whereArgs: [queryPattern],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<FinancialTransactionEntity>> getByDateRange(
      DateTime from, DateTime to) async {
    final rows = await _db.query(
      'ledger_entries',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [
        from.millisecondsSinceEpoch,
        to.millisecondsSinceEpoch,
      ],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<double> getBalance(String customerId) async {
    final cleanId = customerId.trim();
    if (cleanId.isEmpty) return 0.0;
    final rows = await _db.query(
      'customers',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [cleanId],
      limit: 1,
    );
    if (rows.isEmpty) return 0.0;
    final cents = (rows.first['balance_cents'] as num?)?.toInt() ?? 0;
    return cents / 100.0;
  }

  @override
  Future<int> getMaxLogicalClock() async {
    final res = await _db.rawQuery(
      'SELECT MAX(created_at) as max_clock FROM ledger_entries',
    );
    return (res.first['max_clock'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<bool> existsByReferenceId(String referenceId, String type) async {
    final clean = referenceId.trim();
    if (clean.isEmpty) return false;
    final cleanType = type.trim().toUpperCase();
    final rows = await _db.rawQuery(
      '''
      SELECT 1 FROM ledger_entries
      WHERE reference_sale_id = ? AND entry_type LIKE ?
      LIMIT 1
      ''',
      [clean, '%$cleanType%'],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<FinancialTransactionEntity>> getByReferenceId(
      String referenceId) async {
    final clean = referenceId.trim();
    if (clean.isEmpty) return [];
    final rows = await _db.query(
      'ledger_entries',
      where: 'reference_sale_id = ?',
      whereArgs: [clean],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<int> updateOrderSaleTransaction({
    required String orderId,
    required String customerId,
    required double amount,
    required double paidAmount,
    required double debtAmount,
  }) async {
    // In-place update of order sale transaction
    final cleanOrderId = orderId.trim();
    final cleanCustId = customerId.trim();
    final debtCents = (debtAmount * 100).round();
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await _db.query(
      'ledger_entries',
      where: 'reference_sale_id = ?',
      whereArgs: [cleanOrderId],
      limit: 1,
    );

    if (existing.isEmpty) {
      return 0;
    }

    return await _db.update(
      'ledger_entries',
      {
        'customer_id': cleanCustId,
        'amount_cents': debtCents,
        'created_at': now,
      },
      where: 'reference_sale_id = ?',
      whereArgs: [cleanOrderId],
    );
  }

  @override
  Future<int> create(FinancialTransactionEntity entity) async {
    final cleanId = entity.id.trim();
    final cleanCustId = entity.customerId.trim();
    final now = entity.date.millisecondsSinceEpoch;
    final typeUpper = entity.type.trim().toUpperCase();

    // Idempotency: avoid double processing if same ID or reference already processed
    final existing = await _db.query(
      'ledger_entries',
      where: 'id = ?',
      whereArgs: [cleanId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return 1; // Idempotent no-op
    }

    // Determine financial impact adhering to v_customer_ledger_effect canonical semantics:
    // Positive balance = credit (alacak), Negative balance = debt (borç).
    // A sale with debt decreases balance (moves balance towards negative).
    // A collection/payment increases balance (moves balance towards positive).
    // A cancellation restores the debt previously incurred by the sale (increases balance).
    // A refund credits money back to the customer's account (increases balance).
    final int amountCents;
    final String entryType;
    final int balanceDeltaCents;

    if (typeUpper == 'SALE' || typeUpper == 'MANUAL_DEBT' || typeUpper == 'DEBT') {
      final int debtCents = entity.debtAmount > 0
          ? (entity.debtAmount * 100).round()
          : ((entity.amount - entity.paidAmount) * 100).round().clamp(0, (entity.amount * 100).round());
      if (debtCents > 0) {
        amountCents = debtCents;
        entryType = 'DEBIT';
        balanceDeltaCents = -debtCents;
      } else {
        amountCents = (entity.amount * 100).round();
        entryType = 'SALE_PAID';
        balanceDeltaCents = 0;
      }
    } else if (typeUpper == 'COLLECTION' || typeUpper == 'PAYMENT') {
      final int paidCents = entity.paidAmount > 0
          ? (entity.paidAmount * 100).round()
          : (entity.amount * 100).round();
      amountCents = paidCents;
      entryType = 'COLLECTION';
      balanceDeltaCents = paidCents;
    } else if (typeUpper == 'CANCELLATION') {
      final int debtToReverse = entity.debtAmount > 0
          ? (entity.debtAmount * 100).round()
          : ((entity.amount - entity.paidAmount) * 100).round().clamp(0, (entity.amount * 100).round());
      amountCents = (entity.amount * 100).round();
      entryType = 'CANCELLATION';
      balanceDeltaCents = debtToReverse;
    } else if (typeUpper == 'REFUND') {
      final int refundCents = (entity.amount * 100).round();
      amountCents = refundCents;
      entryType = 'REFUND';
      balanceDeltaCents = refundCents;
    } else {
      amountCents = (entity.amount * 100).round();
      entryType = typeUpper;
      balanceDeltaCents = 0;
    }

    // Fetch customer's current balance
    final custRows = await _db.query(
      'customers',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [cleanCustId],
      limit: 1,
    );

    final currentBalCents = custRows.isNotEmpty
        ? ((custRows.first['balance_cents'] as num?)?.toInt() ?? 0)
        : 0;

    final int newBalCents = currentBalCents + balanceDeltaCents;

    final desc = entity.metadata?['notes']?.toString() ??
        (entryType == 'COLLECTION'
            ? 'Tahsilat'
            : (entryType == 'CANCELLATION'
                ? 'Sipariş / Satış İptali'
                : (entryType == 'REFUND' ? 'İade' : 'Finansal Hareket')));

    await _db.insert(
      'ledger_entries',
      {
        'id': cleanId,
        'customer_id': cleanCustId,
        'reference_sale_id': entity.referenceId,
        'entry_type': entryType,
        'amount_cents': amountCents,
        'balance_after_cents': newBalCents,
        'description': desc,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // Update customer's balance
    if (cleanCustId.isNotEmpty) {
      await _db.update(
        'customers',
        {
          'balance_cents': newBalCents,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [cleanCustId],
      );
    }

    // Sync outbox queue
    try {
      // Negatif tutarlı finansal hareketler Sync V4 protokolü gereği sunucuya gönderilemez (Fail-Closed).
      // Bu tür kayıtlar (örn. taksit satır düzeltmeleri) yerelde korunur, sunucuya gönderilmez.
      final totalCents = (entity.amount * 100).round();
      final paidCents = (entity.paidAmount * 100).round();
      final debtCents = (entity.debtAmount * 100).round();

      if (totalCents > 0 &&
          entity.amount >= 0 &&
          entity.paidAmount >= 0 &&
          entity.debtAmount >= 0) {
        final finMutation = SyncV4PayloadAdapter.buildFinancialMutation(
          id: cleanId,
          type: entity.type,
          customerId: cleanCustId,
          total: MoneyCents(totalCents),
          paid: MoneyCents(paidCents),
          debt: MoneyCents(debtCents),
          referenceId: entity.referenceId,
          paymentMethod: entity.paymentMethod,
          description: desc,
          createdAt: entity.date,
          deterministicEventId: 'evt-ft-$cleanId-$now',
        );

        await _db.insert(
          'sync_events',
          finMutation.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    } catch (_) {}

    return 1;
  }

  @override
  Future<int> update(FinancialTransactionEntity entity) async {
    // Ledger entries are immutable by design; no-op or re-fetch
    return 1;
  }

  @override
  Future<int> delete(String id) async {
    final cleanId = id.trim();
    return _db.delete('ledger_entries', where: 'id = ?', whereArgs: [cleanId]);
  }

  @override
  Future<bool> exists(String id) async {
    final cleanId = id.trim();
    final rows = await _db.query(
      'ledger_entries',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [cleanId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<int> count() async {
    final res = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM ledger_entries',
    );
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }
}
