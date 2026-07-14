// lib/infrastructure/database/db_gateway.dart
// PHASE 2 - Database Safety Layer
// DbGateway handles safe, lock-aware, transaction-routed database execution.

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'database_executor.dart';
import 'database_executor_impl.dart';
import 'database_provider.dart';

/// Database Gateway interface providing structured data access and transaction control.
abstract class DbGateway implements DbExecutor, IDbTransactionRunner {
  /// Executes a transaction block on the database, routing all nested repository operations.
  @override
  Future<T> transaction<T>(Future<T> Function() action);
}

/// Implementation of [DbGateway] wrapping the raw [DatabaseManager] connection lifecycle.
class DbGatewayImpl implements DbGateway {
  final DatabaseManager? _dbManager;
  final Database? _rawDb;

  DbGatewayImpl(DatabaseManager dbManager)
      : _dbManager = dbManager,
        _rawDb = null;
  DbGatewayImpl.raw(Database db)
      : _rawDb = db,
        _dbManager = null;

  // A static queue for serializing all write operations and transactions.
  static Future<void> _writeQueue = Future.value();

  Future<Database> get _db async {
    if (_rawDb != null) return _rawDb!;
    return _dbManager!.getDatabase();
  }

  /// Wait for write lock to clear before starting queries or writes.
  /// Bypassed inside active transaction zones.
  Future<void> _waitForWriteLock({bool isWrite = false}) async {
    if (Zone.current[#sqlite_txn] != null) {
      return;
    }
    // Write verification block removed (SQLCipher removed)

    int attempts = 0;
    final bool isTest =
        !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    final int maxAttempts = isTest ? 2 : 40;
    while (DatabaseManager.isWriteLocked) {
      if (!isWrite) {
        break;
      }
      attempts++;
      if (attempts >= maxAttempts) {
        throw DatabaseLockedException(
            'Database is temporarily locked for backup');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Serialize write operations to guarantee FIFO single-writer safety.
  /// Bypassed inside active transaction zones to prevent deadlocks.
  Future<T> _executeSerialized<T>(Future<T> Function() action) async {
    if (Zone.current[#sqlite_txn] != null) {
      return await action();
    }

    final completer = Completer<T>();
    final previous = _writeQueue;

    _writeQueue = () async {
      try {
        await previous;
      } catch (_) {}

      try {
        final result = await action();
        completer.complete(result);
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    }();

    return completer.future;
  }

  /// Resolves the current execution context.
  /// If a transaction is already active in the [Zone], returns [TransactionExecutorImpl].
  /// Otherwise, returns [DbExecutorImpl] wrapping the connection.
  Future<DbExecutor> _getExecutor() async {
    final txn = Zone.current[#sqlite_txn];
    if (txn != null && txn is Transaction) {
      return TransactionExecutorImpl(txn);
    }
    final db = await _db;
    return DbExecutorImpl(db);
  }

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
    await _waitForWriteLock(isWrite: false);
    final executor = await _getExecutor();
    return executor.query(
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
    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);
      final executor = await _getExecutor();
      return executor.insert(
        table,
        values,
        nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm,
      );
    });
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);
      final executor = await _getExecutor();
      return executor.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );
    });
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);
      final executor = await _getExecutor();
      return executor.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );
    });
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);
      final executor = await _getExecutor();
      return executor.execute(sql, arguments);
    });
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    await _waitForWriteLock(isWrite: false);
    final executor = await _getExecutor();
    return executor.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);
      final executor = await _getExecutor();
      return executor.rawInsert(sql, arguments);
    });
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);
      final executor = await _getExecutor();
      return executor.rawUpdate(sql, arguments);
    });
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);
      final executor = await _getExecutor();
      return executor.rawDelete(sql, arguments);
    });
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    if (Zone.current[#sqlite_txn] != null) {
      return await action();
    }

    return await _executeSerialized(() async {
      await _waitForWriteLock(isWrite: true);

      final parentDeferred =
          Zone.current[#deferred_events] as List<DomainEvent>?;
      final isRootTransaction = parentDeferred == null;
      final List<DomainEvent> deferredEvents = parentDeferred ?? [];

      final db = await _db;
      final result = await db.transaction((txn) async {
        return await runZoned(
          action,
          zoneValues: {
            #sqlite_txn: txn,
            #deferred_events: deferredEvents,
          },
        );
      });

      if (isRootTransaction) {
        for (final event in deferredEvents) {
          EventPublisher().publish(event);
        }
      }

      return result;
    });
  }
}
