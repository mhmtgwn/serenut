import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'database_executor.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

Future<void> _checkLock() async {
  int attempts = 0;
  final bool isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  final int maxAttempts = isTest ? 2 : 40; // Fail fast in tests (100ms), wait 2 seconds in production
  while (DatabaseManager.isWriteLocked) {
    attempts++;
    if (attempts >= maxAttempts) {
      throw DatabaseLockedException('Database is temporarily locked for backup');
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

/// Implementation of DbExecutor wrapping sqflite's Database
class DbExecutorImpl implements DbExecutor {
  final Database _database;

  DbExecutorImpl(this._database);

  @override
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
  }) async {
    return _database.query(
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

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await _checkLock();
    return _database.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await _checkLock();
    return _database.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    await _checkLock();
    return _database.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _database.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    return _database.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _database.rawInsert(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _database.rawUpdate(sql, arguments);
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _database.rawDelete(sql, arguments);
  }
}

/// Implementation of DbExecutor wrapping sqflite's Transaction
class TransactionExecutorImpl implements DbExecutor {
  final Transaction _transaction;

  TransactionExecutorImpl(this._transaction);

  @override
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
  }) async {
    return _transaction.query(
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

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await _checkLock();
    return _transaction.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await _checkLock();
    return _transaction.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    await _checkLock();
    return _transaction.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _transaction.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    return _transaction.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _transaction.rawInsert(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _transaction.rawUpdate(sql, arguments);
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    await _checkLock();
    return _transaction.rawDelete(sql, arguments);
  }
}
