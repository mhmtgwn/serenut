import 'dart:async';
import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

class SqliteSaleRepository implements ISaleRepository {
  final DbGateway _gateway;

  SqliteSaleRepository(this._gateway);

  DbExecutor get _executor => _gateway;

  @override
  Future<List<SaleEntity>> findAll() async {
    try {
      final rows = await _executor.query('sales', where: 'is_deleted = 0 OR is_deleted IS NULL');
      return rows.map((row) => SaleEntity.fromMap(row)).toList();
    } catch (_) {
      final rows = await _executor.query('sales');
      return rows.map((row) => SaleEntity.fromMap(row)).toList();
    }
  }

  @override
  Future<SaleEntity?> findByIdempotencyKey(String key) async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await _executor.query(
        'sales',
        where: 'idempotency_key = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [key],
      );
    } catch (_) {
      rows = await _executor.query(
        'sales',
        where: 'idempotency_key = ?',
        whereArgs: [key],
      );
    }
    if (rows.isEmpty) return null;
    
    final sale = SaleEntity.fromMap(rows.first);
    // Load sale items
    final items = await _executor.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [sale.id],
    );
    sale.items.addAll(items);
    return sale;
  }

  @override
  Future<SaleEntity?> findById(dynamic id) async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await _executor.query(
        'sales',
        where: 'id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [id],
      );
    } catch (_) {
      rows = await _executor.query(
        'sales',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    if (rows.isEmpty) return null;
    
    final sale = SaleEntity.fromMap(rows.first);
    // Load sale items
    final items = await _executor.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [id],
    );
    sale.items.addAll(items);
    return sale;
  }

  @override
  Future<int> create(SaleEntity entity) async {
    await _executor.insert('sales', {
      'id': entity.id,
      'customer_id': entity.customerId,
      'total_amount': entity.totalAmount,
      'paid_amount': entity.paidAmount,
      'payment_method': entity.paymentMethod,
      'status': entity.status,
      'created_at': entity.createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'idempotency_key': entity.idempotencyKey,
      'is_synced': entity.isSynced,
      'created_by': entity.createdBy,
    });

    for (final item in entity.items) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      await _executor.insert('sale_items', {
        'id': 'item-${entity.id}-${item['product_id']}',
        'sale_id': entity.id,
        'product_id': item['product_id'] as String,
        'quantity': qty,
        'unit_price': price,
        'subtotal': qty * price,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    return 1;
  }

  @override
  Future<int> update(SaleEntity entity) async {
    await _gateway.transaction(() async {
      await _executor.update(
        'sales',
        {
          'total_amount': entity.totalAmount,
          'paid_amount': entity.paidAmount,
          'status': entity.status,
          'is_synced': entity.isSynced,
          'idempotency_key': entity.idempotencyKey,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      // Remove existing items and write current items
      await _executor.delete(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [entity.id],
      );

      for (final item in entity.items) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (item['unit_price'] ?? item['unitPrice'] as num?)?.toDouble() ?? 0.0;
        await _executor.insert('sale_items', {
          'id': 'item-${entity.id}-${item['product_id']}',
          'sale_id': entity.id,
          'product_id': item['product_id'] as String,
          'quantity': qty,
          'unit_price': price,
          'subtotal': qty * price,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    });
    return 1;
  }

  @override
  Future<int> delete(dynamic id) async {
    return await _executor.update(
      'sales',
      {
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
    final result = await _executor.rawQuery('SELECT COUNT(*) as count FROM sales');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<bool> exists(dynamic id) async {
    final result = await _executor.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  @override
  Future<List<SaleEntity>> getTodaySales() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();
    
    final rows = await _executor.query(
      'sales',
      where: 'created_at BETWEEN ? AND ?',
      whereArgs: [startOfDay, endOfDay],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => SaleEntity.fromMap(row)).toList();
  }

  @override
  Future<List<SaleEntity>> getSalesByDateRange(DateTime from, DateTime to) async {
    final rows = await _executor.query(
      'sales',
      where: 'created_at BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => SaleEntity.fromMap(row)).toList();
  }

  @override
  Future<List<SaleEntity>> getByCustomerId(String customerId) async {
    final rows = await _executor.query(
      'sales',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => SaleEntity.fromMap(row)).toList();
  }

  @override
  Future<List<SaleEntity>> getByPaymentMethod(String method) async {
    final rows = await _executor.query(
      'sales',
      where: 'payment_method = ?',
      whereArgs: [method],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => SaleEntity.fromMap(row)).toList();
  }

  @override
  Future<double> getTodayRevenue() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();
    
    final result = await _executor.rawQuery(
      'SELECT SUM(total_amount) as revenue FROM sales '
      'WHERE created_at BETWEEN ? AND ? AND status = ?',
      [startOfDay, endOfDay, 'completed'],
    );
    if (result.isEmpty) return 0;
    return result.first['revenue'] as double? ?? 0;
  }

  @override
  Future<double> getRevenueByDateRange(DateTime from, DateTime to) async {
    final result = await _executor.rawQuery(
      'SELECT SUM(total_amount) as revenue FROM sales '
      'WHERE created_at BETWEEN ? AND ? AND status = ?',
      [from.toIso8601String(), to.toIso8601String(), 'completed'],
    );
    if (result.isEmpty) return 0;
    return result.first['revenue'] as double? ?? 0;
  }

  @override
  Future<int> getTotalItemsSold() async {
    final result = await _executor.rawQuery(
      'SELECT SUM(quantity) as total FROM sale_items',
    );
    if (result.isEmpty) return 0;
    return result.first['total'] as int? ?? 0;
  }
}

class SqliteFinancialTransactionRepository implements IFinancialTransactionRepository {
  final DbGateway _gateway;
  final String? deviceId;

  SqliteFinancialTransactionRepository(this._gateway, {this.deviceId});

  DbExecutor get _executor => _gateway;

  @override
  Future<List<FinancialTransactionEntity>> findAll() async {
    final rows = await _executor.query('financial_transactions', orderBy: 'logical_clock DESC, device_id DESC');
    return rows.map((row) => FinancialTransactionEntity.fromMap(row)).toList();
  }

  @override
  Future<FinancialTransactionEntity?> findById(dynamic id) async {
    final rows = await _executor.query(
      'financial_transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return FinancialTransactionEntity.fromMap(rows.first);
  }

  @override
  Future<int> create(FinancialTransactionEntity entity) async {
    int nextClock = entity.logicalClock;
    if (nextClock == 0) {
      final result = await _executor.rawQuery('SELECT MAX(logical_clock) as max_clock FROM financial_transactions');
      final maxClock = Sqflite.firstIntValue(result) ?? 0;
      nextClock = maxClock + 1;
    }

    final txDeviceId = entity.deviceId ?? deviceId ?? 'unknown-device';

    return await _executor.insert('financial_transactions', {
      'id': entity.id,
      'type': entity.type,
      'customer_id': entity.customerId,
      'amount': entity.amount,
      'paid_amount': entity.paidAmount,
      'debt_amount': entity.debtAmount,
      'reference_id': entity.referenceId,
      'metadata': entity.metadata != null ? jsonEncode(entity.metadata) : null,
      'created_at': entity.date.toIso8601String(),
      'logical_clock': nextClock,
      'device_id': txDeviceId,
    });
  }

  @override
  Future<int> update(FinancialTransactionEntity entity) async {
    return await _gateway.transaction(() async {
      await _executor.execute('UPDATE ledger_bypass_flag SET active = 1');
      final result = await _executor.update(
        'financial_transactions',
        {
          'id': entity.id,
          'type': entity.type,
          'customer_id': entity.customerId,
          'amount': entity.amount,
          'paid_amount': entity.paidAmount,
          'debt_amount': entity.debtAmount,
          'reference_id': entity.referenceId,
          'metadata': entity.metadata != null ? jsonEncode(entity.metadata) : null,
          'created_at': entity.date.toIso8601String(),
          'logical_clock': entity.logicalClock,
          'device_id': entity.deviceId ?? deviceId ?? 'unknown-device',
        },
        where: 'id = ?',
        whereArgs: [entity.id],
      );
      await _executor.execute('UPDATE ledger_bypass_flag SET active = 0');
      return result;
    });
  }

  @override
  Future<int> delete(dynamic id) async {
    return await _gateway.transaction(() async {
      await _executor.execute('UPDATE ledger_bypass_flag SET active = 1');
      final result = await _executor.delete(
        'financial_transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
      await _executor.execute('UPDATE ledger_bypass_flag SET active = 0');
      return result;
    });
  }

  @override
  Future<int> count() async {
    final result = await _executor.rawQuery('SELECT COUNT(*) as count FROM financial_transactions');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<bool> exists(dynamic id) async {
    final result = await _executor.query(
      'financial_transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  @override
  Future<List<FinancialTransactionEntity>> getByCustomerId(String customerId) async {
    final rows = await _executor.query(
      'financial_transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'logical_clock DESC, device_id DESC',
    );
    return rows.map((row) => FinancialTransactionEntity.fromMap(row)).toList();
  }

  @override
  Future<List<FinancialTransactionEntity>> getByType(String type) async {
    final rows = await _executor.query(
      'financial_transactions',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'logical_clock DESC, device_id DESC',
    );
    return rows.map((row) => FinancialTransactionEntity.fromMap(row)).toList();
  }

  @override
  Future<List<FinancialTransactionEntity>> getByDateRange(DateTime from, DateTime to) async {
    final rows = await _executor.query(
      'financial_transactions',
      where: 'created_at BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'logical_clock DESC, device_id DESC',
    );
    return rows.map((row) => FinancialTransactionEntity.fromMap(row)).toList();
  }

  @override
  Future<double> getBalance(String customerId) async {
    final result = await _executor.rawQuery(
      'SELECT SUM(debt_amount - paid_amount) as balance FROM financial_transactions '
      'WHERE customer_id = ?',
      [customerId],
    );
    if (result.isEmpty) return 0;
    return result.first['balance'] as double? ?? 0;
  }
}
