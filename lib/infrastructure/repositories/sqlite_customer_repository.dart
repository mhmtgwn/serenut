import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

class SqliteCustomerRepository implements ICustomerRepository {
  final DbGateway _gateway;

  SqliteCustomerRepository(this._gateway);

  DbExecutor get _executor => _gateway;

  @override
  Future<List<CustomerEntity>> findAll() async {
    final rows =
        await _executor.query('customers', where: "is_active = 1 AND id != ''");
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
  }

  @override
  Future<Map<String, String>> getLookupMap() async {
    final rows = await _executor.query(
      'customers',
      columns: ['id', 'name'],
      where: "id != ''",
    );
    return {
      for (final r in rows)
        if (r['id'] != null)
          (r['id'] as String): ((r['name'] as String?)?.toTurkishUpperCase ??
              'Bilinmeyen Müşteri'),
    };
  }

  @override
  Future<CustomerEntity?> findById(String id) async {
    final rows = await _executor.rawQuery('''
      SELECT c.*,
        (SELECT MIN(ft.created_at) FROM financial_transactions ft
         WHERE ft.customer_id = c.id
           AND ft.debt_amount > 0
           AND COALESCE(ft.is_deleted, 0) = 0) AS oldest_debt_date,
        (SELECT MAX(ft.created_at) FROM financial_transactions ft
         WHERE ft.customer_id = c.id
           AND ft.debt_amount > 0
           AND COALESCE(ft.is_deleted, 0) = 0) AS latest_debt_date
      FROM customers c
      WHERE c.id = ? AND c.is_active = 1
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return CustomerEntity.fromMap(rows.first);
  }

  @override
  Future<int> create(CustomerEntity entity) async {
    return _gateway.transaction(() async {
      final payload = {
        ...entity.toMap(),
        'is_synced': 0,
        'normalized_name': entity.name.normalizeTurkish,
        'normalized_email': entity.email.toLowerCase(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final result = await _executor.insert('customers', payload);
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'customer',
          entityId: entity.id,
          operation: 'UPSERT',
          payload: payload);
      return result;
    });
  }

  @override
  Future<int> update(CustomerEntity entity) async {
    return _gateway.transaction(() async {
      final payload = {
        ...entity.toMap(),
        'is_synced': 0,
        'normalized_name': entity.name.normalizeTurkish,
        'normalized_email': entity.email.toLowerCase(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      // Append-only bakiye güvencesi: Müşteri profil/iletişim güncellemeleri
      // defter bakiyesini asla ezemez!
      payload.remove('balance');
      payload.remove('balance_minor');
      payload.remove('created_at');
      payload.remove('id');

      final result = await _executor.update('customers', payload,
          where: 'id = ?', whereArgs: [entity.id]);
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'customer',
          entityId: entity.id,
          operation: 'UPSERT',
          payload: {
            'id': entity.id,
            ...payload,
          });
      return result;
    });
  }

  @override
  Future<int> delete(String id) async {
    if (id.isEmpty) return 0;
    return _gateway.transaction(() async {
      final payload = {
        'is_active': 0,
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
      };
      final result = await _executor
          .update('customers', payload, where: 'id = ?', whereArgs: [id]);
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'customer',
          entityId: id.toString(),
          operation: 'DELETE',
          payload: payload);
      return result;
    });
  }

  @override
  Future<int> count() async {
    final result = await _executor.rawQuery(
      "SELECT COUNT(*) as count FROM customers WHERE is_active = 1 AND id != ''",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<bool> exists(String id) async {
    final result = await _executor.query(
      'customers',
      where: 'id = ? AND is_active = 1',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  String _normalizeTurkish(String text) {
    return text.normalizeTurkish;
  }

  @override
  Future<List<CustomerEntity>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final normalizedQuery = _normalizeTurkish(query.trim());
    final rows = await _legacyNormalizedSearch(normalizedQuery);
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
  }

  @override
  Future<List<CustomerEntity>> findFiltered({
    String? searchQuery,
    CustomerBalanceFilter balanceFilter = CustomerBalanceFilter.all,
    CustomerSortOption sortOption = CustomerSortOption.nameAsc,
    int? limit,
    int? offset,
  }) async {
    final limitClause = limit != null ? ' LIMIT $limit' : '';
    final offsetClause = offset != null ? ' OFFSET $offset' : '';

    if (searchQuery == null || searchQuery.trim().isEmpty) {
      final rows = await _executor.rawQuery('''
        SELECT c.*,
          (SELECT MIN(ft.created_at) FROM financial_transactions ft
           WHERE ft.customer_id = c.id
             AND ft.debt_amount > 0
             AND COALESCE(ft.is_deleted, 0) = 0) AS oldest_debt_date,
          (SELECT MAX(ft.created_at) FROM financial_transactions ft
           WHERE ft.customer_id = c.id
             AND ft.debt_amount > 0
             AND COALESCE(ft.is_deleted, 0) = 0) AS latest_debt_date
        FROM customers c
        WHERE c.is_active = 1 AND c.id != ''${_balanceWhere(balanceFilter, prefix: 'c.')}
        ORDER BY ${_orderBy(sortOption)}
        $limitClause$offsetClause
      ''');
      return rows.map((row) => CustomerEntity.fromMap(row)).toList();
    }

    final normalizedQuery = _normalizeTurkish(searchQuery.trim());

    // Normalize phone input: strip non-digits, country code, and leading zeros
    final phoneDigits = normalizedQuery.replaceAll(RegExp(r'\D'), '');
    String cleanPhone = phoneDigits;
    if (cleanPhone.startsWith('90')) {
      cleanPhone = cleanPhone.substring(2);
    } else if (cleanPhone.startsWith('0')) {
      cleanPhone = cleanPhone.substring(1);
    }

    final matches = (await _legacyNormalizedSearch(
      normalizedQuery,
      normalizedPhone: cleanPhone,
    ))
        .where((row) => _matchesBalance(row, balanceFilter))
        .toList(growable: true);

    _sortRowMatches(matches, sortOption, normalizedQuery);

    final start = (offset ?? 0).clamp(0, matches.length);
    final end = limit == null
        ? matches.length
        : (start + limit).clamp(start, matches.length);
    final rows = matches.sublist(start, end);
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
  }

  @override
  Future<CustomerBalanceSummary> getBalanceSummary(
      {String? searchQuery}) async {
    if (searchQuery == null || searchQuery.trim().isEmpty) {
      final rows = await _executor.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN balance < -0.009 THEN -balance ELSE 0 END), 0) AS total_debt,
          COALESCE(SUM(CASE WHEN balance > 0.009 THEN balance ELSE 0 END), 0) AS total_credit,
          SUM(CASE WHEN balance < -0.009 THEN 1 ELSE 0 END) AS debtor_count,
          SUM(CASE WHEN balance > 0.009 THEN 1 ELSE 0 END) AS credit_count,
          SUM(CASE WHEN ABS(balance) <= 0.009 THEN 1 ELSE 0 END) AS clear_count
        FROM customers WHERE is_active = 1 AND id != ''
      ''');
      final row = rows.first;
      return CustomerBalanceSummary(
        totalDebt: (row['total_debt'] as num?)?.toDouble() ?? 0,
        totalCredit: (row['total_credit'] as num?)?.toDouble() ?? 0,
        debtorCount: (row['debtor_count'] as num?)?.toInt() ?? 0,
        creditCount: (row['credit_count'] as num?)?.toInt() ?? 0,
        clearCount: (row['clear_count'] as num?)?.toInt() ?? 0,
      );
    }
    final rows = await _legacyNormalizedSearch(
      _normalizeTurkish(searchQuery.trim()),
      normalizedPhone: _normalizedPhone(searchQuery),
    );
    return _summaryFromRows(rows);
  }

  static String _balanceWhere(CustomerBalanceFilter filter,
          {String prefix = ''}) =>
      switch (filter) {
        CustomerBalanceFilter.debt => ' AND ${prefix}balance < -0.009',
        CustomerBalanceFilter.credit => ' AND ${prefix}balance > 0.009',
        CustomerBalanceFilter.clear => ' AND ABS(${prefix}balance) <= 0.009',
        CustomerBalanceFilter.all => '',
      };

  static String _orderBy(CustomerSortOption sortOption) => switch (sortOption) {
        CustomerSortOption.nameAsc => 'c.normalized_name ASC, c.name ASC',
        CustomerSortOption.nameDesc => 'c.normalized_name DESC, c.name DESC',
        CustomerSortOption.oldestDebt =>
          'CASE WHEN c.balance < -0.009 AND oldest_debt_date IS NOT NULL THEN 0 ELSE 1 END, oldest_debt_date ASC, c.balance ASC',
        CustomerSortOption.newestDebt =>
          'CASE WHEN c.balance < -0.009 AND latest_debt_date IS NOT NULL THEN 0 ELSE 1 END, latest_debt_date DESC, c.balance ASC',
        CustomerSortOption.highestDebt =>
          'CASE WHEN c.balance < -0.009 THEN 0 ELSE 1 END, c.balance ASC',
        CustomerSortOption.lowestDebt =>
          'CASE WHEN c.balance < -0.009 THEN 0 ELSE 1 END, c.balance DESC',
      };

  static void _sortRowMatches(
    List<Map<String, dynamic>> matches,
    CustomerSortOption sortOption,
    String query,
  ) {
    switch (sortOption) {
      case CustomerSortOption.nameAsc:
        matches.sort((a, b) {
          int rank(Map<String, dynamic> row) {
            final name = (row['name']?.toString() ?? '').toLowerCase();
            final email = (row['email']?.toString() ?? '').toLowerCase();
            if (name.startsWith(query)) return 0;
            if (name.contains(query)) return 1;
            if (email.startsWith(query)) return 2;
            if (email.contains(query)) return 3;
            return 4;
          }

          final rankComparison = rank(a).compareTo(rank(b));
          if (rankComparison != 0) return rankComparison;
          return (a['name']?.toString() ?? '')
              .compareTo(b['name']?.toString() ?? '');
        });
        break;
      case CustomerSortOption.nameDesc:
        matches.sort((a, b) => (b['name']?.toString() ?? '')
            .compareTo(a['name']?.toString() ?? ''));
        break;
      case CustomerSortOption.oldestDebt:
        matches.sort((a, b) {
          final aBal = (a['balance'] as num?)?.toDouble() ?? 0.0;
          final bBal = (b['balance'] as num?)?.toDouble() ?? 0.0;
          final aDate = a['oldest_debt_date']?.toString();
          final bDate = b['oldest_debt_date']?.toString();
          final aHas = aBal < -0.009 && aDate != null && aDate.isNotEmpty;
          final bHas = bBal < -0.009 && bDate != null && bDate.isNotEmpty;
          if (aHas && !bHas) return -1;
          if (!aHas && bHas) return 1;
          if (aHas && bHas) {
            final c = aDate.compareTo(bDate);
            if (c != 0) return c;
          }
          return aBal.compareTo(bBal);
        });
        break;
      case CustomerSortOption.newestDebt:
        matches.sort((a, b) {
          final aBal = (a['balance'] as num?)?.toDouble() ?? 0.0;
          final bBal = (b['balance'] as num?)?.toDouble() ?? 0.0;
          final aDate = a['latest_debt_date']?.toString();
          final bDate = b['latest_debt_date']?.toString();
          final aHas = aBal < -0.009 && aDate != null && aDate.isNotEmpty;
          final bHas = bBal < -0.009 && bDate != null && bDate.isNotEmpty;
          if (aHas && !bHas) return -1;
          if (!aHas && bHas) return 1;
          if (aHas && bHas) {
            final c = bDate.compareTo(aDate);
            if (c != 0) return c;
          }
          return aBal.compareTo(bBal);
        });
        break;
      case CustomerSortOption.highestDebt:
        matches.sort((a, b) {
          final aBal = (a['balance'] as num?)?.toDouble() ?? 0.0;
          final bBal = (b['balance'] as num?)?.toDouble() ?? 0.0;
          final aHas = aBal < -0.009;
          final bHas = bBal < -0.009;
          if (aHas && !bHas) return -1;
          if (!aHas && bHas) return 1;
          return aBal.compareTo(bBal);
        });
        break;
      case CustomerSortOption.lowestDebt:
        matches.sort((a, b) {
          final aBal = (a['balance'] as num?)?.toDouble() ?? 0.0;
          final bBal = (b['balance'] as num?)?.toDouble() ?? 0.0;
          final aHas = aBal < -0.009;
          final bHas = bBal < -0.009;
          if (aHas && !bHas) return -1;
          if (!aHas && bHas) return 1;
          return bBal.compareTo(aBal);
        });
        break;
    }
  }

  static bool _matchesBalance(
    Map<String, dynamic> row,
    CustomerBalanceFilter filter,
  ) {
    final balance = (row['balance'] as num?)?.toDouble() ?? 0;
    return switch (filter) {
      CustomerBalanceFilter.debt => balance < -0.009,
      CustomerBalanceFilter.credit => balance > 0.009,
      CustomerBalanceFilter.clear => balance.abs() <= 0.009,
      CustomerBalanceFilter.all => true,
    };
  }

  static String _normalizedPhone(String query) {
    var digits = query.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  static CustomerBalanceSummary _summaryFromRows(
      List<Map<String, dynamic>> rows) {
    var debt = 0.0;
    var credit = 0.0;
    var debtors = 0;
    var creditors = 0;
    var clear = 0;
    for (final row in rows) {
      final balance = (row['balance'] as num?)?.toDouble() ?? 0;
      if (balance < -0.009) {
        debt += balance.abs();
        debtors++;
      } else if (balance > 0.009) {
        credit += balance;
        creditors++;
      } else {
        clear++;
      }
    }
    return CustomerBalanceSummary(
      totalDebt: debt,
      totalCredit: credit,
      debtorCount: debtors,
      creditCount: creditors,
      clearCount: clear,
    );
  }

  Future<List<Map<String, dynamic>>> _legacyNormalizedSearch(
    String query, {
    String? normalizedPhone,
  }) async {
    final candidates = await _executor.rawQuery('''
      SELECT c.*,
        (SELECT MIN(ft.created_at) FROM financial_transactions ft
         WHERE ft.customer_id = c.id
           AND ft.debt_amount > 0
           AND COALESCE(ft.is_deleted, 0) = 0) AS oldest_debt_date,
        (SELECT MAX(ft.created_at) FROM financial_transactions ft
         WHERE ft.customer_id = c.id
           AND ft.debt_amount > 0
           AND COALESCE(ft.is_deleted, 0) = 0) AS latest_debt_date
      FROM customers c
      WHERE c.is_active = 1 AND c.id != ''
      ORDER BY c.name ASC
    ''');
    final matches = candidates.where((row) {
      final name = _normalizeTurkish(row['name']?.toString() ?? '');
      final email = _normalizeTurkish(row['email']?.toString() ?? '');
      final taxNumber = _normalizeTurkish(row['tax_number']?.toString() ?? '');
      final phone =
          row['phone']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      return name.contains(query) ||
          email.contains(query) ||
          taxNumber.contains(query) ||
          (normalizedPhone?.isNotEmpty == true &&
              phone.contains(normalizedPhone!));
    }).toList();
    return matches;
  }

  @override
  Future<List<CustomerEntity>> getDebtors() async {
    final rows = await _executor.query(
      'customers',
      where: "balance < 0 AND is_active = 1 AND id != ''",
      orderBy: 'balance ASC',
    );
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
  }

  @override
  Future<List<CustomerEntity>> getWithCredit() async {
    final rows = await _executor.query(
      'customers',
      where: "balance > 0 AND is_active = 1 AND id != ''",
      orderBy: 'balance DESC',
    );
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
  }

  @override
  Future<void> updateBalance(String customerId, double amount) async {
    return _gateway.transaction(() async {
      final balanceMinor = (amount * 100).round();
      await _executor.update(
        'customers',
        {
          'balance': amount,
          'balance_minor': balanceMinor,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
  }

  @override
  Future<double> getBalance(String customerId) async {
    final rows = await _executor.query(
      'customers',
      columns: ['balance'],
      where: 'id = ?',
      whereArgs: [customerId],
    );
    if (rows.isEmpty) return 0;
    return rows.first['balance'] as double? ?? 0;
  }

  @override
  Future<double> getTotalDebt(String customerId) async {
    final result = await _executor.rawQuery(
      'SELECT COALESCE(SUM(debit), 0.0) as total '
      'FROM v_financial_ledger WHERE customer_id = ?',
      [customerId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<double> getTotalPaid(String customerId) async {
    final result = await _executor.rawQuery(
      'SELECT COALESCE(SUM(credit), 0.0) as total '
      'FROM v_financial_ledger WHERE customer_id = ?',
      [customerId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<CustomerDuplicateCheckResult> checkDuplicates({
    required String name,
    required String phone,
    String? excludeId,
  }) async {
    final normName = _normalizeTurkish(name.trim());
    final normPhone = _normalizedPhone(phone.trim());

    final hasValidPhone = normPhone.length >= 7;

    final whereClauses = ['is_active = 1', "id != ''"];
    final whereArgs = <dynamic>[];
    if (excludeId != null && excludeId.isNotEmpty) {
      whereClauses.add('id != ?');
      whereArgs.add(excludeId);
    }

    final rows = await _executor.query(
      'customers',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
    );

    CustomerEntity? phoneConflictCustomer;

    for (final row in rows) {
      final existingCust = CustomerEntity.fromMap(row);
      final existingNormName = _normalizeTurkish(existingCust.name.trim());
      final existingNormPhone = _normalizedPhone(existingCust.phone.trim());

      final isPhoneMatch = hasValidPhone &&
          existingNormPhone.length >= 7 &&
          (existingNormPhone == normPhone ||
              existingNormPhone.endsWith(normPhone) ||
              normPhone.endsWith(existingNormPhone));

      final isNameMatch = normName.isNotEmpty && existingNormName == normName;

      // 1. Exact match: Both Name AND Phone match -> Strictly BLOCKED
      if (isNameMatch && isPhoneMatch) {
        return CustomerDuplicateCheckResult(
          status: CustomerDuplicateStatus.exactMatch,
          matchedCustomer: existingCust,
        );
      }

      // Exact match when both have same name and no phone
      if (isNameMatch && !hasValidPhone && existingNormPhone.isEmpty) {
        return CustomerDuplicateCheckResult(
          status: CustomerDuplicateStatus.exactMatch,
          matchedCustomer: existingCust,
        );
      }

      // 2. Phone match but different name -> User confirmation required
      if (isPhoneMatch && !isNameMatch) {
        phoneConflictCustomer ??= existingCust;
      }
    }

    if (phoneConflictCustomer != null) {
      return CustomerDuplicateCheckResult(
        status: CustomerDuplicateStatus.phoneConflict,
        matchedCustomer: phoneConflictCustomer,
      );
    }

    return const CustomerDuplicateCheckResult(
      status: CustomerDuplicateStatus.none,
    );
  }
}
