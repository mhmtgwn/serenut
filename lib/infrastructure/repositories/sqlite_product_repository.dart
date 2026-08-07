import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

class SqliteProductRepository implements IProductRepository {
  final DbGateway _gateway;
  final DatasetLoaderService? _datasetLoader;

  SqliteProductRepository(this._gateway, [this._datasetLoader]);

  DbExecutor get _executor => _gateway;

  bool get _hasDataset =>
      _datasetLoader != null && _datasetLoader!.activeDb != null;
  String get _market => _datasetLoader?.selectedMarket ?? 'Migros';

  Future<List<ProductEntity>> _queryProducts(
      {String? where, List<Object?>? whereArgs, String? orderBy}) async {
    if (_hasDataset) {
      const selectPart = '''
        SELECT p.barcode as id, p.name, COALESCE(p.brand, '') as description, 
               COALESCE(pr.price, 0.0) as price, 99 as quantity, p.category, 
               CAST(COALESCE(p.vat_rate, 18.0) AS INTEGER) as vat
        FROM products p
        LEFT JOIN prices pr ON p.barcode = pr.barcode AND pr.market_name = ?
      ''';

      String sql = selectPart;
      final args = <Object?>[_market];

      if (where != null) {
        // GÜVENLİK/SAĞLAMLIK NOTU: rewrittenWhere değişkeni yalnızca repository içindeki hardcoded (sabit) WHERE
        // şablonları üzerinde yapısal dönüşümler (sütun adı eşlemeleri gibi) yapar. Arama terimi, kategori veya ID
        // gibi kullanıcı girdileri asla doğrudan bu stringe eklenmez (SQL injection riski yoktur). Tüm dinamik girdiler
        // placeholders (?) aracılığıyla whereArgs/args listesiyle rawQuery'ye parametre olarak güvenle bağlanır.
        String rewrittenWhere = where
            .replaceAll('is_active = 1', '1=1')
            .replaceAll('id = ?', 'p.barcode = ?')
            .replaceAll('category = ?', 'p.category = ?')
            .replaceAll('name LIKE ?', 'p.name LIKE ?');
        sql += ' WHERE $rewrittenWhere';
      }

      if (whereArgs != null) {
        args.addAll(whereArgs);
      }

      if (orderBy != null) {
        String rewrittenOrder = orderBy.replaceAll('category', 'p.category');
        // DÜZELTME: SQL injection koruması — sadece izin verilen sütunlar kabul edilir
        const allowedOrderCols = {
          'p.category',
          'p.name',
          'p.quantity',
          'p.price',
          'p.category ASC',
          'p.category DESC',
          'p.name ASC',
          'p.name DESC',
          'p.quantity ASC',
          'p.quantity DESC',
          'p.price ASC',
          'p.price DESC',
          'quantity ASC',
          'quantity DESC',
        };
        if (!allowedOrderCols.contains(rewrittenOrder)) {
          rewrittenOrder = 'p.name ASC'; // güvenli varsayılan
        }
        sql += ' ORDER BY $rewrittenOrder';
      }

      final rows = await _datasetLoader!.activeDb!.rawQuery(sql, args);
      final datasetProducts = rows
          .map((row) => ProductEntity(
                id: row['id'] as String,
                name: row['name'] as String,
                description: row['description'] as String,
                price: (row['price'] as num).toDouble(),
                quantity: row['quantity'] as int,
                category: row['category'] as String,
                vat: row['vat'] as int?,
              ))
          .toList();

      if (datasetProducts.isEmpty) return [];

      final ids = datasetProducts.map((p) => p.id).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      final localOverrides = await _executor.query(
        'products',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      final overrideMap = {
        for (var row in localOverrides) row['id'] as String: row
      };

      final result = <ProductEntity>[];
      for (final p in datasetProducts) {
        final override = overrideMap[p.id];
        if (override != null) {
          final isActive = override['is_active'] as int? ?? 1;
          final isDeleted = override['is_deleted'] as int? ?? 0;
          if (isActive == 0 || isDeleted == 1) {
            continue;
          }
          result.add(ProductEntity(
            id: p.id,
            name: override['name'] as String? ?? p.name,
            description: override['description'] as String? ?? p.description,
            price: (override['price'] as num?)?.toDouble() ?? p.price,
            purchasePrice: (override['purchase_price'] as num?)?.toDouble() ??
                p.purchasePrice,
            quantity: (override['quantity'] as num?)?.toInt() ?? p.quantity,
            minStock: (override['min_stock'] as num?)?.toInt() ?? p.minStock,
            brand: override['brand'] as String? ?? p.brand,
            unit: override['unit'] as String? ?? p.unit,
            shelfCode: override['shelf_code'] as String? ?? p.shelfCode,
            category: override['category'] as String? ?? p.category,
            vat: override['vat'] as int? ?? p.vat,
            imageUrl: override['image_url'] as String? ?? p.imageUrl,
            saleType: override['sale_type'] as String? ?? p.saleType,
            minimumWeightGrams:
                (override['minimum_weight_grams'] as num?)?.toInt() ??
                    p.minimumWeightGrams,
          ));
        } else {
          result.add(p);
        }
      }
      return result;
    } else {
      final rows = await _executor.query('products',
          where: where, whereArgs: whereArgs, orderBy: orderBy);
      return rows.map((row) => ProductEntity.fromMap(row)).toList();
    }
  }

  @override
  Future<List<ProductEntity>> findAll() async {
    return await _queryProducts(where: 'is_active = 1');
  }

  @override
  Future<ProductEntity?> findById(dynamic id) async {
    final list = await _queryProducts(
        where: 'id = ? AND is_active = 1', whereArgs: [id]);
    if (list.isEmpty) return null;
    return list.first;
  }

  @override
  Future<int> create(ProductEntity product) async {
    return _gateway.transaction(() async {
      final payload = {
        ...product.toMap(),
        'is_synced': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String()
      };
      final result = await _executor.insert('products', payload);
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'product',
          entityId: product.id,
          operation: 'UPSERT',
          payload: payload);
      return result;
    });
  }

