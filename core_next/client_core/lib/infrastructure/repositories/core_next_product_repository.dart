// core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart
// SERENUT OS — STAGE 10.8.11
// Authoritative Core Next Product & Stock Repository Bridge
// Provides complete IProductRepository contract over serenut_core_v2.db

import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/config/utils.dart';
import '../database/app_database.dart';
import '../sync/sync_v4_payload_adapter.dart';

class CoreNextProductRepository implements IProductRepository {
  final DatabaseExecutor _db;

  CoreNextProductRepository(this._db);

  factory CoreNextProductRepository.fromCoreAppDatabase(CoreAppDatabase coreDb) {
    return CoreNextProductRepository(coreDb.db);
  }

  ProductEntity _rowToEntity(Map<String, dynamic> row) {
    final priceCents = (row['price_cents'] as num?)?.toInt() ?? 0;
    final costCents = (row['cost_price_cents'] as num?)?.toInt() ?? 0;
    final stockQty = (row['stock_quantity'] as num?) ?? 0;
    final critThreshold = (row['critical_threshold'] as num?) ?? 5;
    final categoryName = row['category_name']?.toString() ??
        row['category_id']?.toString() ??
        'Genel';

    return ProductEntity(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      description: row['name']?.toString() ?? '',
      price: priceCents / 100.0,
      purchasePrice: costCents / 100.0,
      quantity: stockQty,
      minStock: critThreshold,
      brand: '',
      unit: row['unit']?.toString() ?? 'adet',
      shelfCode: '',
      category: categoryName,
      vat: (row['vat_rate'] as num?)?.toInt() ?? 20,
      imageUrl: row['image_url']?.toString(),
      saleType: row['sale_type']?.toString() ?? 'piece',
      minimumWeightGrams: (row['minimum_weight_grams'] as num?)?.toInt() ?? 20,
      origin: 'TÜRKİYE',
    );
  }

  Future<void> _ensureCategoryExists(String? categoryName) async {
    if (categoryName == null || categoryName.trim().isEmpty) return;
    final cleanCat = categoryName.trim();
    await _db.rawInsert(
      '''
      INSERT OR IGNORE INTO categories (id, name, updated_at)
      VALUES (?, ?, ?)
      ''',
      [cleanCat, cleanCat, DateTime.now().millisecondsSinceEpoch],
    );
  }

