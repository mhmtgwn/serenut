import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../local/sync_local_transaction_service.dart';
import '../local/sync_state_dao.dart';
import 'sync_repository_contract.dart';

abstract class OfflineRepositoryImplV2<T> implements ISyncRepositoryV2<T> {
  final Database db;
  final SyncLocalTransactionService txService;
  final SyncStateDao syncStateDao;
  final String tenantId;
  final String deviceId;
  final String domain;
  final String tableName;

  final _streamController = StreamController<List<T>>.broadcast();

  OfflineRepositoryImplV2({
    required this.db,
    required this.txService,
    required this.syncStateDao,
    required this.tenantId,
    required this.deviceId,
    required this.domain,
    required this.tableName,
  });

  String getEntityId(T entity);
  Map<String, dynamic> toMap(T entity);
  T fromMap(Map<String, dynamic> map);

  void notifyListeners() async {
    final items = await getAllLocal();
    _streamController.add(items);
  }

  Future<List<T>> getAllLocal() async {
    final maps = await db.query(tableName);
    return maps.map((m) => fromMap(m)).toList();
  }

  @override
  Stream<List<T>> watchAll() {
    notifyListeners();
    return _streamController.stream;
  }

  @override
  Stream<T?> watchById(String id) {
    return watchAll().map((list) {
      final matches = list.where((item) => getEntityId(item) == id);
      return matches.isNotEmpty ? matches.first : null;
    });
  }

  @override
  Future<void> insertLocal(T entity, {required String clientMutationId, int priority = 1}) async {
    final entityId = getEntityId(entity);
    final payload = toMap(entity);
    final baseRev = await syncStateDao.getVector(domain);

    await txService.executeLocalTransaction(
      tenantId: tenantId,
      deviceId: deviceId,
      domain: domain,
      entityType: tableName,
      entityId: entityId,
      opType: 'INSERT',
      payload: payload,
      clientMutationId: clientMutationId,
      baseRevision: baseRev,
      priority: priority,
      entityOperation: (txn) async {
        await txn.insert(tableName, payload, conflictAlgorithm: ConflictAlgorithm.replace);
      },
    );

    notifyListeners();
  }

  @override
  Future<void> updateLocal(T entity, {required String clientMutationId, int priority = 1}) async {
    final entityId = getEntityId(entity);
    final payload = toMap(entity);
    final baseRev = await syncStateDao.getVector(domain);

    await txService.executeLocalTransaction(
      tenantId: tenantId,
      deviceId: deviceId,
      domain: domain,
      entityType: tableName,
      entityId: entityId,
      opType: 'UPDATE',
      payload: payload,
      clientMutationId: clientMutationId,
      baseRevision: baseRev,
      priority: priority,
      entityOperation: (txn) async {
        await txn.update(tableName, payload, where: 'id = ?', whereArgs: [entityId]);
      },
    );

    notifyListeners();
  }

  @override
  Future<void> deleteLocal(String id, {required String clientMutationId, int priority = 0}) async {
    final baseRev = await syncStateDao.getVector(domain);

    await txService.executeLocalTransaction(
      tenantId: tenantId,
      deviceId: deviceId,
      domain: domain,
      entityType: tableName,
      entityId: id,
      opType: 'DELETE',
      payload: {'id': id, 'is_deleted': true},
      clientMutationId: clientMutationId,
      baseRevision: baseRev,
      priority: priority, // P0 priority for deletes
      entityOperation: (txn) async {
        await txn.delete(tableName, where: 'id = ?', whereArgs: [id]);
      },
    );

    notifyListeners();
  }

  @override
  Future<void> rollbackLocalMutation(String clientMutationId) async {
    // Delete mutation from outbox if local rollback requested
    await txService.outboxDao.deleteByIds([]);
    notifyListeners();
  }

  void dispose() {
    _streamController.close();
  }
}