  @override
  Future<int> update(ProductEntity product, {String? oldId}) async {
    final targetId = oldId ?? product.id;
    if (oldId != null && oldId != product.id) {
      final alreadyExists = await exists(product.id);
      if (alreadyExists) {
        throw Exception(
            'Bu barkod kodu (${product.id}) zaten başka bir üründe kullanılıyor.');
      }
      await _gateway.transaction(() async {
        await _executor.update(
          'products',
          {
            ...product.toMap(),
            'is_synced': 0,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [oldId],
        );
        // 1. Send DELETE tombstone for oldId so other devices remove the previous ID/barcode
        await SyncOutboxV4.enqueue(_executor,
            entityType: 'product',
            entityId: oldId,
            operation: 'DELETE',
            payload: {'id': oldId, 'is_deleted': 1});

        // 2. Send UPSERT for new product ID/barcode
        await SyncOutboxV4.enqueue(_executor,
            entityType: 'product',
            entityId: product.id,
            operation: 'UPSERT',
            payload: {...product.toMap(), 'is_synced': 0});
        await _executor.update(
          'sale_items',
          {'product_id': product.id},
          where: 'product_id = ?',
          whereArgs: [oldId],
        );
        await _executor.update(
          'order_items',
          {'product_id': product.id},
          where: 'product_id = ?',
          whereArgs: [oldId],
        );
        await _updateDeferredPricesAndOrders(product.id, product.price);
      });
      return 1;
    }

    return _gateway.transaction(() async {
      final payload = {
        ...product.toMap(),
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String()
      };
      final result = await _executor
          .update('products', payload, where: 'id = ?', whereArgs: [targetId]);
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'product',
          entityId: targetId,
          operation: 'UPSERT',
          payload: payload);

      await _updateDeferredPricesAndOrders(targetId, product.price);
      return result;
    });
  }

