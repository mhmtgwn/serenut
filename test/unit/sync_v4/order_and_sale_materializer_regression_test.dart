import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.12.6 — Sync Materializer Regression Tests (Order vs Sale)', () {
    late Database db;
    late SyncV4Service syncService;

    setUp(() async {
      // Standart legacy SQLite v60 şeması ile in-memory DB oluştur
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await DatabaseSchema.createTables(db);
          },
        ),
      );

      syncService = SyncV4Service(
        ApiClient(),
        deviceIdResolver: () async => 'test-device-id',
        deviceActivationIdResolver: () async => 'test-activation-id',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('1. Sipariş (Order) materyalizasyonu order_items tablosuna başarıyla yazmalı ve unit_price_minor hatası vermemelidir', () async {
      final orderChange = {
        'entity_type': 'order',
        'entity_id': 'ord-test-1001',
        'operation': 'UPSERT',
        'payload': {
          'id': 'ord-test-1001',
          'order_number': 'ORD-2026-001',
          'customer_id': 'cust-1',
          'customer_name': 'Ahmet Yılmaz',
          'status': 'pending',
          'total_amount': 350.0,
          'created_at': '2026-10-16T12:00:00.000Z',
          'items': [
            {
              'id': 'ord-item-1',
              'product_id': 'p-findik-500g',
              'product_name': 'Nutopia Kavrulmuş Fındık 500g',
              'quantity': 2.0,
              'unit_price': 175.0,
            }
          ],
        },
      };

      // Transaction içinde _apply çağrısı
      await db.transaction((txn) async {
        await syncService.applyChangeForTesting(txn, orderChange);
      });

      // Doğrulama: orders tablosu
      final orders = await db.query('orders', where: 'id = ?', whereArgs: ['ord-test-1001']);
      expect(orders.length, equals(1));
      expect(orders.first['order_number'], equals('ORD-2026-001'));
      expect(orders.first['total_amount'], equals(350.0));

      // Doğrulama: order_items tablosu
      final orderItems = await db.query('order_items', where: 'order_id = ?', whereArgs: ['ord-test-1001']);
      expect(orderItems.length, equals(1));
      final item = orderItems.first;
      expect(item['id'], equals('ord-item-1'));
      expect(item['product_id'], equals('p-findik-500g'));
      expect(item['quantity'], equals(2.0));
      expect(item['unit_price'], equals(175.0));
      // order_items şemasında unit_price_minor sütunu yoktur ve yazılmaya çalışılmamıştır
      expect(item.containsKey('unit_price_minor'), isFalse);
    });

    test('2. Satış (Sale) materyalizasyonu sale_items tablosuna unit_price_minor ve subtotal_minor ile birlikte yazmalıdır', () async {
      final saleChange = {
        'entity_type': 'sale',
        'entity_id': 'sale-test-2001',
        'operation': 'UPSERT',
        'payload': {
          'id': 'sale-test-2001',
          'receipt_number': 'REC-2026-001',
          'customer_id': 'cust-1',
          'total_amount': 250.0,
          'status': 'completed',
          'created_at': '2026-10-16T12:30:00.000Z',
          'items': [
            {
              'id': 'sale-item-1',
              'product_id': 'p-ezme-250g',
              'product_name': 'Nutopia Fındık Ezmesi 250g',
              'quantity': 1.0,
              'unit_price': 250.0,
            }
          ],
        },
      };

      await db.transaction((txn) async {
        await syncService.applyChangeForTesting(txn, saleChange);
      });

      // Doğrulama: sales tablosu
      final sales = await db.query('sales', where: 'id = ?', whereArgs: ['sale-test-2001']);
      expect(sales.length, equals(1));

      // Doğrulama: sale_items tablosu
      final saleItems = await db.query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-test-2001']);
      expect(saleItems.length, equals(1));
      final item = saleItems.first;
      expect(item['unit_price'], equals(250.0));
      expect(item['unit_price_minor'], equals(25000));
      expect(item['subtotal'], equals(250.0));
      expect(item['subtotal_minor'], equals(25000));
    });

    test('3. Yeniden deneme (Replay / Idempotency): Aynı sipariş tekrar geldiğinde mükerrerlik olmadan güncellenmelidir', () async {
      final orderChange = {
        'entity_type': 'order',
        'entity_id': 'ord-test-replay-1',
        'operation': 'UPSERT',
        'payload': {
          'id': 'ord-test-replay-1',
          'order_number': 'ORD-REPLAY-001',
          'customer_id': 'cust-1',
          'total_amount': 100.0,
          'status': 'pending',
          'items': [
            {
              'id': 'ord-item-rep-1',
              'product_id': 'p-rep-1',
              'quantity': 1.0,
              'unit_price': 100.0,
            }
          ],
        },
      };

      // 1. İşleme
      await db.transaction((txn) async => syncService.applyChangeForTesting(txn, orderChange));
      // 2. İşleme (Tekrar)
      await db.transaction((txn) async => syncService.applyChangeForTesting(txn, orderChange));

      final orders = await db.query('orders', where: 'id = ?', whereArgs: ['ord-test-replay-1']);
      expect(orders.length, equals(1));

      final items = await db.query('order_items', where: 'order_id = ?', whereArgs: ['ord-test-replay-1']);
      expect(items.length, equals(1)); // Mükerrer satır oluşmamalıdır
    });
  });
}