  @override
  Future<List<ProductEntity>> findAll() async {
    final rows = await _db.rawQuery('''
      SELECT p.*, c.name as category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.is_deleted = 0 AND p.is_active = 1
      ORDER BY p.name COLLATE NOCASE ASC
    ''');
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<ProductEntity?> findById(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return null;
    final rows = await _db.rawQuery('''
      SELECT p.*, c.name as category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE (p.id = ? OR p.barcode = ?) AND p.is_deleted = 0
      LIMIT 1
    ''', [cleanId, cleanId]);

    if (rows.isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  @override
  Future<ProductEntity?> findProductById(String id) async {
    return findById(id);
  }

  @override
  Future<ProductEntity?> getByBarcode(String barcode) async {
    return findById(barcode);
  }

  @override
  Future<int> create(ProductEntity entity) async {
    await _ensureCategoryExists(entity.category);
    final now = DateTime.now().millisecondsSinceEpoch;
    final priceCents = (entity.price * 100).round();
    final costCents = (entity.purchasePrice * 100).round();
    final cleanId = entity.id.trim();

    await _db.insert(
      'products',
      {
        'id': cleanId,
        'barcode': cleanId,
        'name': entity.name.trim(),
        'category_id': entity.category.trim(),
        'price_cents': priceCents,
        'cost_price_cents': costCents,
        'vat_rate': entity.vat ?? 20,
        'unit': entity.unit,
        'sale_type': entity.saleType,
        'minimum_weight_grams': entity.minimumWeightGrams,
        'stock_quantity': entity.quantity.toDouble(),
        'critical_threshold': entity.minStock.toDouble(),
        'image_url': entity.imageUrl,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Enqueue sync event
    try {
      final mutation = SyncV4PayloadAdapter.buildProductMutation(
        productId: cleanId,
        name: entity.name,
        priceCents: priceCents,
        costPriceCents: costCents,
        stockQuantity: entity.quantity,
        minStock: entity.minStock,
        category: entity.category,
        unit: entity.unit,
        saleType: entity.saleType,
        minimumWeightGrams: entity.minimumWeightGrams,
        vatRate: entity.vat,
        imageUrl: entity.imageUrl,
        isDeleted: false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        deterministicEventId: 'evt-prod-$cleanId-$now',
        operation: 'UPSERT',
      );
      await _db.insert(
        'sync_events',
        mutation.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      // Sync queueing error non-blocking for local commit
    }

    return 1;
  }

  @override
  Future<int> update(ProductEntity entity, {String? oldId}) async {
    await _ensureCategoryExists(entity.category);
    final now = DateTime.now().millisecondsSinceEpoch;
    final targetId = (oldId ?? entity.id).trim();
    final priceCents = (entity.price * 100).round();
    final costCents = (entity.purchasePrice * 100).round();

    final count = await _db.update(
      'products',
      {
        'id': entity.id.trim(),
        'barcode': entity.id.trim(),
        'name': entity.name.trim(),
        'category_id': entity.category.trim(),
        'price_cents': priceCents,
        'cost_price_cents': costCents,
        'vat_rate': entity.vat ?? 20,
        'unit': entity.unit,
        'sale_type': entity.saleType,
        'minimum_weight_grams': entity.minimumWeightGrams,
        'stock_quantity': entity.quantity.toDouble(),
        'critical_threshold': entity.minStock.toDouble(),
        'image_url': entity.imageUrl,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [targetId],
    );

    // Enqueue sync event
    try {
      final mutation = SyncV4PayloadAdapter.buildProductMutation(
        productId: entity.id.trim(),
        name: entity.name,
        priceCents: priceCents,
        costPriceCents: costCents,
        stockQuantity: entity.quantity,
        minStock: entity.minStock,
        category: entity.category,
        unit: entity.unit,
        saleType: entity.saleType,
        minimumWeightGrams: entity.minimumWeightGrams,
        vatRate: entity.vat,
        imageUrl: entity.imageUrl,
        isDeleted: false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        deterministicEventId: 'evt-prod-${entity.id}-$now',
        operation: 'UPSERT',
      );
      await _db.insert(
        'sync_events',
        mutation.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {}

    return count;
  }

  @override
  Future<int> delete(String id) async {
    return deleteProduct(id);
  }

  @override
  Future<int> deleteProduct(String id) async {
    final cleanId = id.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = await _db.update(
      'products',
      {
        'is_deleted': 1,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [cleanId],
    );

    try {
      final mutation = SyncV4PayloadAdapter.buildProductMutation(
        productId: cleanId,
        name: cleanId,
        priceCents: 0,
        stockQuantity: 0,
        isDeleted: true,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        deterministicEventId: 'evt-prod-del-$cleanId-$now',
        operation: 'DELETE',
      );
      await _db.insert(
        'sync_events',
        mutation.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {}

    return count;
  }

  @override
  Future<bool> exists(String id) async {
    final cleanId = id.trim();
    final rows = await _db.query(
      'products',
      columns: ['id'],
      where: '(id = ? OR barcode = ?) AND is_deleted = 0',
      whereArgs: [cleanId, cleanId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<int> count() async {
    final res = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE is_deleted = 0 AND is_active = 1',
    );
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<ProductEntity>> searchByName(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return findAll();

    final foldedCol = sqliteTurkishFold('p.name');
    final foldedQuery = clean.normalizeTurkish;

    final rows = await _db.rawQuery('''
      SELECT p.*, c.name as category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE ($foldedCol LIKE ? OR p.barcode LIKE ? OR p.id LIKE ?)
        AND p.is_deleted = 0 AND p.is_active = 1
      ORDER BY p.name COLLATE NOCASE ASC
      LIMIT 100
    ''', ['%$foldedQuery%', '%$clean%', '%$clean%']);

    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<ProductEntity>> getByCategory(String category) async {
    final clean = category.trim();
    final rows = await _db.rawQuery('''
      SELECT p.*, c.name as category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE (p.category_id = ? OR c.name = ?)
        AND p.is_deleted = 0 AND p.is_active = 1
      ORDER BY p.name COLLATE NOCASE ASC
    ''', [clean, clean]);
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<Map<String, List<ProductEntity>>> getGroupedByCategory() async {
    final all = await findAll();
    final grouped = <String, List<ProductEntity>>{};
    for (final p in all) {
      grouped.putIfAbsent(p.category, () => []).add(p);
    }
    return grouped;
  }

  @override
  Future<void> decreaseStock(String productId, num quantity) async {
    final cleanId = productId.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.rawUpdate(
      '''
      UPDATE products
      SET stock_quantity = stock_quantity - ?, updated_at = ?
      WHERE id = ?
      ''',
      [quantity.toDouble(), now, cleanId],
    );
  }

  @override
  Future<void> increaseStock(String productId, num quantity) async {
    final cleanId = productId.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.rawUpdate(
      '''
      UPDATE products
      SET stock_quantity = stock_quantity + ?, updated_at = ?
      WHERE id = ?
      ''',
      [quantity.toDouble(), now, cleanId],
    );
  }

  @override
  Future<List<ProductEntity>> getLowStockProducts(int threshold) async {
    final rows = await _db.rawQuery('''
      SELECT p.*, c.name as category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.stock_quantity <= ?
        AND p.is_deleted = 0 AND p.is_active = 1
      ORDER BY p.stock_quantity ASC
    ''', [threshold]);
    return rows.map(_rowToEntity).toList();
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
    final whereClauses = <String>['p.is_deleted = 0', 'p.is_active = 1'];
    final whereArgs = <dynamic>[];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final clean = searchQuery.trim();
      final foldedCol = sqliteTurkishFold('p.name');
      final foldedQuery = clean.normalizeTurkish;
      whereClauses.add('($foldedCol LIKE ? OR p.barcode LIKE ? OR p.id LIKE ?)');
      whereArgs.add('%$foldedQuery%');
      whereArgs.add('%$clean%');
      whereArgs.add('%$clean%');
    }

    if (category != null && category.trim().isNotEmpty && category != 'Tümü') {
      final cleanCat = category.trim();
      whereClauses.add('(p.category_id = ? OR c.name = ?)');
      whereArgs.add(cleanCat);
      whereArgs.add(cleanCat);
    }

    if (stockFilter != null) {
      if (stockFilter == 'low' || stockFilter == 'critical') {
        whereClauses.add('p.stock_quantity <= p.critical_threshold');
      } else if (stockFilter == 'out') {
        whereClauses.add('p.stock_quantity <= 0');
      } else if (stockFilter == 'in_stock') {
        whereClauses.add('p.stock_quantity > 0');
      }
    }

    String orderClause = 'ORDER BY p.name COLLATE NOCASE ASC';
    if (sortBy != null) {
      switch (sortBy) {
        case 'price_asc':
          orderClause = 'ORDER BY p.price_cents ASC';
          break;
        case 'price_desc':
          orderClause = 'ORDER BY p.price_cents DESC';
          break;
        case 'stock_asc':
          orderClause = 'ORDER BY p.stock_quantity ASC';
          break;
        case 'stock_desc':
          orderClause = 'ORDER BY p.stock_quantity DESC';
          break;
        case 'name_desc':
          orderClause = 'ORDER BY p.name COLLATE NOCASE DESC';
          break;
        default:
          orderClause = 'ORDER BY p.name COLLATE NOCASE ASC';
      }
    }

    final limitClause = limit != null ? 'LIMIT $limit' : '';
    final offsetClause = offset != null ? 'OFFSET $offset' : '';

    final sql = '''
      SELECT p.*, c.name as category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE ${whereClauses.join(' AND ')}
      $orderClause
      $limitClause $offsetClause
    ''';

    final rows = await _db.rawQuery(sql, whereArgs);
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<String>> getCategories() async {
    final rows = await _db.rawQuery('''
      SELECT DISTINCT COALESCE(c.name, p.category_id) as cat_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.is_deleted = 0 AND p.is_active = 1
        AND p.category_id IS NOT NULL AND p.category_id != ''
      ORDER BY cat_name COLLATE NOCASE ASC
    ''');
    return rows
        .map((r) => r['cat_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Future<ProductInventorySummary> getInventorySummary() async {
    final rows = await _db.rawQuery('''
      SELECT 
        COUNT(*) as product_count,
        COALESCE(SUM(stock_quantity), 0) as total_quantity,
        COALESCE(SUM(CAST(stock_quantity AS REAL) * CAST(price_cents AS REAL)), 0) as total_value_cents,
        COALESCE(SUM(CASE WHEN stock_quantity <= critical_threshold THEN 1 ELSE 0 END), 0) as critical_count
      FROM products
      WHERE is_deleted = 0 AND is_active = 1
    ''');

    if (rows.isEmpty) {
      return const ProductInventorySummary(
        productCount: 0,
        totalQuantity: 0,
        stockValue: 0.0,
        criticalCount: 0,
      );
    }

    final first = rows.first;
    final pCount = (first['product_count'] as num?)?.toInt() ?? 0;
    final totalQty = (first['total_quantity'] as num?) ?? 0;
    final totalValCents = (first['total_value_cents'] as num?)?.toDouble() ?? 0.0;
    final critCount = (first['critical_count'] as num?)?.toInt() ?? 0;

    return ProductInventorySummary(
      productCount: pCount,
      totalQuantity: totalQty,
      stockValue: totalValCents / 100.0,
      criticalCount: critCount,
    );
  }
}
