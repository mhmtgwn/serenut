part of 'sync_v4_service.dart';

extension SyncV4Materializer on SyncV4Service {
  @visibleForTesting
  Future<void> applyChangeForTesting(Transaction db, Map<String, dynamic> change) =>
      _apply(db, change);

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
      await _applyRefund(db, id, payload);
      return;
    }
    final table = switch (type) {
      'product' => 'products',
      'customer' => 'customers',
      'order' => 'orders',
      'sale' => 'sales',
      'financial_transaction' => 'financial_transactions',
      'cash_count' => 'cash_counts',
      'cash_expense' => 'cash_expenses',
      'gib_invoice' => 'gib_invoices',
      'customer_installment_plan' => 'customer_installment_plans',
      'customer_installment' => 'customer_installments',
      'warehouse' => 'warehouses',
      'customer_hazelnut_escrow' => 'customer_hazelnut_escrow',
      'warehouse_hazelnut_movement' => 'warehouse_hazelnut_movements',
      'hazelnut_price_cut' => 'hazelnut_price_cuts',
      _ => null,
    };
    if (table == null) {
      debugPrint('[SyncV4] ⚠️ Unknown entity type: "$type" (id: $id)');
      try {
        await db.insert('sync_quarantine_v4', {
          'source': 'materializer',
          'mutation_id': change['mutation_id']?.toString(),
          'entity_type': type,
          'entity_id': id,
          'operation': change['operation']?.toString() ?? 'UPSERT',
          'payload': jsonEncode(payload),
          'error_message': 'unknown_entity_type',
          'quarantined_at': DateTime.timestamp().toIso8601String(),
        });
      } catch (e) {
        debugPrint('[SyncV4] Quarantine record failed: $e');
      }
      return;
    }
    if (change['operation'] == 'DELETE') {
      final schema = await db.rawQuery('PRAGMA table_info($table)');
      final columns = schema
          .map((column) => column['name']?.toString())
          .whereType<String>()
          .toSet();
      if (columns.contains('is_deleted')) {
        final tombstone = <String, Object?>{
          'is_deleted': 1,
          if (columns.contains('deleted_at'))
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
          if (columns.contains('is_synced')) 'is_synced': 1,
        };
        if (columns.contains('is_active')) {
          tombstone['is_active'] = 0;
        }
        await db.update(table, tombstone, where: 'id = ?', whereArgs: [id]);
      } else {
        await db.delete(table, where: 'id = ?', whereArgs: [id]);
      }
      return;
    }
    if (type == 'cash_count') {
      if (payload.containsKey('count_date') && !payload.containsKey('date')) {
        payload['date'] = payload['count_date'];
      } else if (payload.containsKey('date') && !payload.containsKey('count_date')) {
        payload['count_date'] = payload['date'];
      }
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
    if ((type == 'sale' || type == 'order' || type == 'financial_transaction') &&
        (payload['customer_id'] == null ||
            payload['customer_id'].toString().trim().isEmpty)) {
      // Sales, orders and ledger transactions require a non-null customer_id referencing customers(id).
      // Quick/walk-in transactions default to the canonical cash customer ('').
      payload['customer_id'] = '';
    }
    final row = await _normalizeRowForLocalSchema(
      db,
      table,
      {...payload, 'id': id, 'is_synced': 1},
    );
    if ((type == 'sale' || type == 'order' || type == 'financial_transaction') &&
        (row['customer_id'] == null ||
            row['customer_id'].toString().trim().isEmpty)) {
      row['customer_id'] = '';
    }
    if (type == 'order') {
      await _disambiguateOrderNumber(db, row, id);
    }
    if ((type == 'order' ||
            type == 'sale' ||
            type == 'customer_installment_plan' ||
            type == 'customer_installment' ||
            type == 'financial_transaction') &&
        row['customer_id'] != null) {
      final customerId = row['customer_id'].toString().trim();
      final existingCust = await db.query(
        'customers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (existingCust.isEmpty) {
        final now = DateTime.now().toUtc().toIso8601String();
        final rawCustName = (payload['customer_name'] as String?)?.trim();
        final customerName = customerId.isEmpty
            ? 'Peşin Müşteri'
            : (rawCustName?.isNotEmpty == true
                ? rawCustName!
                : 'Müşteri ($customerId)');
        final customerPhone = (payload['customer_phone'] as String?)?.trim();
        await db.insert(
          'customers',
          {
            'id': customerId,
            'name': customerName,
            'phone': customerPhone ?? '',
            'created_at': now,
            'updated_at': now,
            'is_synced': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    if (type == 'customer') {
      // Server balance is a cache and uses the opposite sign convention.
      // The immutable local ledger is the sole source for this projection.
      row.remove('balance');
    }
    if (type == 'financial_transaction') {
      if (row['customer_id'] == null ||
          row['customer_id'].toString().trim().isEmpty) {
        row['customer_id'] = '';
      }
      final existing = await db.query(
        table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        // Append-only ledger invariant: Existing transactions are immutable financial facts.
        // Only synchronization metadata (is_synced) can be updated on an acknowledged record.
        final prev = existing.first;
        if ((prev['is_synced'] as num?)?.toInt() != 1) {
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
      if (type == 'cash_count' && row['date'] != null) {
        final byDate = await db.update(table, row,
            where: 'date = ?', whereArgs: [row['date']]);
        if (byDate == 0) {
          await db.insert(table, row,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } else {
        await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
      }
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
              if (type == 'sale')
                'unit_price_minor': (unitPrice * 100).round(),
              if (type == 'sale') 'subtotal': quantity * unitPrice,
              if (type == 'sale')
                'subtotal_minor': ((quantity * unitPrice) * 100).round(),
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
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final rows = await db.rawQuery(
          '''SELECT si.*,COALESCE((SELECT SUM(ri.quantity)
        FROM refund_items ri WHERE ri.sale_item_id=si.id),0) refunded_quantity
        FROM sale_items si WHERE si.id=? AND si.sale_id=?''',
          [saleItemId, saleId]);
      if (rows.isEmpty || quantity <= 0.0001) {
        throw StateError('invalid_refund_item');
      }
      final row = rows.first;
      final sold = (row['quantity'] as num).toDouble();
      final refunded = (row['refunded_quantity'] as num).toDouble();
      if (quantity > (sold - refunded) + 0.0001) {
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
    // Universal NOT NULL guard: If an older client schema has a NOT NULL column
    // without a DEFAULT, and the sync payload omitted or set it to null, provide
    // a safe zero-value fallback so SQLite never crashes with NOT NULL constraint violation.
    for (final colInfo in schema) {
      final colName = colInfo['name']?.toString();
      if (colName == null || !columns.contains(colName)) continue;
      final isNotNull = colInfo['notnull'] == 1;
      final hasDefault = colInfo['dflt_value'] != null;
      final isPk = colInfo['pk'] != 0;
      if (isNotNull && !hasDefault && !isPk && row[colName] == null) {
        final colType = (colInfo['type']?.toString() ?? '').toUpperCase();
        if (colType.contains('INT')) {
          row[colName] = 0;
        } else if (colType.contains('REAL') ||
            colType.contains('NUM') ||
            colType.contains('DOUB') ||
            colType.contains('FLOAT')) {
          row[colName] = 0.0;
        } else {
          row[colName] = '';
        }
      }
    }
    // Dual-write: Populate *_minor currency columns if local schema contains them
    for (final col in columns) {
      if (col.endsWith('_minor') && row[col] == null) {
        final baseName = col.substring(0, col.length - 6);
        if (source.containsKey(baseName) && source[baseName] != null) {
          final val = _syncDouble(source[baseName]);
          row[col] = (val * 100).round();
        }
      }
    }
    return row;
  }
}
