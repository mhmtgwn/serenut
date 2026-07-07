import 'dart:async';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';

class SqliteProductRepository implements IProductRepository {
  final DbGateway _gateway;
  final DatasetLoaderService? _datasetLoader;

  SqliteProductRepository(this._gateway, [this._datasetLoader]);

  DbExecutor get _executor => _gateway;

  bool get _hasDataset => _datasetLoader != null && _datasetLoader!.activeDb != null;
  String get _market => _datasetLoader?.selectedMarket ?? 'Migros';

  Future<List<ProductEntity>> _queryProducts({String? where, List<Object?>? whereArgs, String? orderBy}) async {
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
        sql += ' ORDER BY $rewrittenOrder';
      }
      
      final rows = await _datasetLoader!.activeDb!.rawQuery(sql, args);
      return rows.map((row) => ProductEntity(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String,
        price: (row['price'] as num).toDouble(),
        quantity: row['quantity'] as int,
        category: row['category'] as String,
        vat: row['vat'] as int?,
      )).toList();
    } else {
      final rows = await _executor.query('products', where: where, whereArgs: whereArgs, orderBy: orderBy);
      return rows.map((row) => ProductEntity.fromMap(row)).toList();
    }
  }

  @override
  Future<List<ProductEntity>> findAll() async {
    return await _queryProducts(where: 'is_active = 1');
  }

  @override
  Future<ProductEntity?> findById(dynamic id) async {
    final list = await _queryProducts(where: 'id = ? AND is_active = 1', whereArgs: [id]);
    if (list.isEmpty) return null;
    return list.first;
  }

  @override
  Future<int> create(ProductEntity product) async {
    return await _executor.insert(
      'products',
      {
        ...product.toMap(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  Future<int> update(ProductEntity product, {String? oldId}) async {
    final targetId = oldId ?? product.id;
    if (oldId != null && oldId != product.id) {
      final alreadyExists = await exists(product.id);
      if (alreadyExists) {
        throw Exception('Bu barkod kodu (${product.id}) zaten başka bir üründe kullanılıyor.');
      }
      await _gateway.transaction(() async {
        await _executor.update(
          'products',
          {
            ...product.toMap(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [oldId],
        );
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
      });
      return 1;
    }

    return await _executor.update(
      'products',
      {
        ...product.toMap(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [targetId],
    );
  }

  @override
  Future<int> delete(dynamic id) async {
    // Soft delete
    return await _executor.update(
      'products',
      {
        'is_active': 0,
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<int> count() async {
    if (_hasDataset) {
      final result = await _datasetLoader!.activeDb!.rawQuery('SELECT COUNT(*) as count FROM products');
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
      final result = await _datasetLoader!.activeDb!.rawQuery('SELECT 1 FROM products WHERE barcode = ? LIMIT 1', [id]);
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
    return await _queryProducts(where: 'name LIKE ? AND is_active = 1', whereArgs: ['%$query%']);
  }

  @override
  Future<List<ProductEntity>> getByCategory(String category) async {
    return await _queryProducts(where: 'category = ? AND is_active = 1', whereArgs: [category]);
  }

  @override
  Future<Map<String, List<ProductEntity>>> getGroupedByCategory() async {
    final entities = await _queryProducts(where: 'is_active = 1', orderBy: 'category');
    
    final grouped = <String, List<ProductEntity>>{};
    for (final entity in entities) {
      grouped.putIfAbsent(entity.category, () => []).add(entity);
    }
    return grouped;
  }

  @override
  Future<void> decreaseStock(String productId, int quantity) async {
    await _executor.rawUpdate(
      'UPDATE products SET quantity = quantity - ?, updated_at = ? WHERE id = ?',
      [quantity, DateTime.now().toIso8601String(), productId],
    );
  }

  @override
  Future<void> increaseStock(String productId, int quantity) async {
    await _executor.rawUpdate(
      'UPDATE products SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
      [quantity, DateTime.now().toIso8601String(), productId],
    );
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

    final String whereString = whereClauses.join(' AND ');

    final rows = await _executor.query(
      'products',
      where: whereString,
      whereArgs: whereArgs,
      limit: limit,
      offset: offset,
      orderBy: 'name ASC',
    );
    return rows.map((row) => ProductEntity.fromMap(row)).toList();
  }

  @override
  Future<List<String>> getCategories() async {
    final rows = await _executor.rawQuery(
      'SELECT DISTINCT category FROM products WHERE is_active = 1 ORDER BY category ASC',
    );
    return rows.map((row) => (row['category'] as String?) ?? '').where((c) => c.isNotEmpty).toList();
  }
}
