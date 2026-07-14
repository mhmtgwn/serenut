/// RequiredDbExecutor — Enforces transaction usage at compile time
///
/// Key idea: Can ONLY be created by AppTransaction.run()
/// This prevents accidental use of cached executor in critical paths.
///
/// Usage:
/// ```dart
/// // WRONG: No way to do this
/// final result = saleService.createSale(sale, items);  // RequiredDbExecutor needed!
///
/// // RIGHT: Only inside transaction
/// await txn.run<SaleResult>((requiredExecutor) async {
///   return saleService.createSaleWithinTransaction(sale, items, requiredExecutor);
/// });
/// ```
library;

import 'package:serenutos/infrastructure/database/database_executor.dart';

/// Opaque wrapper that can only be created inside a transaction.
/// Prevents accidental executor bypass by making it impossible to obtain
/// outside of txn.run() context.
class RequiredDbExecutor {
  final DbExecutor _executor;

  /// Private constructor — can only be created by AppTransaction.run()
  RequiredDbExecutor._(this._executor);

  /// Get the underlying executor
  DbExecutor get executor => _executor;

  /// Factory for AppTransaction to create with proper context
  static RequiredDbExecutor create(DbExecutor executor) {
    return RequiredDbExecutor._(executor);
  }

  @override
  String toString() => 'RequiredDbExecutor(transactionContext)';
}

/// Extension to make it ergonomic
extension RequiredDbExecutorAccess on RequiredDbExecutor {
  /// Direct executor access — used by repo methods
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return _executor.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(String table, Map<String, dynamic> values) async {
    return _executor.insert(table, values);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return _executor.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return _executor.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    return _executor.rawQuery(sql, arguments);
  }

  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    return _executor.execute(sql, arguments);
  }
}