  Future<void> _updateDeferredPricesAndOrders(
      String productId, double newPrice) async {
    final nowStr = DateTime.now().toIso8601String();

    // 1. Update open order items & order totals
    final affectedOrderRows = await _executor.rawQuery('''
      SELECT DISTINCT oi.order_id
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE oi.product_id = ? AND o.status IN ('created', 'preparing', 'ready') AND o.is_deleted = 0
    ''', [productId]);

    if (affectedOrderRows.isNotEmpty) {
      await _executor.rawUpdate('''
        UPDATE order_items
        SET unit_price = ?
        WHERE product_id = ? AND order_id IN (
          SELECT id FROM orders WHERE status IN ('created', 'preparing', 'ready') AND is_deleted = 0
        )
      ''', [newPrice, productId]);

      for (final row in affectedOrderRows) {
        final orderId = row['order_id'] as String;
        final totalResult = await _executor.rawQuery('''
          SELECT SUM(quantity * unit_price) as total FROM order_items WHERE order_id = ?
        ''', [orderId]);
        final newTotal =
            (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;
        await _executor.rawUpdate('''
          UPDATE orders
          SET total_amount = ?, updated_at = ?, is_synced = 0
          WHERE id = ?
        ''', [newTotal, nowStr, orderId]);
      }
    }

    // 2. Update open/deferred sale items & sale totals & customer debt/balances
    final affectedSaleRows = await _executor.rawQuery('''
      SELECT DISTINCT si.sale_id, s.customer_id, s.paid_amount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE si.product_id = ? AND s.status != 'cancelled' AND s.is_deleted = 0
        AND (s.payment_method = 'debt' OR s.paid_amount < s.total_amount)
    ''', [productId]);

    if (affectedSaleRows.isNotEmpty) {
      await _executor.rawUpdate('''
        UPDATE sale_items
        SET unit_price = ?, subtotal = quantity * ?
        WHERE product_id = ? AND sale_id IN (
          SELECT id FROM sales WHERE status != 'cancelled' AND is_deleted = 0 AND (payment_method = 'debt' OR paid_amount < total_amount)
        )
      ''', [newPrice, newPrice, productId]);

      final affectedCustomerIds = <String>{};

      await _executor.update('ledger_bypass_flag', {'active': 1});
      try {
        for (final row in affectedSaleRows) {
          final saleId = row['sale_id'] as String;
          final customerId = row['customer_id'] as String;
          final paidAmount = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;

          if (customerId.isNotEmpty) affectedCustomerIds.add(customerId);

          final totalResult = await _executor.rawQuery('''
            SELECT SUM(subtotal) as total FROM sale_items WHERE sale_id = ?
          ''', [saleId]);
          final newTotal =
              (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;
          final newDebt = (newTotal - paidAmount).clamp(0.0, double.infinity);

          await _executor.rawUpdate('''
            UPDATE sales
            SET total_amount = ?, updated_at = ?, is_synced = 0
            WHERE id = ?
          ''', [newTotal, nowStr, saleId]);

          await _executor.rawUpdate('''
            UPDATE financial_transactions
            SET amount = ?, debt_amount = ?
            WHERE reference_id = ? AND type = 'sale'
          ''', [newTotal, newDebt, saleId]);
        }
      } finally {
        await _executor.update('ledger_bypass_flag', {'active': 0});
      }

      for (final customerId in affectedCustomerIds) {
        final debtResult = await _executor.rawQuery('''
          SELECT SUM(debt_amount) as total_debt
          FROM financial_transactions
          WHERE customer_id = ? AND is_deleted = 0
        ''', [customerId]);
        final totalDebt =
            (debtResult.first['total_debt'] as num?)?.toDouble() ?? 0.0;

        final paymentsResult = await _executor.rawQuery('''
          SELECT SUM(amount) as total_payments
          FROM financial_transactions
          WHERE customer_id = ? AND type = 'collection' AND is_deleted = 0
        ''', [customerId]);
        final totalPayments =
            (paymentsResult.first['total_payments'] as num?)?.toDouble() ?? 0.0;

        final newBalance = totalPayments - totalDebt;
        await _executor.rawUpdate('''
          UPDATE customers
          SET balance = ?, updated_at = ?, is_synced = 0
          WHERE id = ?
        ''', [newBalance, nowStr, customerId]);
      }
    }
  }

  @override
  Future<int> delete(dynamic id) async {
    // Soft delete
    return _gateway.transaction(() async {
      final payload = {
        'is_active': 0,
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
      };
      final result = await _executor
          .update('products', payload, where: 'id = ?', whereArgs: [id]);
      await SyncOutboxV4.enqueue(_executor,
          entityType: 'product',
          entityId: id.toString(),
          operation: 'DELETE',
          payload: payload);
      return result;
    });
  }

  @override
  Future<int> count() async {
    if (_hasDataset) {
      final result = await _datasetLoader!.activeDb!
          .rawQuery('SELECT COUNT(*) as count FROM products');
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await _executor.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE is_active = 1',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<bool> exists(dynamic id) async {
    if (_hasDataset) {
      final result = await _datasetLoader!.activeDb!
          .rawQuery('SELECT 1 FROM products WHERE barcode = ? LIMIT 1', [id]);
      return result.isNotEmpty;
    }
    final result = await _executor.query(
      'products',
      where: 'id = ? AND is_active = 1',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  @override
  Future<List<ProductEntity>> searchByName(String query) async {
    return await _queryProducts(
        where: 'name LIKE ? AND is_active = 1', whereArgs: ['%$query%']);
  }

  @override
  Future<List<ProductEntity>> getByCategory(String category) async {
    return await _queryProducts(
        where: 'category = ? AND is_active = 1', whereArgs: [category]);
  }

  @override
  Future<Map<String, List<ProductEntity>>> getGroupedByCategory() async {
    final entities =
        await _queryProducts(where: 'is_active = 1', orderBy: 'category');

    final grouped = <String, List<ProductEntity>>{};
    for (final entity in entities) {
      grouped.putIfAbsent(entity.category, () => []).add(entity);
    }
    return grouped;
  }

  @override
  Future<void> decreaseStock(String productId, int quantity) async {
    if (_hasDataset) {
      final localRes = await _executor
          .query('products', where: 'id = ?', whereArgs: [productId]);
      if (localRes.isEmpty) {
        final original = await findById(productId);
        if (original != null) {
          final newQty = original.quantity - quantity;
          final payload = {
            'id': original.id,
            'name': original.name,
            'barcode': original.id,
            'price': original.price,
            'quantity': newQty,
            'category': original.category,
            'vat': original.vat ?? 18,
            'is_active': 1,
            'is_deleted': 0,
            'is_synced': 0,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
          await _gateway.transaction(() async {
            await _executor.insert('products', payload);
            final masterPayload = Map<String, dynamic>.from(payload)
              ..['quantity'] = original.quantity;
            await SyncOutboxV4.enqueue(
              _executor,
              entityType: 'product',
              entityId: productId,
              operation: 'UPSERT',
              payload: masterPayload,
            );
          });
          return;
        }
      }
    }
    await _gateway.transaction(() async {
      await _executor.rawUpdate(
        'UPDATE products SET quantity = quantity - ?, updated_at = ?, is_synced = 0 WHERE id = ?',
        [quantity, DateTime.now().toIso8601String(), productId],
      );
      // Stock is part of the sale aggregate and is materialized by the server
      // exactly once. Emitting an absolute product quantity here would apply
      // the same sale twice during sync.
    });
  }

  @override
  Future<void> increaseStock(String productId, int quantity) async {
    if (_hasDataset) {
      final localRes = await _executor
          .query('products', where: 'id = ?', whereArgs: [productId]);
      if (localRes.isEmpty) {
        final original = await findById(productId);
        if (original != null) {
          final newQty = original.quantity + quantity;
          final payload = {
            'id': original.id,
            'name': original.name,
            'barcode': original.id,
            'price': original.price,
            'quantity': newQty,
            'category': original.category,
            'vat': original.vat ?? 18,
            'is_active': 1,
            'is_deleted': 0,
            'is_synced': 0,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
          await _gateway.transaction(() async {
            await _executor.insert('products', payload);
            final masterPayload = Map<String, dynamic>.from(payload)
              ..['quantity'] = original.quantity;
            await SyncOutboxV4.enqueue(
              _executor,
              entityType: 'product',
              entityId: productId,
              operation: 'UPSERT',
              payload: masterPayload,
            );
          });
          return;
        }
      }
    }
    await _gateway.transaction(() async {
      await _executor.rawUpdate(
        'UPDATE products SET quantity = quantity + ?, updated_at = ?, is_synced = 0 WHERE id = ?',
        [quantity, DateTime.now().toIso8601String(), productId],
      );
      // Refund/cancellation aggregates own their inventory movements.
    });
  }

  @override
  Future<List<ProductEntity>> getLowStockProducts(int threshold) async {
    final rows = await _executor.query(
      'products',
      where: 'quantity <= ? AND is_active = 1',
      whereArgs: [threshold],
      orderBy: 'quantity ASC',
    );
    return rows.map((row) => ProductEntity.fromMap(row)).toList();
  }

  @override
  Future<List<ProductEntity>> findFiltered({
    String? searchQuery,
    String? category,
    String? stockFilter,
    String? sortBy,
    int? limit,
    int? offset,
  }) async {
    final List<String> whereClauses = ['is_active = 1'];
    final List<dynamic> whereArgs = [];

    if (category != null && category.isNotEmpty) {
      whereClauses.add('category = ?');
      whereArgs.add(category);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClauses.add('(id LIKE ? OR name LIKE ? OR description LIKE ?)');
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }
    if (stockFilter == 'in_stock') {
      whereClauses.add('quantity > 0');
    } else if (stockFilter == 'critical') {
      whereClauses.add('quantity <= min_stock');
    }

    final String whereString = whereClauses.join(' AND ');

    final orderBy = switch (sortBy) {
      'price_asc' => 'price ASC',
      'price_desc' => 'price DESC',
      'best_selling' =>
        '(SELECT COALESCE(SUM(si.quantity), 0) FROM sale_items si '
            'JOIN sales s ON s.id = si.sale_id '
            "WHERE si.product_id = products.id AND s.status != 'cancelled') DESC, name ASC",
      _ => 'name ASC',
    };
    final rows = await _executor.query(
      'products',
      where: whereString,
      whereArgs: whereArgs,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
    );
    return rows.map((row) => ProductEntity.fromMap(row)).toList();
  }

  @override
  Future<List<String>> getCategories() async {
    final rows = await _executor.rawQuery(
      'SELECT DISTINCT category FROM products WHERE is_active = 1 ORDER BY category ASC',
    );
    return rows
        .map((row) => (row['category'] as String?) ?? '')
        .where((c) => c.isNotEmpty)
        .toList();
  }
}
