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

  static final RegExp _ftAmountsTagRegex = RegExp(
    r'\s*\[ft:total=(-?\d+),paid=(-?\d+),debt=(-?\d+)\]$',
  );

  FinancialTransactionEntity _rowToEntity(Map<String, dynamic> row) {
    final amountCents = (row['amount_cents'] as num?)?.toInt() ?? 0;
    final balanceAfterCents = (row['balance_after_cents'] as num?)?.toInt() ?? 0;
    final createdAtMs = _parseTimestamp(row['created_at']) ??
        DateTime.now().millisecondsSinceEpoch;
    final entryType = (row['entry_type'] ?? 'payment').toString().toUpperCase();
    final hasSaleRef = row['reference_sale_id'] != null &&
        row['reference_sale_id'].toString().trim().isNotEmpty;
    final rawDesc = row['description']?.toString() ?? '';

    String mappedType = 'payment';
    if (entryType.contains('CANCEL')) {
      mappedType = 'cancellation';
    } else if (entryType.contains('REFUND')) {
      mappedType = 'refund';
    } else if (entryType.contains('COLLECTION')) {
      mappedType = 'collection';
    } else if (entryType.contains('PAYMENT') || entryType.contains('CREDIT')) {
      mappedType = 'payment';
    } else if (entryType.contains('SALE') || hasSaleRef) {
      mappedType = 'sale';
    } else if (entryType.contains('DEBIT') ||
        entryType.contains('BORC') ||
        entryType.contains('DEBT')) {
      mappedType = 'manual_debt';
    }

    double amount = amountCents / 100.0;
    double paidAmount = 0.0;
    double debtAmount = 0.0;

    final tagMatch = _ftAmountsTagRegex.firstMatch(rawDesc);
    if (tagMatch != null) {
      amount = int.parse(tagMatch.group(1)!) / 100.0;
      paidAmount = int.parse(tagMatch.group(2)!) / 100.0;
      debtAmount = int.parse(tagMatch.group(3)!) / 100.0;
    } else if (entryType == 'SALE_PAID') {
      paidAmount = amount;
      debtAmount = 0.0;
    } else if (mappedType == 'cancellation') {
      paidAmount = 0.0;
      debtAmount = amount;
    } else if (mappedType == 'refund') {
      paidAmount = entryType == 'REFUND_CASH' ? amount : 0.0;
      debtAmount = 0.0;
    } else if (mappedType == 'collection' || mappedType == 'payment') {
      paidAmount = amount;
      debtAmount = 0.0;
    } else if (mappedType == 'sale' || mappedType == 'manual_debt') {
      paidAmount = 0.0;
      debtAmount = amount;
    }

    final cleanDesc = tagMatch != null
        ? rawDesc.substring(0, tagMatch.start)
        : row['description'];

    final rawCustId = row['customer_id']?.toString() ?? '';
    return FinancialTransactionEntity(
      id: row['id']?.toString() ?? '',
      type: mappedType,
      customerId: rawCustId == 'walkin-customer' ? '' : rawCustId,
      amount: amount,
      paidAmount: paidAmount,
      debtAmount: debtAmount,
      date: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      referenceId: row['reference_sale_id']?.toString(),
      metadata: {
        'description': cleanDesc,
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
    final totalCents = (amount * 100).round();
    final paidCents = (paidAmount * 100).round();
    final debtCents = (debtAmount * 100).round();
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await _db.query(
      'ledger_entries',
      where:
          "reference_sale_id = ? AND UPPER(entry_type) IN ('DEBIT', 'SALE_PAID', 'SALE', 'DEBIT_SALE')",
      whereArgs: [cleanOrderId],
      limit: 1,
    );

    if (existing.isEmpty) {
      return 0;
    }

    final prevRow = existing.first;
    final prevEntity = _rowToEntity(prevRow);
    final prevCustId = prevEntity.customerId.trim();
    final prevDebtCents = (prevEntity.debtAmount * 100).round();

    if (prevCustId.isNotEmpty && prevDebtCents != 0) {
      final prevCustRows = await _db.query(
        'customers',
        columns: ['balance_cents'],
        where: 'id = ?',
        whereArgs: [prevCustId],
        limit: 1,
      );
      if (prevCustRows.isNotEmpty) {
        final oldBal = (prevCustRows.first['balance_cents'] as num?)?.toInt() ?? 0;
        await _db.update(
          'customers',
          {
            'balance_cents': oldBal + prevDebtCents,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [prevCustId],
        );
      }
    }

    int newBalCents = 0;
    final effectiveCustId =
        cleanCustId.isNotEmpty ? cleanCustId : 'walkin-customer';
    final newCustRows = await _db.query(
      'customers',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [effectiveCustId],
      limit: 1,
    );
    if (newCustRows.isEmpty) {
      await _db.insert(
        'customers',
        {
          'id': effectiveCustId,
          'name': cleanCustId.isNotEmpty
              ? 'Müşteri ($cleanCustId)'
              : 'Misafir Müşteri',
          'balance_cents': 0,
          'credit_limit_cents': 0,
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    if (cleanCustId.isNotEmpty) {
      final currentBal = newCustRows.isNotEmpty
          ? ((newCustRows.first['balance_cents'] as num?)?.toInt() ?? 0)
          : 0;
      newBalCents = currentBal - debtCents;
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

    final newEntryType = debtCents > 0 ? 'DEBIT' : 'SALE_PAID';
    final newAmountCents = debtCents > 0 ? debtCents : totalCents;
    final baseDesc = 'Sipariş Revizyonu: $cleanOrderId';
    final taggedDesc = (paidCents > 0 && debtCents > 0)
        ? '$baseDesc [ft:total=$totalCents,paid=$paidCents,debt=$debtCents]'
        : baseDesc;

    return await _db.update(
      'ledger_entries',
      {
        'customer_id': effectiveCustId,
        'entry_type': newEntryType,
        'amount_cents': newAmountCents,
        'balance_after_cents': newBalCents,
        'description': taggedDesc,
        'created_at': now,
      },
      where: 'id = ?',
      whereArgs: [prevRow['id']],
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
    final int totalCents = (entity.amount * 100).round();
    final int paidCents = (entity.paidAmount * 100).round();

    if (typeUpper == 'SALE' || typeUpper == 'MANUAL_DEBT' || typeUpper == 'DEBT') {
      final int debtCents = entity.debtAmount != 0
          ? (entity.debtAmount * 100).round()
          : ((entity.amount - entity.paidAmount) * 100).round().clamp(0, totalCents);
      if (debtCents != 0) {
        amountCents = debtCents;
        entryType = 'DEBIT';
        balanceDeltaCents = -debtCents;
      } else {
        amountCents = totalCents;
        entryType = 'SALE_PAID';
        balanceDeltaCents = 0;
      }
    } else if (typeUpper == 'COLLECTION' || typeUpper == 'PAYMENT') {
      final int effectivePaidCents = paidCents > 0 ? paidCents : totalCents;
      amountCents = effectivePaidCents;
      entryType = typeUpper == 'PAYMENT' ? 'PAYMENT' : 'COLLECTION';
      balanceDeltaCents = effectivePaidCents;
    } else if (typeUpper == 'CANCELLATION') {
      final int debtToReverse = entity.debtAmount > 0
          ? (entity.debtAmount * 100).round()
          : ((entity.amount - entity.paidAmount) * 100).round().clamp(0, totalCents);
      amountCents = debtToReverse;
      entryType = 'CANCELLATION';
      balanceDeltaCents = debtToReverse;
    } else if (typeUpper == 'REFUND') {
      final int refundCents = totalCents;
      amountCents = refundCents;
      if (paidCents > 0) {
        entryType = 'REFUND_CASH';
        balanceDeltaCents = 0;
      } else {
        entryType = 'REFUND';
        balanceDeltaCents = refundCents;
      }
    } else {
      amountCents = totalCents;
      entryType = typeUpper;
      balanceDeltaCents = 0;
    }

    final effectiveCustId =
        cleanCustId.isNotEmpty ? cleanCustId : 'walkin-customer';

    // Fetch customer's current balance
    final custRows = await _db.query(
      'customers',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [effectiveCustId],
      limit: 1,
    );

    if (custRows.isEmpty) {
      await _db.insert(
        'customers',
        {
          'id': effectiveCustId,
          'name': cleanCustId.isNotEmpty
              ? 'Müşteri ($cleanCustId)'
              : 'Misafir Müşteri',
          'balance_cents': 0,
          'credit_limit_cents': 0,
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final currentBalCents = custRows.isNotEmpty
        ? ((custRows.first['balance_cents'] as num?)?.toInt() ?? 0)
        : 0;

    final int newBalCents = currentBalCents + balanceDeltaCents;

    final baseDesc = entity.metadata?['notes']?.toString() ??
        (entryType == 'COLLECTION' || entryType == 'PAYMENT'
            ? 'Tahsilat'
            : (entryType == 'CANCELLATION'
                ? 'Sipariş / Satış İptali'
                : (entryType.startsWith('REFUND') ? 'İade' : 'Finansal Hareket')));
    final int effectiveDebtCents = entity.debtAmount != 0
        ? (entity.debtAmount * 100).round()
        : ((entity.amount - entity.paidAmount) * 100).round().clamp(0, totalCents);
    final bool needsAmountsTag =
        (typeUpper == 'SALE' && paidCents > 0 && effectiveDebtCents > 0) ||
        (typeUpper == 'CANCELLATION' && totalCents != effectiveDebtCents);
    final storedDesc = needsAmountsTag
        ? '$baseDesc [ft:total=$totalCents,paid=$paidCents,debt=$effectiveDebtCents]'
        : baseDesc;

    await _db.insert(
      'ledger_entries',
      {
        'id': cleanId,
        'customer_id': effectiveCustId,
        'reference_sale_id': entity.referenceId,
        'entry_type': entryType,
        'amount_cents': amountCents,
        'balance_after_cents': newBalCents,
        'description': storedDesc,
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
          description: baseDesc,
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

