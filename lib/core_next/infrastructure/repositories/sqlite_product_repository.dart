// core_next/client_core/lib/infrastructure/repositories/sqlite_product_repository.dart
import 'package:sqflite/sqflite.dart';
import '../../domain/models/core_entities.dart';

abstract interface class ICoreProductRepository {
  Future<ProductEntity?> getById(String id);
  Future<ProductEntity?> getByBarcode(String barcode);
  Future<List<ProductEntity>> searchProducts(String query, {int limit = 50});
  Future<List<ProductEntity>> getByCategory(String categoryId);
  Future<void> upsertProduct(ProductEntity product);
  Future<void> updateStock(String productId, num newQuantity);
  Future<void> softDeleteProduct(String productId);
}

class SqliteProductRepository implements ICoreProductRepository {
  final DatabaseExecutor _db;

  const SqliteProductRepository(this._db);

  @override
  Future<ProductEntity?> getById(String id) async {
    final rows = await _db.query(
      'products',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ProductEntity.fromMap(rows.first);
  }

  @override
  Future<ProductEntity?> getByBarcode(String barcode) async {
    final rows = await _db.query(
      'products',
      where: 'barcode = ? AND is_deleted = 0',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ProductEntity.fromMap(rows.first);
  }

  @override
  Future<List<ProductEntity>> searchProducts(String query,
      {int limit = 50}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      final rows = await _db.query(
        'products',
        where: 'is_deleted = 0 AND is_active = 1',
        orderBy: 'name ASC',
        limit: limit,
      );
      return rows.map(ProductEntity.fromMap).toList();
    }

    final rows = await _db.query(
      'products',
      where: 'is_deleted = 0 AND is_active = 1 AND (barcode LIKE ? OR name LIKE ?)',
      whereArgs: ['%$cleanQuery%', '%$cleanQuery%'],
      orderBy: 'name ASC',
      limit: limit,
    );
    return rows.map(ProductEntity.fromMap).toList();
  }

  @override
  Future<List<ProductEntity>> getByCategory(String categoryId) async {
    final rows = await _db.query(
      'products',
      where: 'category_id = ? AND is_deleted = 0 AND is_active = 1',
      whereArgs: [categoryId],
      orderBy: 'name ASC',
    );
    return rows.map(ProductEntity.fromMap).toList();
  }

  @override
  Future<void> upsertProduct(ProductEntity product) async {
    await _db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateStock(String productId, num newQuantity) async {
    await _db.update(
      'products',
      {
        'stock_quantity': newQuantity.toDouble(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  @override
  Future<void> softDeleteProduct(String productId) async {
    await _db.update(
      'products',
      {
        'is_deleted': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }
}
