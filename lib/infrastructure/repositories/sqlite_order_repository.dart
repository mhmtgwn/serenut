import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';
import 'package:serenutos/config/utils.dart';

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
    final rows = await _executor.rawQuery('''
      SELECT o.*, c.name AS customer_name, c.phone AS customer_phone
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.is_deleted = 0 OR o.is_deleted IS NULL
      ORDER BY o.created_at DESC
    ''');
    return _enrichOrders(rows);
  }

  @override
  Future<OrderEntity?> findById(dynamic id) async {
    final rows = await _executor.rawQuery('''
      SELECT o.*, c.name AS customer_name, c.phone AS customer_phone
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.id = ? AND (o.is_deleted = 0 OR o.is_deleted IS NULL)
    ''', [id]);
    if (rows.isEmpty) return null;
    final itemRows = await _executor
        .query('order_items', where: 'order_id = ?', whereArgs: [id]);
    final order = OrderEntity.fromMap(rows.first);
    order.items.addAll(itemRows);
    return order;
  }

  @override
  Future<int> create(OrderEntity entity) async {
    final totalAmount = entity.totalAmount;
    return _gateway.transaction(() async {
      final sequenceRows = await _executor.query(
        'order_number_sequence',
        columns: const ['next_value'],
        where: 'id = 1',
        limit: 1,
      );
      int nextValue = 1;
      if (sequenceRows.isNotEmpty) {
        nextValue = (sequenceRows.single['next_value'] as num).toInt();
      }

      final maxOrderRows = await _executor.rawQuery('''
        SELECT MAX(CAST(SUBSTR(order_number, 4) AS INTEGER)) as max_num
        FROM orders
        WHERE order_number LIKE 'SP-%'
      ''');
      if (maxOrderRows.isNotEmpty && maxOrderRows.first['max_num'] != null) {
        final maxExisting = (maxOrderRows.first['max_num'] as num).toInt();
        if (maxExisting >= nextValue) {
          nextValue = maxExisting + 1;
        }
      }

      String orderNumber = 'SP-${nextValue.toString().padLeft(6, '0')}';
      while (true) {
        final existsRows = await _executor.rawQuery(
          'SELECT 1 FROM orders WHERE order_number = ? LIMIT 1',
          [orderNumber],
        );
        if (existsRows.isEmpty) break;
        nextValue++;
        orderNumber = 'SP-${nextValue.toString().padLeft(6, '0')}';
      }

      if (sequenceRows.isEmpty) {
        await _executor.insert('order_number_sequence', {
          'id': 1,
          'next_value': nextValue + 1,
        });
      } else {
        await _executor.rawUpdate(
          'UPDATE order_number_sequence SET next_value = ? WHERE id = 1',
          [nextValue + 1],
        );
      }
      final payload = {
        'id': entity.id,
        'order_number': orderNumber,
        'customer_id': entity.customerId,
        'status': entity.status,
        'total_amount': totalAmount,
        'discount_amount': entity.discountAmount,
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
    final totalAmount = entity.totalAmount;
    return _gateway.transaction(() async {
      final existing = await _executor.query(
        'orders',
        columns: ['order_number'],
        where: 'id = ?',
        whereArgs: [entity.id],
        limit: 1,
      );
      final existingNum = existing.isNotEmpty ? (existing.first['order_number']?.toString() ?? '') : '';
      final orderNumber = entity.orderNumber.isNotEmpty && !entity.orderNumber.startsWith('SYNC-')
          ? entity.orderNumber
          : (existingNum.isNotEmpty && !existingNum.startsWith('SYNC-') ? existingNum : entity.orderNumber);

      final payload = {
        'id': entity.id,
        if (orderNumber.isNotEmpty) 'order_number': orderNumber,
        'customer_id': entity.customerId,
        'status': entity.status,
        'total_amount': totalAmount,
        'discount_amount': entity.discountAmount,
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
    final rows = await _executor.rawQuery('''
      SELECT o.*, c.name AS customer_name, c.phone AS customer_phone
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.customer_id = ? AND (o.is_deleted = 0 OR o.is_deleted IS NULL)
      ORDER BY o.created_at DESC
    ''', [customerId]);
    return _enrichOrders(rows);
  }

  @override
  Future<List<OrderEntity>> getByStatus(String status) async {
    final rows = await _executor.rawQuery('''
      SELECT o.*, c.name AS customer_name, c.phone AS customer_phone
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.status = ? AND (o.is_deleted = 0 OR o.is_deleted IS NULL)
      ORDER BY o.created_at DESC
    ''', [status]);
    return _enrichOrders(rows);
  }

  @override
  Future<List<OrderEntity>> getPending() async {
    final rows = await _executor.rawQuery('''
      SELECT o.*, c.name AS customer_name, c.phone AS customer_phone
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.status IN ('created', 'preparing', 'ready') AND (o.is_deleted = 0 OR o.is_deleted IS NULL)
      ORDER BY o.created_at DESC
    ''');
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
    final rows = await _executor.rawQuery('''
      SELECT o.*, c.name AS customer_name, c.phone AS customer_phone
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.expected_delivery_date < ? AND o.status != 'delivered' AND (o.is_deleted = 0 OR o.is_deleted IS NULL)
      ORDER BY o.created_at DESC
    ''', [now]);
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

    conditions.add('(o.is_deleted = 0 OR o.is_deleted IS NULL)');

    final hasStatus = status != null && status != 'all' && status.isNotEmpty;
    if (hasStatus) {
      conditions.add('o.status = ?');
      args.add(status);
    }

    final hasSearch = searchQuery != null && searchQuery.trim().isNotEmpty;
    if (hasSearch) {
      final trimmed = searchQuery.trim();
      final normalizedQuery = trimmed.normalizeTurkish;
      final qPattern = '%$normalizedQuery%';
      final rawPattern = '%$trimmed%';
      conditions.add('(o.id LIKE ? OR o.order_number LIKE ? OR o.notes LIKE ? OR o.customer_id IN '
          '(SELECT id FROM customers WHERE ${sqliteTurkishFold('name')} LIKE ? OR phone LIKE ?))');
      args.addAll([
        rawPattern,
        rawPattern,
        qPattern,
        qPattern,
        rawPattern,
      ]);
    }
    if (dateFrom != null) {
      conditions.add('o.created_at >= ?');
      args.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      conditions.add('o.created_at < ?');
      args.add(dateTo.toIso8601String());
    }
    if (overdueOnly) {
      conditions.add('o.expected_delivery_date IS NOT NULL');
      conditions.add('o.expected_delivery_date < ?');
      conditions.add("o.status NOT IN ('delivered', 'cancelled')");
      args.add(DateTime.now().toIso8601String());
    }

    final where = conditions.join(' AND ');
    args.addAll([limit, offset]);

    final rows = await _executor.rawQuery(
      'SELECT o.*, c.name AS customer_name, c.phone AS customer_phone FROM orders o LEFT JOIN customers c ON o.customer_id = c.id WHERE $where ORDER BY o.created_at DESC LIMIT ? OFFSET ?',
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
