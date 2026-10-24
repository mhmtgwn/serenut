// core_next/client_core/lib/infrastructure/repositories/core_next_sale_repository.dart
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import '../database/app_database.dart';

/// Core Next Veritabanı (`serenut_core_v2.db`) üzerinde çalışan ISaleRepository uyarlayıcısı.
/// Bu sınıf, Authoritative Store Cutover mimarisinde UI okuma katmanlarının
/// doğrudan yeni veritabanından beslenmesini sağlar (Dual-DB Split çözümü).
class CoreNextSaleRepository implements ISaleRepository {
  final DatabaseExecutor _db;

  CoreNextSaleRepository(this._db);

  factory CoreNextSaleRepository.fromCoreAppDatabase(CoreAppDatabase coreDb) {
    return CoreNextSaleRepository(coreDb.db);
  }

  Future<List<SaleEntity>> _enrichSales(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];

    final saleIds = rows.map((r) => r['id'].toString()).toList();
    final itemRows = <Map<String, dynamic>>[];
    final paymentRows = <Map<String, dynamic>>[];

    const chunkSize = 400;
    for (var i = 0; i < saleIds.length; i += chunkSize) {
      final chunk = saleIds.sublist(
        i,
        i + chunkSize > saleIds.length ? saleIds.length : i + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');

      final items = await _db.rawQuery(
        'SELECT * FROM sale_items WHERE sale_id IN ($placeholders)',
        chunk,
      );
      itemRows.addAll(items);

      final pays = await _db.rawQuery(
        'SELECT * FROM sale_payments WHERE sale_id IN ($placeholders)',
        chunk,
      );
      paymentRows.addAll(pays);
    }

    final itemsBySale = <String, List<Map<String, dynamic>>>{};
    for (final item in itemRows) {
      final sid = item['sale_id'].toString();
      final unitPrice = ((item['unit_price_cents'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final total = ((item['total_cents'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final mappedItem = {
        'id': item['id'],
        'sale_id': sid,
        'product_id': item['product_id'],
        'barcode': item['barcode'],
        'product_name': item['product_name'],
        'unit_price': unitPrice,
        'quantity': (item['quantity'] as num?)?.toDouble() ?? 1.0,
        'subtotal': total,
        'discount_amount': ((item['discount_cents'] as num?)?.toDouble() ?? 0.0) / 100.0,
        'vat_rate': item['vat_rate'] ?? 20,
      };
      itemsBySale.putIfAbsent(sid, () => []).add(mappedItem);
    }

    final paymentsBySale = <String, List<Map<String, dynamic>>>{};
    for (final p in paymentRows) {
      final sid = p['sale_id'].toString();
      paymentsBySale.putIfAbsent(sid, () => []).add(p);
    }

    final sales = <SaleEntity>[];
    for (final row in rows) {
      final sid = row['id'].toString();
      final totalCents = (row['total_cents'] as num?)?.toInt() ?? 0;
      final paidCents = (row['paid_cents'] as num?)?.toInt() ?? 0;
      final discountCents = (row['discount_cents'] as num?)?.toInt() ?? 0;
      final createdAtMs = (row['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

      final salePayments = paymentsBySale[sid] ?? [];
      String method = 'cash';
      if (salePayments.length > 1) {
        method = 'mixed';
      } else if (salePayments.isNotEmpty) {
        method = salePayments.first['payment_type']?.toString() ?? 'cash';
      }

      final entity = SaleEntity(
        id: sid,
        customerId: row['customer_id']?.toString() ?? '',
        totalAmount: totalCents / 100.0,
        paidAmount: paidCents / 100.0,
        discountAmount: discountCents / 100.0,
        paymentMethod: method,
        status: (row['status'] ?? 'completed').toString().toLowerCase(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
        items: itemsBySale[sid] ?? [],
        idempotencyKey: row['idempotency_key']?.toString(),
        isSynced: 0,
      );
      sales.add(entity);
    }

    return sales;
  }

  @override
  Future<List<SaleEntity>> findAll() async {
    final rows = await _db.query('sales', orderBy: 'created_at DESC');
    return _enrichSales(rows);
  }

  @override
  Future<SaleEntity?> findById(String id) async {
    final rows = await _db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final sales = await _enrichSales(rows);
    return sales.firstOrNull;
  }

  @override
  Future<SaleEntity?> findByIdempotencyKey(String key) async {
    final rows = await _db.query('sales', where: 'idempotency_key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final sales = await _enrichSales(rows);
    return sales.firstOrNull;
  }

  @override
  Future<List<SaleEntity>> findFiltered({
    String? searchQuery,
    String? paymentMethod,
    String? status,
    int limit = 25,
    int offset = 0,
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClauses.add('(id LIKE ? OR receipt_no LIKE ?)');
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }
    if (status != null && status.isNotEmpty) {
      whereClauses.add('LOWER(status) = ?');
      whereArgs.add(status.toLowerCase());
    }

    final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    final rows = await _db.query(
      'sales',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return _enrichSales(rows);
  }

  @override
  Future<List<SaleEntity>> getTodaySales() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;
    final rows = await _db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [startOfDay, endOfDay],
      orderBy: 'created_at DESC',
    );
    return _enrichSales(rows);
  }

  @override
  Future<List<SaleEntity>> getSalesByDateRange(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'created_at DESC',
    );
    return _enrichSales(rows);
  }

  @override
  Future<List<SaleEntity>> getByCustomerId(String customerId) async {
    final rows = await _db.query(
      'sales',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return _enrichSales(rows);
  }

  @override
  Future<List<SaleEntity>> getByPaymentMethod(String method) async {
    final all = await findAll();
    return all.where((s) => s.paymentMethod.toLowerCase() == method.toLowerCase()).toList();
  }

  @override
  Future<double> getTodayRevenue() async {
    final today = await getTodaySales();
    return today.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
  }

  @override
  Future<double> getRevenueByDateRange(DateTime from, DateTime to) async {
    final range = await getSalesByDateRange(from, to);
    return range.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
  }

  @override
  Future<int> getTotalItemsSold() async {
    final res = await _db.rawQuery('SELECT COALESCE(SUM(quantity), 0) as total FROM sale_items');
    return (res.first['total'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<SaleEntity>> findUnsynced() async {
    return [];
  }

  @override
  Future<int> count() async {
    final res = await _db.rawQuery('SELECT COUNT(*) as count FROM sales');
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<bool> exists(String id) async {
    final res = await _db.query('sales', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    return res.isNotEmpty;
  }

  @override
  Future<int> create(SaleEntity entity) async {
    throw UnsupportedError('Yazma işlemleri CoreCheckoutUseCase üzerinden yapılmalıdır.');
  }

  @override
  Future<int> update(SaleEntity entity) async {
    throw UnsupportedError('Satış güncellemesi CoreNext Sale Engine üzerinden yönetilmelidir.');
  }

  @override
  Future<int> delete(String id) async {
    return _db.delete('sales', where: 'id = ?', whereArgs: [id]);
  }
}
