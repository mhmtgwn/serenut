part of 'sync_v4_service.dart';

extension SyncV4Materializer on SyncV4Service {
  Future<void> _apply(Transaction db, Map<String, dynamic> change) async {
    final type = change['entity_type'] as String;
    final payload = Map<String, dynamic>.from(change['payload'] as Map);
    var id = change['entity_id'] as String;
    if (type == 'system_reset') {
      switch (payload['scope']) {
        case 'operational':
          await DataResetService.clearOperationalTables(db);
          break;
        case 'catalog':
          await DataResetService.clearProductCatalog(db);
          break;
        default:
          throw StateError('unsupported_system_reset_scope');
      }
      return;
    }
    if (type == 'refund') {
      if (change['operation'] == 'DELETE') throw StateError('immutable_refund');
      await this._applyRefund(db, id, payload);
      return;
    }
    final table = switch (type) {
      'product' => 'products',
      'customer' => 'customers',
      'order' => 'orders',
      'sale' => 'sales',
      'financial_transaction' => 'financial_transactions',
      _ => null,
    };
    if (table == null) return;
    if (change['operation'] == 'DELETE') {
      final tombstone = <String, Object?>{
        'is_deleted': 1,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'is_synced': 1,
      };
      if (table == 'products' || table == 'customers') {
        tombstone['is_active'] = 0;
      }
      await db.update(table, tombstone, where: 'id = ?', whereArgs: [id]);
      return;
    }
    if (type == 'product') {
      final repairedId = BarcodeStandard.normalizeReadyCatalog(id);
      if (repairedId != id) {
        final existing = await db.query(
          'products',
          columns: const ['id', 'name', 'price', 'image_url'],
          where: 'id = ?',
          whereArgs: [repairedId],
          limit: 1,
        );
        final incomingName = payload['name']?.toString().trim().toLowerCase();
        final incomingPrice = _syncDouble(payload['price']);
        if (existing.isNotEmpty &&
            existing.first['name']?.toString().trim().toLowerCase() ==
                incomingName &&
            ((_syncDouble(existing.first['price']) - incomingPrice).abs() <=
                0.01)) {
          final retainedImage = existing.first['image_url']?.toString() ?? '';
          if ((payload['image_url']?.toString().trim().isEmpty ?? true) &&
              retainedImage.isNotEmpty) {
            payload['image_url'] = retainedImage;
          }
          if (payload['sku']?.toString() == id) payload['sku'] = repairedId;
          id = repairedId;
        }
      }
    }
    final items = payload.remove('items');
    if (type == 'order' &&
        (payload['order_number'] == null ||
            payload['order_number'].toString().trim().isEmpty)) {
      // Cloud orders created before schema v80 have no order number. SQLite
      // requires one, so use a deterministic value that is stable on replay.
      payload['order_number'] = 'SYNC-$id';
    }
    final row = await this._normalizeRowForLocalSchema(
      db,
      table,
      {...payload, 'id': id, 'is_synced': 1},
    );
    if (type == 'order') {
      await this._disambiguateOrderNumber(db, row, id);
    }
    if ((type == 'order' || type == 'sale') && row['customer_id'] != null) {
      final customerId = row['customer_id'].toString().trim();
      if (customerId.isNotEmpty) {
        final existingCust = await db.query(
          'customers',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [customerId],
          limit: 1,
        );
        if (existingCust.isEmpty) {
          final now = DateTime.now().toUtc().toIso8601String();
          final customerName = (payload['customer_name'] as String?)?.trim();
          final customerPhone = (payload['customer_phone'] as String?)?.trim();
          await db.insert(
            'customers',
            {
              'id': customerId,
              'name': customerName?.isNotEmpty == true
                  ? customerName!
                  : 'Müşteri ($customerId)',
              'phone': customerPhone,
              'created_at': now,
              'updated_at': now,
              'is_synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    }
    if (type == 'customer') {
      // Server balance is a cache and uses the opposite sign convention.
      // The immutable local ledger is the sole source for this projection.
      row.remove('balance');
    }
    if (type == 'financial_transaction') {
      final existing = await db.query(
        table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final prev = existing.first;
        final amountChanged =
            (_syncDouble(prev['amount']) - _syncDouble(row['amount'])).abs() >
                0.001;
        final paidChanged =
            (_syncDouble(prev['paid_amount']) - _syncDouble(row['paid_amount']))
                    .abs() >
                0.001;
        final debtChanged =
            (_syncDouble(prev['debt_amount']) - _syncDouble(row['debt_amount']))
                    .abs() >
                0.001;
        final customerChanged =
            prev['customer_id']?.toString() != row['customer_id']?.toString();
        if (amountChanged || paidChanged || debtChanged || customerChanged) {
          await db.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');
          try {
            await db.update(table, row, where: 'id = ?', whereArgs: [id]);
          } finally {
            await db.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
          }
        } else if ((prev['is_synced'] as num?)?.toInt() != 1) {
          await db.update(table, {'is_synced': 1},
              where: 'id = ?', whereArgs: [id]);
        }
        return;
      }
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
      return;
    }
    final updated =
        await db.update(table, row, where: 'id = ?', whereArgs: [id]);
    if (updated == 0) {
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
    }
    if (items is List && (type == 'sale' || type == 'order')) {
      final itemTable = type == 'sale' ? 'sale_items' : 'order_items';
      final parentColumn = type == 'sale' ? 'sale_id' : 'order_id';
      await db.delete(itemTable, where: '$parentColumn = ?', whereArgs: [id]);
      for (var index = 0; index < items.length; index++) {
        final source = Map<String, dynamic>.from(items[index] as Map);
        final productId = source['product_id']?.toString().trim();
        if (productId == null || productId.isEmpty) continue;

        final existingProd = await db.query(
          'products',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (existingProd.isEmpty) {
          final now = DateTime.now().toUtc().toIso8601String();
          final prodName = (source['product_name'] as String?)?.trim();
          await db.insert(
            'products',
            {
              'id': productId,
              'name': prodName?.isNotEmpty == true
                  ? prodName!
                  : 'Ürün ($productId)',
              'price': _syncDouble(source['unit_price']),
              'quantity': 0,
              'category': 'Genel',
              'created_at': now,
              'updated_at': now,
              'is_synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }

        final quantity = _syncDouble(source['quantity']);
        final unitPrice = _syncDouble(source['unit_price']);
        await db.insert(
            itemTable,
            {
              'id': source['id'] ?? 'sync-$id-$productId-$index',
              parentColumn: id,
              'product_id': productId,
              'product_name': source['product_name'],
              'quantity': quantity,
              'unit_price': unitPrice,
              if (type == 'sale') 'subtotal': quantity * unitPrice,
              'created_at': source['created_at'] ??
                  DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<void> _disambiguateOrderNumber(
    Transaction db,
    Map<String, Object?> row,
    String id,
  ) async {
    final orderNumber = row['order_number']?.toString().trim() ?? '';
    if (orderNumber.isEmpty) return;

    final collision = await db.query(
      'orders',
      columns: const ['id'],
      where: 'order_number = ? AND id <> ?',
      whereArgs: [orderNumber, id],
      limit: 1,
    );
    if (collision.isEmpty) return;

    // Including the globally unique entity ID makes the value deterministic
    // across retries and avoids silently merging two unrelated orders.
    row['order_number'] = '$orderNumber-$id';
  }

  Future<void> _applyRefund(
      Transaction db, String id, Map<String, dynamic> payload) async {
    final existing = await db.query('refunds',
        columns: const ['id'], where: 'id=?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty) return;
    final saleId = payload['sale_id']?.toString() ?? '';
    final sales =
        await db.query('sales', where: 'id=?', whereArgs: [saleId], limit: 1);
    if (sales.isEmpty) throw StateError('refund_sale_missing');
    final sale = sales.first;
    final snapshotProjection = payload['_snapshot_projection'] == true;
    final rawItems = payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw StateError('refund_items_missing');
    }
    final normalized = <Map<String, Object?>>[];
    var amount = 0.0;
    for (final value in rawItems) {
      final item = Map<String, dynamic>.from(value as Map);
      final saleItemId = item['sale_item_id']?.toString() ?? '';
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      final rows = await db.rawQuery(
          '''SELECT si.*,COALESCE((SELECT SUM(ri.quantity)
        FROM refund_items ri WHERE ri.sale_item_id=si.id),0) refunded_quantity
        FROM sale_items si WHERE si.id=? AND si.sale_id=?''',
          [saleItemId, saleId]);
      if (rows.isEmpty || quantity <= 0) {
        throw StateError('invalid_refund_item');
      }
      final row = rows.first;
      final sold = (row['quantity'] as num).toDouble();
      final refunded = (row['refunded_quantity'] as num).toDouble();
      if (quantity > sold - refunded) {
        throw StateError('invalid_refund_quantity');
      }
      final unit = (row['subtotal'] as num).toDouble() / sold;
      final subtotal = double.parse((unit * quantity).toStringAsFixed(2));
      amount += subtotal;
      normalized.add({
        'sale_item_id': saleItemId,
        'product_id': row['product_id'],
        'quantity': quantity,
        'unit_refund_amount': unit,
        'subtotal': subtotal
      });
    }
    amount = double.parse(amount.toStringAsFixed(2));
    final now = DateTime.now().toUtc().toIso8601String();
    final method = payload['refund_method']?.toString() ?? 'balance';
    final reason = payload['reason']?.toString() ?? '';
    await db.insert('refunds', {
      'id': id,
      'sale_id': saleId,
      'amount': amount,
      'refund_method': method,
      'external_reference': payload['external_reference'],
      'reason': reason,
      'status': 'completed',
      'created_at': now
    });
    for (final row in normalized) {
      await db.insert('refund_items',
          {'id': 'sync-$id-${row['sale_item_id']}', 'refund_id': id, ...row});
      if (!snapshotProjection) {
        await db.rawUpdate(
            'UPDATE products SET quantity=quantity+?,updated_at=? WHERE id=?',
            [row['quantity'], now, row['product_id']]);
      }
    }
    final previous = (sale['refunded_amount'] as num?)?.toDouble() ?? 0;
    final total = (sale['total_amount'] as num).toDouble();
    final newRefunded = double.parse((previous + amount).toStringAsFixed(2));
    await db.update(
        'sales',
        {
          'refunded_amount': newRefunded,
          'fsm_state':
              newRefunded >= total - 0.01 ? 'refunded' : 'partially_refunded',
          'updated_at': now
        },
        where: 'id=?',
        whereArgs: [saleId]);
    final customerId = sale['customer_id']?.toString();
    if (!snapshotProjection && customerId != null && customerId.isNotEmpty) {
      await db.insert(
          'financial_transactions',
          {
            'id': 'refund-$id',
            'type': 'refund',
            'customer_id': customerId,
            'amount': amount,
            'paid_amount': method == 'balance' ? 0.0 : amount,
            'debt_amount': 0.0,
            'reference_id': id,
            'description': reason,
            'payment_method': method,
            'created_at': now,
            'is_synced': 1
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Sync payloads outlive individual client schema versions. Only write
  /// columns present in the receiving SQLite table and fill mandatory audit
  /// timestamps when an older producer omitted them.
  Future<Map<String, Object?>> _normalizeRowForLocalSchema(
    Transaction db,
    String table,
    Map<String, dynamic> source,
  ) async {
    final schema = await db.rawQuery('PRAGMA table_info($table)');
    final columns = schema
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();
    final row = <String, Object?>{};
    for (final entry in source.entries) {
      if (!columns.contains(entry.key)) continue;
      final val = entry.value;
      if (val == null) {
        row[entry.key] = null;
      } else if (val is Map || val is List) {
        row[entry.key] = jsonEncode(val);
      } else if (val is bool) {
        row[entry.key] = val ? 1 : 0;
      } else {
        row[entry.key] = val;
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    if (columns.contains('created_at') && row['created_at'] == null) {
      row['created_at'] = now;
    }
    if (columns.contains('updated_at') && row['updated_at'] == null) {
      row['updated_at'] = row['created_at'] ?? now;
    }
    return row;
  }
}
