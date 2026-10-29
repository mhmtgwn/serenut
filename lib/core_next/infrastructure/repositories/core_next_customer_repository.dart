// core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart
// SERENUT OS — STAGE 10.8.11
// Authoritative Core Next Customer Repository Bridge
// Implements ICustomerRepository over serenut_core_v2.db

import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/config/utils.dart';
import '../database/app_database.dart';
import '../sync/sync_v4_payload_adapter.dart';

class CoreNextCustomerRepository implements ICustomerRepository {
  final DatabaseExecutor _db;

  CoreNextCustomerRepository(this._db);

  factory CoreNextCustomerRepository.fromCoreAppDatabase(CoreAppDatabase coreDb) {
    return CoreNextCustomerRepository(coreDb.db);
  }

  static const String _debtTypesCondition =
      "(UPPER(REPLACE(le.entry_type, '_', '')) IN ('DEBITSALE', 'DEBT', 'MANUALDEBT', 'SALE', 'DEBITADJUSTMENT') "
      "OR UPPER(le.entry_type) IN ('DEBIT_SALE', 'DEBT', 'MANUAL_DEBT', 'SALE', 'DEBIT_ADJUSTMENT') "
      "OR le.entry_type IN ('debitSale', 'debitAdjustment'))";

  static const String _paymentTypesCondition =
      "(UPPER(REPLACE(entry_type, '_', '')) IN ('COLLECTION', 'PAYMENT', 'CREDITCOLLECTION', 'CREDITADJUSTMENT') "
      "OR UPPER(entry_type) IN ('COLLECTION', 'PAYMENT', 'CREDIT_COLLECTION', 'CREDIT_ADJUSTMENT') "
      "OR entry_type IN ('creditCollection', 'creditAdjustment'))";


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

  CustomerEntity _rowToEntity(Map<String, dynamic> row) {
    final balanceCents = (row['balance_cents'] as num?)?.toInt() ?? 0;
    final createdAtMs = _parseTimestamp(row['created_at']) ??
        _parseTimestamp(row['updated_at']) ??
        DateTime.now().millisecondsSinceEpoch;

    final oldestDebtMs = _parseTimestamp(row['oldest_debt_date']);
    final latestDebtMs = _parseTimestamp(row['latest_debt_date']);

    return CustomerEntity(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      address: row['notes']?.toString(), // Or address if column exists
      phone: row['phone']?.toString() ?? '',
      balance: balanceCents / 100.0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      oldestDebtDate: oldestDebtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(oldestDebtMs)
          : null,
      latestDebtDate: latestDebtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(latestDebtMs)
          : null,
    );
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90')) return digits.substring(2);
    if (digits.startsWith('0')) return digits.substring(1);
    return digits;
  }

