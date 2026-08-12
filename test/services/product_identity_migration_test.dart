import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/schema/db_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v51 merges stripped EAN-8 aliases without losing stock or images',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''CREATE TABLE products (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, price REAL NOT NULL,
      purchase_price REAL NOT NULL DEFAULT 0, quantity INTEGER NOT NULL,
      min_stock INTEGER NOT NULL DEFAULT 5, brand TEXT NOT NULL DEFAULT '',
      unit TEXT NOT NULL DEFAULT 'adet', shelf_code TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL, sku TEXT UNIQUE, vat INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, image_url TEXT, is_deleted INTEGER NOT NULL DEFAULT 0,
      deleted_at TEXT, deleted_by TEXT, is_synced INTEGER NOT NULL DEFAULT 1,
      sale_type TEXT NOT NULL DEFAULT 'piece',
      minimum_weight_grams INTEGER NOT NULL DEFAULT 20
    )''');
    for (final table in ['sale_items', 'order_items', 'refund_items']) {
      await db.execute(
          'CREATE TABLE $table (id TEXT PRIMARY KEY, product_id TEXT NOT NULL)');
    }
    await db.execute('''CREATE TABLE sync_outbox_v4 (
      id INTEGER PRIMARY KEY AUTOINCREMENT, mutation_id TEXT NOT NULL UNIQUE,
      entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, operation TEXT NOT NULL,
      payload TEXT NOT NULL, base_revision INTEGER NOT NULL DEFAULT 0,
      state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE sync_cursor_v4 (
      key TEXT PRIMARY KEY, cursor INTEGER NOT NULL DEFAULT 0
    )''');
    await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 42});

    Map<String, Object?> product(String id,
            {required int quantity,
            required String updatedAt,
            String? image}) =>
        {
          'id': id,
          'name': '7 Days Çilekli Kruvasan 60 G',
          'description': '7 Days',
          'price': 29.90,
          'purchase_price': 10.0,
          'quantity': quantity,
          'min_stock': 5,
          'brand': '7 Days',
          'unit': 'adet',
          'shelf_code': '',
          'category': 'Atıştırmalık',
          'sku': id,
          'vat': 10,
          'is_active': 1,
          'created_at': '2026-08-11T10:00:00.000Z',
          'updated_at': updatedAt,
          'image_url': image,
          'is_deleted': 0,
          'is_synced': 1,
          'sale_type': 'piece',
          'minimum_weight_grams': 20,
        };

    await db.insert(
        'products',
        product('07031652',
            quantity: 0,
            updatedAt: '2026-08-11T12:00:00.000Z',
            image: r'C:\images\07031652.jpg'));
    await db.insert(
        'products',
        product('7031652',
            quantity: 200, updatedAt: '2026-08-12T12:00:00.000Z'));
    await db.insert('products',
        product('7654321', quantity: 3, updatedAt: '2026-08-12T12:00:00.000Z'));
    for (final table in ['sale_items', 'order_items', 'refund_items']) {
      await db.insert(table, {'id': '$table-1', 'product_id': '7031652'});
    }

    await DatabaseMigrations.onUpgrade(db, 50, 51);

    final canonical =
        (await db.query('products', where: 'id = ?', whereArgs: ['07031652']))
            .single;
    final alias =
        (await db.query('products', where: 'id = ?', whereArgs: ['7031652']))
            .single;
    expect(canonical['quantity'], 200);
    expect(canonical['image_url'], r'C:\images\07031652.jpg');
    expect(canonical['is_active'], 1);
    expect(alias['is_active'], 0);
    expect(alias['is_deleted'], 1);
    expect(await db.query('products', where: 'id = ?', whereArgs: ['7654321']),
        hasLength(1),
        reason: 'Eşleşmeyen mağaza içi yedi haneli kod korunmalı');
    for (final table in ['sale_items', 'order_items', 'refund_items']) {
      expect((await db.query(table)).single['product_id'], '07031652');
    }
    expect(await db.query('sync_outbox_v4'), isEmpty,
        reason:
            'Merkezi v89 temizliği varken binlerce gereksiz olay üretilmemeli');
  });
}
