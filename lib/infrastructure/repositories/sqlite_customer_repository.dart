import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/config/utils.dart';

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
  Future<CustomerEntity?> findById(dynamic id) async {
    final rows = await _executor.query(
      'customers',
      where: 'id = ? AND is_active = 1',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return CustomerEntity.fromMap(rows.first);
  }

  @override
  Future<int> create(CustomerEntity entity) async {
    return await _executor.insert('customers', {
      ...entity.toMap(),
      'is_synced': 0,
      'normalized_name': entity.name.normalizeTurkish,
      'normalized_email': entity.email.toLowerCase(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<int> update(CustomerEntity entity) async {
    return await _executor.update(
      'customers',
      {
        ...entity.toMap(),
        'is_synced': 0,
        'normalized_name': entity.name.normalizeTurkish,
        'normalized_email': entity.email.toLowerCase(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [entity.id],
    );
  }

  @override
  Future<int> delete(dynamic id) async {
    if (id == null || id == '') return 0;
    return await _executor.update(
      'customers',
      {
        'is_active': 0,
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<int> count() async {
    final result = await _executor.rawQuery(
      "SELECT COUNT(*) as count FROM customers WHERE is_active = 1 AND id != ''",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<bool> exists(dynamic id) async {
    final result = await _executor.query(
      'customers',
      where: 'id = ? AND is_active = 1',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  String _normalizeTurkish(String text) {
    return text
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o');
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
    int? limit,
    int? offset,
  }) async {
    if (searchQuery == null || searchQuery.trim().isEmpty) {
      final rows = await _executor.query(
        'customers',
        where: "is_active = 1 AND id != ''",
        orderBy: 'normalized_name ASC',
        limit: limit,
        offset: offset,
      );
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

    final matches = await _legacyNormalizedSearch(
      normalizedQuery,
      normalizedPhone: cleanPhone,
    );
    final start = (offset ?? 0).clamp(0, matches.length);
    final end = limit == null
        ? matches.length
        : (start + limit).clamp(start, matches.length);
    final rows = matches.sublist(start, end);
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
  }

  Future<List<Map<String, dynamic>>> _legacyNormalizedSearch(
    String query, {
    String? normalizedPhone,
  }) async {
    final candidates = await _executor.query(
      'customers',
      where: "is_active = 1 AND id != ''",
      orderBy: 'name ASC',
    );
    final matches = candidates.where((row) {
      final name = _normalizeTurkish(row['name']?.toString() ?? '');
      final email = _normalizeTurkish(row['email']?.toString() ?? '');
      final phone =
          row['phone']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      return name.contains(query) ||
          email.contains(query) ||
          (normalizedPhone?.isNotEmpty == true &&
              phone.contains(normalizedPhone!));
    }).toList();
    matches.sort((a, b) {
      int rank(Map<String, dynamic> row) {
        final name = _normalizeTurkish(row['name']?.toString() ?? '');
        final email = _normalizeTurkish(row['email']?.toString() ?? '');
        if (name.startsWith(query)) return 0;
        if (name.contains(query)) return 1;
        if (email.startsWith(query)) return 2;
        if (email.contains(query)) return 3;
        return 4;
      }

      final rankComparison = rank(a).compareTo(rank(b));
      if (rankComparison != 0) return rankComparison;
      return _normalizeTurkish(a['name']?.toString() ?? '')
          .compareTo(_normalizeTurkish(b['name']?.toString() ?? ''));
    });
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
    await _executor.execute(
      'UPDATE customers SET balance = balance + ? WHERE id = ?',
      [amount, customerId],
    );
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
      "SELECT COALESCE(SUM(CASE WHEN type IN ('sale', 'manual_debt') THEN amount WHEN type = 'cancellation' THEN -amount ELSE 0 END), 0.0) as total "
      "FROM financial_transactions WHERE customer_id = ?",
      [customerId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<double> getTotalPaid(String customerId) async {
    final result = await _executor.rawQuery(
      "SELECT COALESCE(SUM(CASE "
      "  WHEN type = 'sale' THEN paid_amount "
      "  WHEN type = 'payment' THEN amount "
      "  WHEN type = 'collection' THEN amount "
      "  WHEN type = 'refund' THEN amount "
      "  WHEN type = 'cancellation' THEN -paid_amount "
      "  ELSE 0 "
      "END), 0.0) as total "
      "FROM financial_transactions WHERE customer_id = ?",
      [customerId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
