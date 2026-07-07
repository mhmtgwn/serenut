import 'package:sqflite_sqlcipher/sqflite.dart';

/// Abstract database executor for transaction-aware CRUD operations.
/// 
/// Repositories use this instead of direct Database access,
/// enabling transparent transaction switching:
/// - Normal ops: DbExecutor → Database
/// - Txn ops: DbExecutor → Transaction
/// 
/// Interface matches sqflite.Database for drop-in compatibility.
abstract class DbExecutor {
  /// Query a table
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  });

  /// Insert one row, return inserted ID
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  });

  /// Update rows, return count
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  });

  /// Delete rows, return count
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  /// Execute raw SQL (no results)
  Future<void> execute(String sql, [List<Object?>? arguments]);

  /// Execute raw SQL query (SELECT)
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]);

  /// Execute raw SQL insert
  Future<int> rawInsert(String sql, [List<Object?>? arguments]);

  /// Execute raw SQL update
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]);

  /// Execute raw SQL delete
  Future<int> rawDelete(String sql, [List<Object?>? arguments]);
}
