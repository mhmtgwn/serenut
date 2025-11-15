import '../models/product.dart';
import 'database_service.dart';

class ProductService {
  Future<List<Product>> getAll() async {
    final db = await DatabaseService.database;
    final maps = await db.query('products', orderBy: 'name ASC');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<Product?> getById(int id) async {
    final db = await DatabaseService.database;
    final maps = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  Future<int> add(Product product) async {
    final db = await DatabaseService.database;
    return await db.insert('products', product.toMap());
  }

  Future<void> update(Product product) async {
    final db = await DatabaseService.database;
    await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await DatabaseService.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStock(int productId, int quantity) async {
    final db = await DatabaseService.database;
    await db.rawUpdate(
      'UPDATE products SET stock = stock + ? WHERE id = ?',
      [quantity, productId],
    );
  }

  Future<List<Product>> getLowStock({int threshold = 10}) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'products',
      where: 'stock <= ?',
      whereArgs: [threshold],
      orderBy: 'stock ASC',
    );
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<List<Product>> getByCategory(String category) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'products',
      where: 'category = ?',
      whereArgs: [category],
    );
    return maps.map((map) => Product.fromMap(map)).toList();
  }
}
