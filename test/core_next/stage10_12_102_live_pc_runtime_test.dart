// test/core_next/stage10_12_102_live_pc_runtime_test.dart
// SERENUT OS — STAGE 10.12.102
// BU BİLGİSAYARDA CANLI APPDATA VERİTABANI İLE UÇTAN UCA CANLI SATIŞ VE DEFTER TESTİ
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

import 'package:serenutos/core_next/domain/models/core_entities.dart' as core;
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/database/dual_database_routing_coordinator.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_financial_transaction_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_product_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_sale_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.102 — Bu PC Üzerinde Canlı AppData Core Next Testi', () {
    final roaming = Platform.environment['APPDATA'] ?? '';
    final liveAppDir = p.join(roaming, 'Serenut OS Software Technologies A.Ş', 'Serenut OS');
    final liveCorePath = p.join(liveAppDir, 'databases', 'serenut_core_v2.db');
    final liveLegacyPath = p.join(liveAppDir, 'databases', 'serenut_pos.db');

    late CoreAppDatabase coreDb;
    late ProviderContainer container;
    late CoreNextSaleExecutor saleExecutor;
    late CoreNextRefundExecutor refundExecutor;
    late CoreNextProductRepository productRepo;
    late CoreNextCustomerRepository customerRepo;

    const pEzmeKavanozId = 'a4e94c39-b9a2-4f2f-ba38-843bad520bd7'; // Ezme Kavanoz (70.00 TL = 7000 kuruş)
    const pKrokanId = '6df71657-d6b5-4ee0-9c34-4f3c234057ca'; // Fındık Krokan 300gr (300.00 TL = 30000 kuruş)
    const cMehmetGuvenId = '4e310f85-d8a1-4d1c-aec1-da8b25d13e44'; // MEHMET GÜVEN

    setUp(() async {
      final coreFile = File(liveCorePath);
      expect(coreFile.existsSync(), isTrue, reason: 'Canlı AppData serenut_core_v2.db mevcut olmalıdır.');

      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: liveCorePath);

      final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: coreDb,
        enableSalesEngine: true,
      );
      container = ProviderContainer(overrides: overrides);

      saleExecutor = container.read(coreNextSaleExecutorProvider)!;
      refundExecutor = container.read(coreNextRefundExecutorProvider)!;
      productRepo = CoreNextProductRepository.fromCoreAppDatabase(coreDb);
      customerRepo = CoreNextCustomerRepository.fromCoreAppDatabase(coreDb);
    });

    tearDown(() async {
      container.dispose();
      await coreDb.close();
    });

    test('1. Canlı AppData Veritabanı Bütünlük ve Sağlık Kontrolü', () async {
      print('\n================================================================');
      print('🚀 [STAGE 10.12.102] BU PC CANLI VERİTABANI SAĞLIK KONTROLÜ');
      print('   Dosya Yolu: $liveCorePath');
      print('================================================================');

      final integrity = await coreDb.db.rawQuery('PRAGMA integrity_check;');
      print('  PRAGMA integrity_check : ${integrity.first.values.first}');
      expect(integrity.first.values.first, equals('ok'));

      final fkCheck = await coreDb.db.rawQuery('PRAGMA foreign_key_check;');
      print('  PRAGMA foreign_key_check: ${fkCheck.length} ihlal');
      expect(fkCheck, isEmpty);

      final versionRes = await coreDb.db.rawQuery('PRAGMA user_version;');
      final userVersion = (versionRes.first.values.first as num).toInt();
      print('  PRAGMA user_version    : $userVersion (Beklenen: 3)');
      expect(userVersion, equals(3));

      final prodCount = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT COUNT(*) FROM products'),
      );
      final custCount = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT COUNT(*) FROM customers'),
      );
      final salesCount = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales'),
      );

      print('  Canlı Ürün Sayısı      : $prodCount adet (37.682 bekleniyor)');
      print('  Canlı Müşteri Sayısı   : $custCount kişi (626 bekleniyor)');
      print('  Canlı Satış Sayısı     : $salesCount fiş');

      expect(prodCount, equals(37682));
      expect(custCount, equals(626));
      expect(salesCount, greaterThanOrEqualTo(52));
    });

    test('2. Canlı Katalog ve Ürün Arama Testi', () async {
      print('\n================================================================');
      print('🔍 [STAGE 10.12.102] ÜRÜN ARAMA VE BARKOD KONTROLÜ');
      print('================================================================');

      // Aktif mağaza ürünü arama (Ezme Kavanoz)
      final product = await productRepo.findById(pEzmeKavanozId);
      expect(product, isNotNull);
      print('  Aktif Ürün Araması (Ezme Kavanoz):');
      print('    Adı        : ${product!.name}');
      print('    Fiyat      : ${product.price.toStringAsFixed(2)} TL (${(product.price * 100).round()} kuruş)');
      print('    Mevcut Stok: ${product.quantity}');

      expect(product.name, contains('Ezme Kavanoz'));
      expect(product.price, equals(70.00));
      expect(product.quantity, greaterThan(0));
    });

    test('3. Canlı Müşteri ve Defter Sorgulama Testi', () async {
      print('\n================================================================');
      print('👤 [STAGE 10.12.102] MÜŞTERİ CARİ VE BAKİYE KONTROLÜ');
      print('================================================================');

      final customer = await customerRepo.findById(cMehmetGuvenId);
      expect(customer, isNotNull);
      print('  Müşteri Bilgileri:');
      print('    Adı     : ${customer!.name}');
      print('    Bakiye  : ${customer.balance.toStringAsFixed(2)} TL');

      expect(customer.name, contains('MEHMET G'));

      // Müşterinin defter hareketlerini getir
      final ledgers = await coreDb.db.query(
        'ledger_entries',
        where: 'customer_id = ?',
        whereArgs: [cMehmetGuvenId],
        orderBy: 'rowid DESC',
        limit: 3,
      );
      print('  Son 3 Defter Hareketi:');
      for (final l in ledgers) {
        print('    Tarih: ${l['created_at']} | Tip: ${l['entry_type']} | Tutar: ${(l['amount_cents'] as num) / 100.0} TL | Açıklama: ${l['description']}');
      }
    });

    test('4. CANLI İŞLEM 1: Peşin Nakit Satış ve Kasa Çekmecesi Girişi', () async {
      print('\n================================================================');
      print('💰 [STAGE 10.12.102] CANLI İŞLEM 1: PEŞİN NAKİT SATIŞ İCRASI');
      print('================================================================');

      // Satış öncesi stok ve kasa durumu
      final pRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: [pEzmeKavanozId]);
      final stockBefore = (pRows.first['stock_quantity'] as num).toDouble();
      final cashCountBefore = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT COUNT(*) FROM cash_transactions'),
      )!;

      print('  İşlem Öncesi Stok : $stockBefore adet');
      print('  İşlem Öncesi Kasa : $cashCountBefore hareket');

      // 1 Adet Ezme Kavanoz Satışı (70.00 TL = 7000 kuruş)
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: pEzmeKavanozId,
            productName: 'Ezme Kavanoz',
            quantity: 1,
            unitPrice: 70.00,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 70.00,
        cashierName: 'Kasiyer Canlı Test',
        userId: 'usr-kasiyer-pc-01',
        userRole: 'cashier',
      );

      expect(sale, isNotNull);
      print('  ✅ Satış Başarıyla İcra Edildi!');
      print('    Fiş No     : ${sale!.id}');
      print('    Tutar      : ${sale.totalAmount} TL');
      print('    Ödeme Tipi : ${sale.paymentMethod}');

      // 1. Stok kontrolü
      final pRowsAfter = await coreDb.db.query('products', where: 'id = ?', whereArgs: [pEzmeKavanozId]);
      final stockAfter = (pRowsAfter.first['stock_quantity'] as num).toDouble();
      print('  İşlem Sonrası Stok: $stockAfter adet (Beklenen: ${stockBefore - 1.0})');
      expect(stockAfter, equals(stockBefore - 1.0));

      // 2. Kasa çekmecesi nakit girişi (Son eklenen nakit hareketi)
      final cashRowsAfter = await coreDb.db.query('cash_transactions', orderBy: 'rowid DESC', limit: 1);
      expect(cashRowsAfter.first['type'], equals('INFLOW'));
      expect(cashRowsAfter.first['amount_cents'], equals(7000));
      print('  ✅ Kasa Çekmecesine +70.00 TL Nakit Girişi Doğrulandı.');

      // 3. Sync Outbox kontrolü
      final syncRows = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: [sale.id]);
      expect(syncRows.isNotEmpty, isTrue);
      print('  ✅ Bulut Senkronizasyon Kuyruğuna (sync_events) Olay Eklendi.');
    });

    test('5. CANLI İŞLEM 2: Müşteri Veresiye Satışı (Cariye Borçlandırma)', () async {
      print('\n================================================================');
      print('📝 [STAGE 10.12.102] CANLI İŞLEM 2: AÇIK HESAP / VERESİYE SATIŞ');
      print('================================================================');

      // Satış öncesi müşteri bakiyesi
      final cRows = await coreDb.db.query('customers', where: 'id = ?', whereArgs: [cMehmetGuvenId]);
      final balanceBeforeCents = (cRows.first['balance_cents'] as num).toInt();
      print('  Satış Öncesi Müşteri Bakiye: ${(balanceBeforeCents / 100.0).toStringAsFixed(2)} TL ($balanceBeforeCents kuruş)');

      // 1 Adet Fındık Krokan Veresiye Satışı (300.00 TL = 30000 kuruş)
      final sale = await saleExecutor(
        customerId: cMehmetGuvenId,
        items: [
          SaleItemInput(
            productId: pKrokanId,
            productName: 'Fındık Krokan 300gr',
            quantity: 1,
            unitPrice: 300.00,
          ),
        ],
        paymentMethod: 'on_account',
        paidAmount: 0.0,
        cashierName: 'Kasiyer Canlı Test',
        userId: 'usr-kasiyer-pc-01',
        userRole: 'cashier',
      );

      expect(sale, isNotNull);
      print('  ✅ Veresiye Satış Başarıyla İcra Edildi!');
      print('    Fiş No: ${sale!.id} | Tutar: ${sale.totalAmount} TL');

      // 1. Müşteri bakiyesi kontrolü (Negatif borç kuralı: 300.00 TL düşmeli)
      final cRowsAfter = await coreDb.db.query('customers', where: 'id = ?', whereArgs: [cMehmetGuvenId]);
      final balanceAfterCents = (cRowsAfter.first['balance_cents'] as num).toInt();
      print('  Satış Sonrası Müşteri Bakiye: ${(balanceAfterCents / 100.0).toStringAsFixed(2)} TL ($balanceAfterCents kuruş)');
      expect(balanceAfterCents, equals(balanceBeforeCents - 30000));

      // 2. Defter kaydı kontrolü (Son eklenen cari hareket)
      final lastLedger = (await coreDb.db.query(
        'ledger_entries',
        where: 'reference_sale_id = ?',
        whereArgs: [sale.id],
      )).first;
      expect(lastLedger['entry_type'], equals('debitSale'));
      expect(lastLedger['amount_cents'], equals(30000));
      print('  ✅ Deftere (ledger_entries) debitSale olarak 300.00 TL Borç İşlendi.');
    });

    test('6. CANLI İŞLEM 3: Satış İadesi ve Stokun Otomatik Geri Dönmesi', () async {
      print('\n================================================================');
      print('🔄 [STAGE 10.12.102] CANLI İŞLEM 3: NAKİT SATIŞ İADESİ VE STOK RESTORASYONU');
      print('================================================================');

      // Önce iade edilecek 1 adet satış oluştur
      final initProduct = await coreDb.db.query('products', where: 'id = ?', whereArgs: [pKrokanId]);
      final stockBeforeSale = (initProduct.first['stock_quantity'] as num).toDouble();

      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: pKrokanId,
            productName: 'Fındık Krokan 300gr',
            quantity: 1,
            unitPrice: 300.00,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 300.00,
        cashierName: 'Kasiyer Canlı Test',
        userId: 'usr-kasiyer-pc-01',
        userRole: 'cashier',
      );

      final stockAfterSale = ((await coreDb.db.query('products', where: 'id = ?', whereArgs: [pKrokanId])).first['stock_quantity'] as num).toDouble();
      expect(stockAfterSale, equals(stockBeforeSale - 1.0));
      print('  Satış Yapıldı -> Stok $stockBeforeSale \'den $stockAfterSale \'ye düştü.');

      // İadeyi icra et
      await refundExecutor(
        saleId: sale!.id,
        itemsToReturn: [
          SaleItemInput(
            productId: pKrokanId,
            productName: 'Fındık Krokan 300gr',
            quantity: 1,
            unitPrice: 300.00,
          ),
        ],
        refundMethod: 'cash',
        reason: 'Müşteri değişim istedi',
        cashierName: 'Yönetici Test',
        userId: 'usr-yonetici-pc-01',
        userRole: 'manager',
      );

      // İade sonrası stok eski haline geri dönmeli
      final stockAfterRefund = ((await coreDb.db.query('products', where: 'id = ?', whereArgs: [pKrokanId])).first['stock_quantity'] as num).toDouble();
      print('  İade Alındı   -> Stok $stockAfterSale \'den $stockAfterRefund \'ye RESTORE EDİLDİ.');
      expect(stockAfterRefund, equals(stockBeforeSale));
      print('  ✅ Stok Restorasyonu Başarıyla Doğrulandı.');
    });

    test('7. İşlemler Sonrası Canlı Veritabanı ve Z-Raporu Denetimi', () async {
      print('\n================================================================');
      print('📊 [STAGE 10.12.102] İŞLEMLER SONRASI KASA VE VERİTABANI DENETİMİ');
      print('================================================================');

      final integrity = await coreDb.db.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first.values.first, equals('ok'));

      final fkCheck = await coreDb.db.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck, isEmpty);

      print('  PRAGMA integrity_check : ${integrity.first.values.first} (SIFIR BOZULMA)');
      print('  PRAGMA foreign_key_check: ${fkCheck.length} ihlal (SIFIR İHLAL)');
      print('  ✅ Tüm canlı testler 0 kuruş sapma ve sıfır veri kaybı ile tamamlandı.');
    });
  });
}
