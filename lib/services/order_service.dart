import '../models/order.dart';
import 'database_service.dart';

class OrderService {
  Future<List<Order>> getAll({String? status}) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'orders',
      where: status != null ? 'status = ?' : null,
      whereArgs: status != null ? [status] : null,
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => Order.fromMap(map)).toList();
  }

  Future<Order?> getById(int id) async {
    final db = await DatabaseService.database;
    final maps = await db.query('orders', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Order.fromMap(maps.first);
  }

  Future<List<OrderItem>> getOrderItems(int orderId) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    return maps.map((map) => OrderItem.fromMap(map)).toList();
  }

  Future<int> create(Order order, List<OrderItem> items) async {
    final db = await DatabaseService.database;

    // Transaction için
    return await db.transaction((txn) async {
      // 1. Sipariş ekle
      final orderId = await txn.insert('orders', order.toMap());

      // 2. Sipariş ürünlerini ekle
      for (var item in items) {
        final itemWithOrderId = OrderItem(
          orderId: orderId,
          productId: item.productId,
          productName: item.productName,
          quantity: item.quantity,
          price: item.price,
          subtotal: item.subtotal,
        );
        await txn.insert('order_items', itemWithOrderId.toMap());

        // 3. Stok düş
        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [item.quantity, item.productId],
        );
      }

      return orderId;
    });
  }

  Future<void> updateStatus(int orderId, String newStatus) async {
    final db = await DatabaseService.database;
    await db.update(
      'orders',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<void> cancel(int orderId) async {
    final db = await DatabaseService.database;

    await db.transaction((txn) async {
      // 1. Sipariş ürünlerini al
      final items = await txn.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      // 2. Stok iade et
      for (var item in items) {
        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          [item['quantity'], item['product_id']],
        );
      }

      // 3. Sipariş durumunu güncelle
      await txn.update(
        'orders',
        {'status': 'cancelled'},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  Future<Map<String, dynamic>> getDailySummary(String date) async {
    final db = await DatabaseService.database;

    // Günlük toplam
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as order_count,
        SUM(total) as total_amount
      FROM orders
      WHERE DATE(created_at) = DATE(?)
      AND status != 'cancelled'
    ''', [date]);

    return {
      'order_count': result.first['order_count'] ?? 0,
      'total_amount': result.first['total_amount'] ?? 0.0,
    };
  }
}
