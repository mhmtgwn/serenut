import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

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

  @override
  Future<List<CustomerEntity>> search(String query) async {
    final rows = await _executor.query(
      'customers',
      where: "(name LIKE ? OR email LIKE ?) AND is_active = 1 AND id != ''",
      whereArgs: ['%$query%', '%$query%'],
    );
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
  }

  @override
  Future<List<CustomerEntity>> findFiltered({
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    String? whereClause;
    List<dynamic>? whereArgs;

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClause =
          "(name LIKE ? OR phone LIKE ? OR email LIKE ?) AND is_active = 1 AND id != ''";
      whereArgs = ['%$searchQuery%', '%$searchQuery%', '%$searchQuery%'];
    } else {
      whereClause = "is_active = 1 AND id != ''";
    }

    final rows = await _executor.query(
      'customers',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map((row) => CustomerEntity.fromMap(row)).toList();
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
      'SELECT SUM(debt_amount) as total FROM financial_transactions '
      'WHERE customer_id = ? AND debt_amount > 0',
      [customerId],
    );
    if (result.isEmpty) return 0;
    return result.first['total'] as double? ?? 0;
  }

  @override
  Future<double> getTotalPaid(String customerId) async {
    final result = await _executor.rawQuery(
      'SELECT SUM(paid_amount) as total FROM financial_transactions '
      'WHERE customer_id = ?',
      [customerId],
    );
    if (result.isEmpty) return 0;
    return result.first['total'] as double? ?? 0;
  }
}
