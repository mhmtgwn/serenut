// test/core_next/stock_movements_ledger_audit_test.dart
// SERENUT OS — ARCHITECTURAL REPAIR PHASE 2
// Append-Only Stock Movements Ledger Verification Test
// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/database/schema_definitions.dart';
import 'package:serenutos/core_next/infrastructure/database/dual_database_routing_coordinator.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FAZ 2: İstemcide Append-Only Stok Defteri (stock_movements)', () {
    late CoreAppDatabase coreDb;
    late ProviderContainer container;
    late CoreNextSaleExecutor saleExecutor;
    late CoreNextRefundExecutor refundExecutor;

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);

      final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: coreDb,
        enableSalesEngine: true,
      );
      container = ProviderContainer(overrides: overrides);
      saleExecutor = container.read(coreNextSaleExecutorProvider)!;
      refundExecutor = container.read(coreNextRefundExecutorProvider)!;

      // Başlangıç test ürünü ekle: 50 adet stok, 25.00 TL fiyat
      await coreDb.db.insert('products', {
        'id': 'prod-findik-1',
        'barcode': '869000000001',
        'name': 'Giresun Fındığı 500g',
        'price_cents': 2500,
        'cost_price_cents': 1800,
        'vat_rate': 10,
        'unit': 'piece',
        'stock_quantity': 50.0,
        'critical_threshold': 5.0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      container.dispose();
      await coreDb.close();
    });

    test('2.1 Veritabanı Şeması v6 ve stock_movements Tablosu Doğrulanmalıdır', () async {
      expect(CoreSchemaDefinitions.schemaVersion, equals(7));

      final vRes = await coreDb.db.rawQuery('PRAGMA user_version;');
      expect((vRes.first.values.first as num).toInt(), equals(7));

      final tables = (await coreDb.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'].toString())
          .toSet();
      expect(tables.contains('stock_movements'), isTrue);

      final indexes = (await coreDb.db.rawQuery("SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => r['name'].toString())
          .toSet();
      expect(indexes.contains('idx_stock_movements_product'), isTrue);
      expect(indexes.contains('idx_stock_movements_ref'), isTrue);
      expect(indexes.contains('idx_stock_movements_created'), isTrue);
    });

    test('2.2 Satış Yapıldığında stock_movements Tablosuna Atomik Negatif Stok Hareketi Yazılmalıdır', () async {
      // 3 adet satış yap (3 * 25.00 TL = 75.00 TL)
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: 'prod-findik-1',
            productName: 'Giresun Fındığı 500g',
            quantity: 3,
            unitPrice: 25.00,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 75.00,
        cashierName: 'Kasiyer Ahmet',
        userId: 'usr-kasiyer-01',
        userRole: 'cashier',
      );

      expect(sale, isNotNull);

      // 1. Ürün tablosunda stok 50 -> 47'ye inmeli
      final pRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-findik-1']);
      expect((pRows.first['stock_quantity'] as num).toDouble(), equals(47.0));

      // 2. stock_movements tablosunda kayıt doğrulanmalı
      final movements = await coreDb.db.query(
        'stock_movements',
        where: 'product_id = ?',
        whereArgs: ['prod-findik-1'],
      );
      expect(movements.length, equals(1));

      final m = movements.first;
      expect(m['reference_id'], equals(sale!.id));
      expect(m['reference_type'], equals('SALE'));
      expect((m['quantity_delta'] as num).toDouble(), equals(-3.0));
      expect((m['previous_stock'] as num).toDouble(), equals(50.0));
      expect((m['new_stock'] as num).toDouble(), equals(47.0));
      expect(m['created_by'], equals('Kasiyer Ahmet'));
    });

    test('2.3 İade Yapıldığında stock_movements Tablosuna Atomik Pozitif Stok Hareketi Yazılmalıdır', () async {
      // 1. Önce 5 adet sat: Stok 50 -> 45
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: 'prod-findik-1',
            productName: 'Giresun Fındığı 500g',
            quantity: 5,
            unitPrice: 25.00,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 125.00,
        cashierName: 'Kasiyer Ahmet',
        userId: 'usr-kasiyer-01',
        userRole: 'cashier',
      );
      expect(sale, isNotNull);

      // 2. Satılan 5 adedin 2 adedini iade al
      await refundExecutor(
        saleId: sale!.id,
        itemsToReturn: [
          SaleItemInput(
            productId: 'prod-findik-1',
            productName: 'Giresun Fındığı 500g',
            quantity: 2,
            unitPrice: 25.00,
          ),
        ],
        refundMethod: 'cash',
        reason: 'Paket hasarlı',
        cashierName: 'Yönetici Mehmet',
        userId: 'usr-yonetici-01',
        userRole: 'manager',
      );

      // 3. Ürün tablosunda stok 45 -> 47'ye dönmeli
      final pRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-findik-1']);
      expect((pRows.first['stock_quantity'] as num).toDouble(), equals(47.0));

      // 4. stock_movements tablosunda 2 hareket olmalı (1 SALE, 1 REFUND)
      final movements = await coreDb.db.query(
        'stock_movements',
        where: 'product_id = ?',
        whereArgs: ['prod-findik-1'],
        orderBy: 'created_at ASC',
      );
      expect(movements.length, equals(2));

      // Satış hareketi
      expect(movements[0]['reference_type'], equals('SALE'));
      expect((movements[0]['quantity_delta'] as num).toDouble(), equals(-5.0));
      expect((movements[0]['previous_stock'] as num).toDouble(), equals(50.0));
      expect((movements[0]['new_stock'] as num).toDouble(), equals(45.0));

      // İade hareketi
      expect(movements[1]['reference_type'], equals('REFUND'));
      expect((movements[1]['quantity_delta'] as num).toDouble(), equals(2.0));
      expect((movements[1]['previous_stock'] as num).toDouble(), equals(45.0));
      expect((movements[1]['new_stock'] as num).toDouble(), equals(47.0));
      expect(movements[1]['reason'], equals('İade: Paket hasarlı'));
      expect(movements[1]['created_by'], equals('Yönetici Mehmet'));

      // 5. Matematiksel Toplam (CRDT / Ledger Değişmezliği):
      // Başlangıç Stok (50) + SUM(quantity_delta) (-5 + 2 = -3) == Mevcut Stok (47)
      final sumDelta = (await coreDb.db.rawQuery(
        'SELECT SUM(quantity_delta) as s FROM stock_movements WHERE product_id = ?',
        ['prod-findik-1'],
      )).first['s'] as num;
      expect(sumDelta.toDouble(), equals(-3.0));
      expect(50.0 + sumDelta.toDouble(), equals(47.0));
    });
  });
}
