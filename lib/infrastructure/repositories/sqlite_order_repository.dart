import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

class SqliteOrderRepository implements IOrderRepository {
  final DbGateway _gateway;

  SqliteOrderRepository(this._gateway);

  DbExecutor get _executor => _gateway;

  Future<List<OrderEntity>> _enrichOrders(
      List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];

    // Optimized: single bulk IN query instead of N+1 per-order subqueries
    final orderIds = rows.map((r) => r['id'].toString()).toList();
    final placeholders = List.filled(orderIds.length, '?').join(',');
    final itemRows = await _executor.query(
      'order_items',
      where: 'order_id IN ($placeholders)',
      whereArgs: orderIds,
    );

    // Group items by order_id for O(1) lookup
    final itemsByOrderId = <String, List<Map<String, dynamic>>>{};
    for (final item in itemRows) {
      final orderId = item['order_id'] as String;
      itemsByOrderId.putIfAbsent(orderId, () => []).add(item);
    }

    final list = <OrderEntity>[];
    for (final row in rows) {
      final order = OrderEntity.fromMap(row);
      order.items.addAll(itemsByOrderId[order.id] ?? []);
      list.add(order);
    }
    return list;
  }

  @override
  Future<List<OrderEntity>> findAll() async {
    final rows = await _executor.query('orders',
        where: 'is_deleted = 0 OR is_deleted IS NULL',
        orderBy: 'created_at DESC');
    return _enrichOrders(rows);
  }

  @override
  Future<OrderEntity?> findById(dynamic id) async {
    final rows = await _executor.query(
      'orders',
      where: 'id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final itemRows = await _executor
        .query('order_items', where: 'order_id = ?', whereArgs: [id]);
    final order = OrderEntity.fromMap(rows.first);
    order.items.addAll(itemRows);
    return order;
  }

  @override
  Future<int> create(OrderEntity entity) async {
    final totalAmount = entity.items.fold<double>(
      0.0,
      (sum, item) =>
          sum +
          ((item['unit_price'] as double? ?? 0.0) *
              ((item['quantity'] as num?)?.toDouble() ?? 0.0)),
    );
    return _gateway.transaction(() async {
      final sequenceRows = await _executor.query(
        'order_number_sequence',
        columns: const ['next_value'],
        where: 'id = 1',
        limit: 1,
      );
      if (sequenceRows.isEmpty) {
        throw StateError('Sipariş numarası sayacı bulunamadı.');
      }
      final nextValue = (sequenceRows.single['next_value'] as num).toInt();
      final orderNumber = 'SP-${nextValue.toString().padLeft(6, '0')}';
      final sequenceUpdated = await _executor.update(
        'order_number_sequence',
        {'next_value': nextValue + 1},
        where: 'id = 1 AND next_value = ?',
        whereArgs: [nextValue],
      );
      if (sequenceUpdated != 1) {
        throw StateError('Sipariş numarası eşzamanlı üretilemedi.');
      }
      final payload = {
        'id': entity.id,
        'order_number': orderNumber,
        'customer_id': entity.customerId,
        'status': entity.status,
        'total_amount': totalAmount,
        'order_date': entity.createdAt.toIso8601String(),
        'expected_delivery_date':
            entity.expectedDeliveryDate?.toIso8601String(),
        'notes': entity.notes,
        'created_at': entity.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'created_by': entity.createdBy,
        'is_synced': 0,
        'items': entity.items,
      };
      final rowPayload = Map<String, dynamic>.from(payload)..remove('items');
      final rowId = await _executor.insert('orders', rowPayload);
      int index = 0;
      for (final item in entity.items) {
        await _executor.insert('order_items', {
          'id': 'item-${entity.id}-${item['product_id']}-${++index}',
          'order_id': entity.id,
          'product_id': item['product_id'] as String,
          'product_name': item['product_name'],
          'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
          'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'order',
          entityId: entity.id,
          operation: 'UPSERT',
          payload: payload);
      return rowId;
    });
  }

  @override
  Future<int> update(OrderEntity entity) async {
    final totalAmount = entity.items.fold<double>(
      0.0,
      (sum, item) =>
          sum +
          ((item['unit_price'] as double? ?? 0.0) *
              ((item['quantity'] as num?)?.toDouble() ?? 0.0)),
    );
    return _gateway.transaction(() async {
      final payload = {
        'customer_id': entity.customerId,
        'status': entity.status,
        'total_amount': totalAmount,
        'expected_delivery_date':
            entity.expectedDeliveryDate?.toIso8601String(),
        'actual_delivery_date': entity.actualDeliveryDate?.toIso8601String(),
        'notes': entity.notes,
        'updated_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
        'items': entity.items,
      };
      final rowPayload = Map<String, dynamic>.from(payload)..remove('items');
      await _executor.update('orders', rowPayload,
          where: 'id = ?', whereArgs: [entity.id]);

      // Re-insert items
      await _executor
          .delete('order_items', where: 'order_id = ?', whereArgs: [entity.id]);
      int index = 0;
      for (final item in entity.items) {
        await _executor.insert('order_items', {
          'id': 'item-${entity.id}-${item['product_id']}-${++index}',
          'order_id': entity.id,
          'product_id': item['product_id'] as String,
          'product_name': item['product_name'],
          'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
          'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'order',
          entityId: entity.id,
          operation: 'UPSERT',
          payload: payload);
      return 1;
    });
  }

  @override
  Future<int> delete(dynamic id) async {
    // Soft delete order, keep order_items intact so we can restore!
    return _gateway.transaction(() async {
      final payload = {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
      };
      final result = await _executor
          .update('orders', payload, where: 'id = ?', whereArgs: [id]);
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'order',
          entityId: id.toString(),
          operation: 'DELETE',
          payload: payload);
      return result;
    });
  }

  @override
  Future<int> count() async {
    final result =
        await _executor.rawQuery('SELECT COUNT(*) as count FROM orders');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<bool> exists(dynamic id) async {
    final result = await _executor.query('orders',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return result.isNotEmpty;
  }

  @override
  Future<List<OrderEntity>> getByCustomerId(String customerId) async {
    final rows = await _executor.query(
      'orders',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return _enrichOrders(rows);
  }

  @override
  Future<List<OrderEntity>> getByStatus(String status) async {
    final rows = await _executor.query(
      'orders',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at DESC',
    );
    return _enrichOrders(rows);
  }

  @override
  Future<List<OrderEntity>> getPending() async {
    final rows = await _executor.query(
      'orders',
      where: 'status IN (?, ?, ?)',
      whereArgs: ['created', 'preparing', 'ready'],
      orderBy: 'created_at DESC',
    );
    return _enrichOrders(rows);
  }

  @override
  Future<void> updateStatus(String orderId, String status) async {
    await _gateway.transaction(() async {
      final existing = await _executor.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (existing.isEmpty) throw Exception('Sipariş bulunamadı.');
      if (existing.first['status'] == status) return;

      final now = DateTime.now().toIso8601String();
      final updateMap = <String, dynamic>{
        'status': status,
        'updated_at': now,
        'is_synced': 0,
      };
      if (status == 'delivered') updateMap['actual_delivery_date'] = now;

      final count = await _executor.update(
        'orders',
        updateMap,
        where: 'id = ? AND status != ?',
        whereArgs: [orderId, status],
      );
      if (count != 1) throw Exception('Geçersiz sipariş durumu geçişi.');

      // A status transition is a replicated domain mutation, just like create
      // and edit. Keep the row write and its complete aggregate payload in the
      // same transaction so another device can materialize it immediately.
      final updatedRows = await _executor.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      final itemRows = await _executor.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      final payload = Map<String, dynamic>.from(updatedRows.single)
        ..['items'] = itemRows;
      await SyncOutboxV4.enqueue(
        _executor,
        entityType: 'order',
        entityId: orderId,
        operation: 'UPSERT',
        payload: payload,
      );
    });
  }

  @override
  Future<List<OrderEntity>> getOverdue() async {
    final now = DateTime.now().toIso8601String();
    final rows = await _executor.query(
      'orders',
      where: 'expected_delivery_date < ? AND status != ?',
      whereArgs: [now, 'delivered'],
      orderBy: 'created_at DESC',
    );
    return _enrichOrders(rows);
  }

  @override
  Future<List<OrderEntity>> findFiltered({
    String? searchQuery,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool overdueOnly = false,
    int limit = 25,
    int offset = 0,
  }) async {
    final conditions = <String>[];
    final args = <dynamic>[];

    conditions.add('(is_deleted = 0 OR is_deleted IS NULL)');

    final hasStatus = status != null && status != 'all' && status.isNotEmpty;
    if (hasStatus) {
      conditions.add('status = ?');
      args.add(status);
    }

    final hasSearch = searchQuery != null && searchQuery.isNotEmpty;
    if (hasSearch) {
      conditions.add('(id LIKE ? OR order_number LIKE ? OR customer_id IN '
          '(SELECT id FROM customers WHERE name LIKE ? OR phone LIKE ?))');
      args.addAll([
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%'
      ]);
    }
    if (dateFrom != null) {
      conditions.add('created_at >= ?');
      args.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      conditions.add('created_at < ?');
      args.add(dateTo.toIso8601String());
    }
    if (overdueOnly) {
      conditions.add('expected_delivery_date IS NOT NULL');
      conditions.add('expected_delivery_date < ?');
      conditions.add("status NOT IN ('delivered', 'cancelled')");
      args.add(DateTime.now().toIso8601String());
    }

    final where = conditions.join(' AND ');
    args.addAll([limit, offset]);

    final rows = await _executor.rawQuery(
      'SELECT * FROM orders WHERE $where ORDER BY created_at DESC LIMIT ? OFFSET ?',
      args,
    );
    return _enrichOrders(rows);
  }

  @override
  Future<Map<String, int>> getStatusCounts({
    String? searchQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool overdueOnly = false,
  }) async {
    final conditions = <String>['(is_deleted = 0 OR is_deleted IS NULL)'];
    final args = <dynamic>[];

    final hasSearch = searchQuery != null && searchQuery.isNotEmpty;
    if (hasSearch) {
      conditions.add('(id LIKE ? OR order_number LIKE ? OR customer_id IN '
          '(SELECT id FROM customers WHERE name LIKE ? OR phone LIKE ?))');
      args.addAll([
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%'
      ]);
    }
    if (dateFrom != null) {
      conditions.add('created_at >= ?');
      args.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      conditions.add('created_at < ?');
      args.add(dateTo.toIso8601String());
    }
    if (overdueOnly) {
      conditions.add('expected_delivery_date IS NOT NULL');
      conditions.add('expected_delivery_date < ?');
      conditions.add("status NOT IN ('delivered', 'cancelled')");
      args.add(DateTime.now().toIso8601String());
    }

    final where = conditions.join(' AND ');
    final rows = await _executor.rawQuery(
      'SELECT status, COUNT(*) as cnt FROM orders WHERE $where GROUP BY status',
      args,
    );

    final counts = <String, int>{
      'all': 0,
      'created': 0,
      'preparing': 0,
      'ready': 0,
      'delivered': 0,
      'cancelled': 0,
    };

    for (final row in rows) {
      final s = row['status'] as String? ?? '';
      final c = (row['cnt'] as num?)?.toInt() ?? 0;
      if (counts.containsKey(s)) counts[s] = c;
      counts['all'] = (counts['all'] ?? 0) + c;
    }
    return counts;
  }
}