  @override
  Future<List<CustomerEntity>> findAll() async {
    final rows = await _db.rawQuery('''
      SELECT c.*,
        (SELECT MIN(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS oldest_debt_date,
        (SELECT MAX(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS latest_debt_date
      FROM customers c
      WHERE c.is_deleted = 0 AND c.is_active = 1
      ORDER BY c.name COLLATE NOCASE ASC
    ''');
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<CustomerEntity?> findById(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return null;

    final rows = await _db.rawQuery('''
      SELECT c.*,
        (SELECT MIN(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS oldest_debt_date,
        (SELECT MAX(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS latest_debt_date
      FROM customers c
      WHERE c.id = ? AND c.is_deleted = 0
      LIMIT 1
    ''', [cleanId]);

    if (rows.isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  @override
  Future<List<CustomerEntity>> search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return findAll();

    final normPhone = _normalizePhone(clean);

    final rows = await _db.rawQuery('''
      SELECT c.*,
        (SELECT MIN(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS oldest_debt_date,
        (SELECT MAX(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS latest_debt_date
      FROM customers c
      WHERE (c.name LIKE ? OR c.phone LIKE ? OR (? != '' AND c.phone LIKE ?))
        AND c.is_deleted = 0 AND c.is_active = 1
      ORDER BY c.name COLLATE NOCASE ASC
      LIMIT 100
    ''', ['%$clean%', '%$clean%', normPhone, '%$normPhone%']);

    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<CustomerEntity>> findFiltered({
    String? searchQuery,
    CustomerBalanceFilter balanceFilter = CustomerBalanceFilter.all,
    CustomerSortOption sortOption = CustomerSortOption.nameAsc,
    int? limit,
    int? offset,
  }) async {
    final whereClauses = <String>['c.is_deleted = 0', 'c.is_active = 1'];
    final whereArgs = <dynamic>[];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final clean = searchQuery.trim();
      final normPhone = _normalizePhone(clean);
      final foldedCol = sqliteTurkishFold('c.name');
      final foldedName = clean.normalizeTurkish;
      whereClauses.add('($foldedCol LIKE ? OR c.phone LIKE ? OR (? != \'\' AND c.phone LIKE ?))');
      whereArgs.add('%$foldedName%');
      whereArgs.add('%$clean%');
      whereArgs.add(normPhone);
      whereArgs.add('%$normPhone%');
    }

    switch (balanceFilter) {
      case CustomerBalanceFilter.debt:
        whereClauses.add('c.balance_cents < 0');
        break;
      case CustomerBalanceFilter.credit:
        whereClauses.add('c.balance_cents > 0');
        break;
      case CustomerBalanceFilter.clear:
        whereClauses.add('c.balance_cents = 0');
        break;
      case CustomerBalanceFilter.all:
        break;
    }

    String orderClause = 'ORDER BY c.name COLLATE NOCASE ASC';
    switch (sortOption) {
      case CustomerSortOption.nameAsc:
        orderClause = 'ORDER BY c.name COLLATE NOCASE ASC';
        break;
      case CustomerSortOption.nameDesc:
        orderClause = 'ORDER BY c.name COLLATE NOCASE DESC';
        break;
      case CustomerSortOption.highestDebt:
        orderClause = 'ORDER BY c.balance_cents ASC'; // More negative = higher debt
        break;
      case CustomerSortOption.lowestDebt:
        orderClause = 'ORDER BY c.balance_cents DESC';
        break;
      case CustomerSortOption.oldestDebt:
        orderClause = 'ORDER BY oldest_debt_date ASC NULLS LAST';
        break;
      case CustomerSortOption.newestDebt:
        orderClause = 'ORDER BY latest_debt_date DESC NULLS LAST';
        break;
    }

    final limitClause = limit != null ? 'LIMIT $limit' : '';
    final offsetClause = offset != null ? 'OFFSET $offset' : '';

    final sql = '''
      SELECT c.*,
        (SELECT MIN(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS oldest_debt_date,
        (SELECT MAX(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS latest_debt_date
      FROM customers c
      WHERE ${whereClauses.join(' AND ')}
      $orderClause
      $limitClause $offsetClause
    ''';

    final rows = await _db.rawQuery(sql, whereArgs);
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<CustomerBalanceSummary> getBalanceSummary({String? searchQuery}) async {
    final whereClauses = <String>['is_deleted = 0', 'is_active = 1'];
    final whereArgs = <dynamic>[];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final clean = searchQuery.trim();
      final normPhone = _normalizePhone(clean);
      whereClauses.add('(name LIKE ? OR phone LIKE ? OR (? != \'\' AND phone LIKE ?))');
      whereArgs.add('%$clean%');
      whereArgs.add('%$clean%');
      whereArgs.add(normPhone);
      whereArgs.add('%$normPhone%');
    }

    final sql = '''
      SELECT
        COALESCE(SUM(CASE WHEN balance_cents < 0 THEN -balance_cents ELSE 0 END), 0) AS total_debt_cents,
        COALESCE(SUM(CASE WHEN balance_cents > 0 THEN balance_cents ELSE 0 END), 0) AS total_credit_cents,
        SUM(CASE WHEN balance_cents < 0 THEN 1 ELSE 0 END) AS debtor_count,
        SUM(CASE WHEN balance_cents > 0 THEN 1 ELSE 0 END) AS credit_count,
        SUM(CASE WHEN balance_cents = 0 THEN 1 ELSE 0 END) AS clear_count
      FROM customers
      WHERE ${whereClauses.join(' AND ')}
    ''';

    final rows = await _db.rawQuery(sql, whereArgs);
    if (rows.isEmpty) {
      return const CustomerBalanceSummary(
        totalDebt: 0.0,
        totalCredit: 0.0,
        debtorCount: 0,
        creditCount: 0,
        clearCount: 0,
      );
    }

    final first = rows.first;
    final totalDebtCents = (first['total_debt_cents'] as num?)?.toDouble() ?? 0.0;
    final totalCreditCents = (first['total_credit_cents'] as num?)?.toDouble() ?? 0.0;
    final debtorCount = (first['debtor_count'] as num?)?.toInt() ?? 0;
    final creditCount = (first['credit_count'] as num?)?.toInt() ?? 0;
    final clearCount = (first['clear_count'] as num?)?.toInt() ?? 0;

    return CustomerBalanceSummary(
      totalDebt: totalDebtCents / 100.0,
      totalCredit: totalCreditCents / 100.0,
      debtorCount: debtorCount,
      creditCount: creditCount,
      clearCount: clearCount,
    );
  }

  @override
  Future<List<CustomerEntity>> getDebtors() async {
    final rows = await _db.rawQuery('''
      SELECT c.*,
        (SELECT MIN(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS oldest_debt_date,
        (SELECT MAX(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS latest_debt_date
      FROM customers c
      WHERE c.balance_cents < 0 AND c.is_deleted = 0 AND c.is_active = 1
      ORDER BY c.balance_cents ASC
    ''');
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<CustomerEntity>> getWithCredit() async {
    final rows = await _db.rawQuery('''
      SELECT c.*,
        (SELECT MIN(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS oldest_debt_date,
        (SELECT MAX(le.created_at) FROM ledger_entries le
         WHERE le.customer_id = c.id AND $_debtTypesCondition
        ) AS latest_debt_date
      FROM customers c
      WHERE c.balance_cents > 0 AND c.is_deleted = 0 AND c.is_active = 1
      ORDER BY c.balance_cents DESC
    ''');
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<void> updateBalance(String customerId, double amount) async {
    final cleanId = customerId.trim();
    final balanceCents = (amount * 100).round();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.update(
      'customers',
      {
        'balance_cents': balanceCents,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [cleanId],
    );
  }

  @override
  Future<double> getBalance(String customerId) async {
    final cleanId = customerId.trim();
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
  Future<double> getTotalDebt(String customerId) async {
    final cleanId = customerId.trim();
    final rows = await _db.query(
      'customers',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [cleanId],
      limit: 1,
    );
    if (rows.isEmpty) return 0.0;
    final cents = (rows.first['balance_cents'] as num?)?.toInt() ?? 0;
    if (cents < 0) {
      return (-cents) / 100.0;
    }
    return 0.0;
  }

  @override
  Future<double> getTotalPaid(String customerId) async {
    final cleanId = customerId.trim();
    final res = await _db.rawQuery('''
      SELECT COALESCE(SUM(amount_cents), 0) as paid_cents
      FROM ledger_entries
      WHERE customer_id = ? AND $_paymentTypesCondition
    ''', [cleanId]);
    final cents = (res.first['paid_cents'] as num?)?.toDouble() ?? 0.0;
    return cents / 100.0;
  }

  @override
  Future<Map<String, String>> getLookupMap() async {
    final rows = await _db.query(
      'customers',
      columns: ['id', 'name'],
      where: "is_deleted = 0 AND id != ''",
    );
    return {
      for (final r in rows)
        if (r['id'] != null)
          (r['id'] as String): ((r['name'] as String?)?.toTurkishUpperCase ??
              'Bilinmeyen Müşteri'),
    };
  }

  @override
  Future<CustomerDuplicateCheckResult> checkDuplicates({
    required String name,
    required String phone,
    String? excludeId,
  }) async {
    final normName = name.trim().toLowerCase();
    final normPhone = _normalizePhone(phone.trim());

    if (normPhone.isEmpty && normName.isEmpty) {
      return const CustomerDuplicateCheckResult(
        status: CustomerDuplicateStatus.none,
      );
    }

    final whereClauses = <String>['is_deleted = 0'];
    final whereArgs = <dynamic>[];
    if (excludeId != null && excludeId.trim().isNotEmpty) {
      whereClauses.add('id != ?');
      whereArgs.add(excludeId.trim());
    }

    final rows = await _db.query(
      'customers',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
    );

    CustomerEntity? matchedCustomer;
    bool hasPhoneConflict = false;

    for (final r in rows) {
      final rName = (r['name']?.toString() ?? '').trim().toLowerCase();
      final rPhone = _normalizePhone(r['phone']?.toString() ?? '');

      if (normPhone.isNotEmpty && rPhone.isNotEmpty && normPhone == rPhone) {
        matchedCustomer = _rowToEntity(r);
        if (rName == normName) {
          return CustomerDuplicateCheckResult(
            status: CustomerDuplicateStatus.exactMatch,
            matchedCustomer: matchedCustomer,
          );
        } else {
          hasPhoneConflict = true;
        }
      }
    }

    if (hasPhoneConflict) {
      return CustomerDuplicateCheckResult(
        status: CustomerDuplicateStatus.phoneConflict,
        matchedCustomer: matchedCustomer,
      );
    }

    return const CustomerDuplicateCheckResult(
      status: CustomerDuplicateStatus.none,
    );
  }

  @override
  Future<int> create(CustomerEntity entity) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final balanceCents = (entity.balance * 100).round();
    final cleanId = entity.id.trim();

    await _db.insert(
      'customers',
      {
        'id': cleanId,
        'name': entity.name.trim(),
        'phone': entity.phone.trim(),
        'email': entity.email.trim(),
        'balance_cents': balanceCents,
        'notes': entity.address,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    try {
      final mutation = SyncV4PayloadAdapter.buildCustomerMutation(
        customerId: cleanId,
        name: entity.name,
        phone: entity.phone,
        email: entity.email,
        address: entity.address,
        balanceCents: balanceCents,
        isDeleted: false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        deterministicEventId: 'evt-cust-$cleanId-$now',
        operation: 'UPSERT',
      );
      await _db.insert(
        'sync_events',
        mutation.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      debugPrint('[CoreNextCustomerRepo] insert customer mutation error: $e');
    }

    return 1;
  }

  @override
  Future<int> update(CustomerEntity entity) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final balanceCents = (entity.balance * 100).round();
    final cleanId = entity.id.trim();

    // Bakiye (balance_cents) yalnızca defter hareketleri (ledger_entries) üzerinden güncellenir.
    // Müşteri profili düzenlenirken mevcut defter bakiyesi korunur.
    final currentRows = await _db.query(
      'customers',
      columns: ['balance_cents'],
      where: 'id = ?',
      whereArgs: [cleanId],
      limit: 1,
    );
    final authoritativeBalanceCents = currentRows.isNotEmpty
        ? ((currentRows.first['balance_cents'] as num?)?.toInt() ?? balanceCents)
        : balanceCents;

    final count = await _db.update(
      'customers',
      {
        'name': entity.name.trim(),
        'phone': entity.phone.trim(),
        'email': entity.email.trim(),
        'notes': entity.address,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [cleanId],
    );

    try {
      final mutation = SyncV4PayloadAdapter.buildCustomerMutation(
        customerId: cleanId,
        name: entity.name,
        phone: entity.phone,
        email: entity.email,
        address: entity.address,
        balanceCents: authoritativeBalanceCents,
        isDeleted: false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        deterministicEventId: 'evt-cust-$cleanId-$now',
        operation: 'UPSERT',
      );
      await _db.insert(
        'sync_events',
        mutation.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      debugPrint('[CoreNextCustomerRepo] insert customer mutation error: $e');
    }

    return count;
  }

  @override
  Future<int> delete(String id) async {
    final cleanId = id.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = await _db.update(
      'customers',
      {
        'is_deleted': 1,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [cleanId],
    );

    try {
      final mutation = SyncV4PayloadAdapter.buildCustomerMutation(
        customerId: cleanId,
        name: cleanId,
        isDeleted: true,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        deterministicEventId: 'evt-cust-del-$cleanId-$now',
        operation: 'DELETE',
      );
      await _db.insert(
        'sync_events',
        mutation.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      debugPrint('[CoreNextCustomerRepo] insert customer mutation error: $e');
    }

    return count;
  }

  @override
  Future<bool> exists(String id) async {
    final cleanId = id.trim();
    final rows = await _db.query(
      'customers',
      columns: ['id'],
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [cleanId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<int> count() async {
    final res = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM customers WHERE is_deleted = 0 AND is_active = 1',
    );
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }
}
