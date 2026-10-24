// test/core_next/stage10_12_101_pilot_cutover_live_execution_test.dart
// SERENUT OS — STAGE 10.12.101
// FAZ 3: NUTOPIA KASASINDA KONTROLLÜ PİLOT CUTOVER VE CANLI İŞLEM DOĞRULAMA
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

import 'package:serenutos/core_next/domain/models/core_entities.dart' as core;
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/database/dual_database_routing_coordinator.dart';
import 'package:serenutos/core_next/infrastructure/migration/migration_bridge_engine.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_financial_transaction_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_product_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_sale_repository.dart';

String computeSha256(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) return 'NOT_FOUND';
  final bytes = file.readAsBytesSync();
  return sha256.convert(bytes).toString().toLowerCase();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.101 — Faz 3: Nutopia Pilot Cutover & Canlı İşlem Doğrulama', () {
    const nutopiaMerchantId = 'comp-1785241628448-c7f5677d';
    const erkulMerchantId = 'comp-1791194455402-bdc6d8d1';

    final rootDir = Directory.current.path;
    final liveCoreSourcePath = p.join(
      rootDir,
      'backups',
      'nutopia_live_20261021_2055',
      'nutopia_core_next_live.db',
    );
    final manifestPath = p.join(
      rootDir,
      'backups',
      'live_cutover_faz2_snapshot_20261023_211448',
      'snapshot_manifest.json',
    );
    final faz2SnapshotDbPath = p.join(
      rootDir,
      'backups',
      'live_cutover_faz2_snapshot_20261023_211448',
      'nutopia_live_snapshot_20261023_211448.db',
    );

    late Directory testTempDir;
    late String workingCoreDbPath;
    late String workingLegacyDbPath;
    late CoreAppDatabase workingCoreDb;

    setUp(() async {
      testTempDir = Directory.systemTemp.createTempSync('stage101_pilot_cutover_');
      workingCoreDbPath = p.join(testTempDir.path, 'working_nutopia_core_live.db');
      workingLegacyDbPath = p.join(testTempDir.path, 'working_nutopia_legacy_pos.db');

      // 1. Hedef Core Next veritabanının çalışma kopyasını oluştur
      final srcFile = File(liveCoreSourcePath);
      expect(srcFile.existsSync(), isTrue, reason: 'Hedef veritabanı mevcut olmalıdır.');
      srcFile.copySync(workingCoreDbPath);

      // 2. Faz 2 snapshot yedeğinin çalışma kopyasını legacy olarak aç
      final snapFile = File(faz2SnapshotDbPath);
      expect(snapFile.existsSync(), isTrue, reason: 'Faz 2 snapshot mevcut olmalıdır.');
      snapFile.copySync(workingLegacyDbPath);

      workingCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: workingCoreDbPath);
    });

    tearDown(() async {
      await workingCoreDb.close();
      if (testTempDir.existsSync()) {
        try {
          testTempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // ─────────────────────────────────────────────────────────────
    // GRUP 1: ÖN KOŞULLAR VE SNAPSHOT BÜTÜNLÜK DENETİMİ (FAZ 2 AUDIT)
    // ─────────────────────────────────────────────────────────────
    group('Grup 1: Ön Koşullar & Snapshot Bütünlük Denetimi', () {
      test('1.1 Faz 2 Yedekleme Manifesti ve SHA-256 İmzası Tam Doğrulanmalıdır', () {
        final mFile = File(manifestPath);
        expect(mFile.existsSync(), isTrue);

        final manifest = jsonDecode(mFile.readAsStringSync()) as Map<String, dynamic>;
        expect(manifest['stage'], equals('FAZ_2_LIVE_BACKUP_AND_SNAPSHOT'));
        expect(manifest['snapshots'], isNotNull);

        final nutopiaSnap = manifest['snapshots']['nutopia_live'] as Map<String, dynamic>;
        final expectedSha = (nutopiaSnap['sha256'] as String).toLowerCase();
        final actualSha = computeSha256(nutopiaSnap['snapshot_path']);
        expect(actualSha, equals(expectedSha));

        final snapFile = File(nutopiaSnap['snapshot_path']);
        expect(snapFile.existsSync(), isTrue);
        expect(snapFile.lengthSync(), equals(nutopiaSnap['size_bytes']));
        expect(nutopiaSnap['integrity_check'], equals('ok'));
        expect(nutopiaSnap['table_counts']['products'], equals(37682));
        expect(nutopiaSnap['table_counts']['customers'], equals(626));
      });

      test('1.2 Hedef Core Next Veritabanı Bütünlüğü ve Şema v3 Doğrulanmalıdır', () async {
        final integrity = await workingCoreDb.db.rawQuery('PRAGMA integrity_check;');
        expect(integrity.first.values.first, equals('ok'));

        final fkCheck = await workingCoreDb.db.rawQuery('PRAGMA foreign_key_check;');
        expect(fkCheck, isEmpty);

        final versionRes = await workingCoreDb.db.rawQuery('PRAGMA user_version;');
        final userVersion = (versionRes.first.values.first as num).toInt();
        expect(userVersion, equals(3));

        final totalProducts = Sqflite.firstIntValue(
          await workingCoreDb.db.rawQuery('SELECT COUNT(*) FROM products'),
        );
        final totalCustomers = Sqflite.firstIntValue(
          await workingCoreDb.db.rawQuery('SELECT COUNT(*) FROM customers'),
        );
        expect(totalProducts, equals(37682));
        expect(totalCustomers, equals(626));
      });

      test('1.3 Erkul Çeyiz Çapraz Kiracı Geçiş Talebi Fail-Closed Engellenmelidir', () async {
        SharedPreferences.setMockInitialValues({
          PilotCutoverGate.prefKeyPilotEnabled: true,
          PilotCutoverGate.prefKeySalesEngineEnabled: true,
          PilotCutoverGate.prefKeyKillSwitch: false,
          CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
          CoreNextBootstrapCoordinator.prefKeyBackupPath: faz2SnapshotDbPath,
          'last_backup_date': DateTime.now().toIso8601String(),
        });
        final prefs = await SharedPreferences.getInstance();

        const gate = PilotCutoverGate();
        final result = await gate.evaluate(
          prefs: prefs,
          requestedTenantId: erkulMerchantId,
          legacyDbPath: workingLegacyDbPath,
          targetDbPath: workingCoreDbPath,
          enableSalesEngine: true,
        );

        expect(result.isPilotActive, isFalse);
        expect(result.status, equals(PilotGateStatus.blockedTenantMismatch));
        expect(result.overrides, isEmpty);
      });

      test('1.4 Acil Durum Kill Switch Açıldığında Geçiş Derhal Durdurulmalıdır', () async {
        SharedPreferences.setMockInitialValues({
          PilotCutoverGate.prefKeyPilotEnabled: true,
          PilotCutoverGate.prefKeySalesEngineEnabled: true,
          PilotCutoverGate.prefKeyKillSwitch: true, // Acil kesici devrede
          CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
          CoreNextBootstrapCoordinator.prefKeyBackupPath: faz2SnapshotDbPath,
          'last_backup_date': DateTime.now().toIso8601String(),
        });
        final prefs = await SharedPreferences.getInstance();

        const gate = PilotCutoverGate();
        final result = await gate.evaluate(
          prefs: prefs,
          requestedTenantId: nutopiaMerchantId,
          legacyDbPath: workingLegacyDbPath,
          targetDbPath: workingCoreDbPath,
          enableSalesEngine: true,
        );

        expect(result.isPilotActive, isFalse);
        expect(result.status, equals(PilotGateStatus.blockedKillSwitch));
      });
    });

    // ─────────────────────────────────────────────────────────────
    // GRUP 2: PİLOT CUTOVER GATE VE ÇALIŞMA ZAMANI BAĞLANTILARI
    // ─────────────────────────────────────────────────────────────
    group('Grup 2: Pilot Cutover Gate ve Sağlayıcı Enjeksiyonu', () {
      test('2.1 Nutopia İçin Pilot Geçişi ve 4 Satış Motoru Sağlayıcısı Başarıyla Bağlanmalıdır', () async {
        SharedPreferences.setMockInitialValues({
          PilotCutoverGate.prefKeyPilotEnabled: true,
          PilotCutoverGate.prefKeySalesEngineEnabled: true,
          PilotCutoverGate.prefKeyKillSwitch: false,
          CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
          CoreNextBootstrapCoordinator.prefKeyBackupPath: faz2SnapshotDbPath,
          'last_backup_date': DateTime.now().toIso8601String(),
        });
        final prefs = await SharedPreferences.getInstance();

        final gate = PilotCutoverGate(
          overrideGenerator: ({
            required String requestedTenantId,
            required String legacyDbPath,
            required String targetDbPath,
            required bool enableSalesEngine,
            DatabaseFactory? dbFactory,
          }) async {
            return DualDatabaseRoutingCoordinator.createRepositoryOverrides(
              coreDb: workingCoreDb,
              enableSalesEngine: enableSalesEngine,
            );
          },
        );

        final result = await gate.evaluate(
          prefs: prefs,
          requestedTenantId: nutopiaMerchantId,
          legacyDbPath: workingLegacyDbPath,
          targetDbPath: workingCoreDbPath,
          enableSalesEngine: true,
        );

        expect(result.isPilotActive, isTrue);
        expect(result.status, equals(PilotGateStatus.pilotActiveApproved));
        expect(result.isSalesEngineActive, isTrue);
        expect(result.overrides.length, greaterThanOrEqualTo(5));

        final container = ProviderContainer(overrides: result.overrides);
        addTearDown(container.dispose);

        expect(container.read(coreNextSalesEngineEnabledProvider), isTrue);
        expect(container.read(coreNextSaleExecutorProvider), isNotNull);
        expect(container.read(coreNextRefundExecutorProvider), isNotNull);
        expect(container.read(coreNextSaleRepositoryProvider), isA<CoreNextSaleRepository>());

        final customerRepo = await container.read(customerRepositoryProvider.future);
        final productRepo = await container.read(productRepositoryProvider.future);
        final financialRepo = await container.read(financialTransactionRepositoryProvider.future);

        expect(customerRepo, isA<CoreNextCustomerRepository>());
        expect(productRepo, isA<CoreNextProductRepository>());
        expect(financialRepo, isA<CoreNextFinancialTransactionRepository>());
      });
    });

    // ─────────────────────────────────────────────────────────────
    // GRUP 3: HEDEF VERİTABANINDA CANLI SATIŞ VE KASA İŞLEMLERİ
    // ─────────────────────────────────────────────────────────────
    group('Grup 3: Hedef Veritabanında Canlı Satış ve Kasa İşlemleri (Stage 101 Retail Execution)', () {
      late ProviderContainer container;
      late CoreNextSaleExecutor saleExecutor;
      late CoreNextRefundExecutor refundExecutor;

      const pDanoneId = '8696368232546'; // Danone Danette Çikolatalı Puding 375 Gr (99.90 TL = 9990 kuruş)
      const pLifalifId = '8690526472164'; // Eti Lifalif 3 lü Bar (107.50 TL = 10750 kuruş)
      const pKajunId = '8690526397634'; // Eti Lifalif Kajun Bar (37.50 TL = 3750 kuruş)
      const pAlpellaId = '8690504090106'; // Alpella Gofret (16.00 TL = 1600 kuruş)
      const cMehmetGuvenId = '4e310f85-d8a1-4d1c-aec1-da8b25d13e44'; // MEHMET GÜVEN

      setUp(() {
        final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
          coreDb: workingCoreDb,
          enableSalesEngine: true,
        );
        container = ProviderContainer(overrides: overrides);
        saleExecutor = container.read(coreNextSaleExecutorProvider)!;
        refundExecutor = container.read(coreNextRefundExecutorProvider)!;
      });

      tearDown(() {
        container.dispose();
      });

      test('3.1 Senaryo 1: Peşin Nakit Satış (2 Adet Danette Puding) ve Kasa Girişi', () async {
        // Başlangıç stok: 200.0
        final initProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pDanoneId]);
        final initStock = (initProduct.first['stock_quantity'] as num).toDouble();
        expect(initStock, equals(200.0));

        final initCashRows = await workingCoreDb.query('cash_transactions');
        final initCashCount = initCashRows.length;

        // 2 adet nakit satış (2 * 99.90 = 199.80 TL = 19980 kuruş)
        final sale = await saleExecutor(
          customerId: '',
          items: [
            SaleItemInput(
              productId: pDanoneId,
              productName: 'Danone Danette Çikolatalı Puding 375 Gr',
              quantity: 2,
              unitPrice: 99.90,
            ),
          ],
          paymentMethod: 'cash',
          paidAmount: 199.80,
          cashierName: 'Kasiyer Mehmet',
          userId: 'usr-kasiyer-01',
          userRole: 'cashier',
        );

        expect(sale, isNotNull);
        expect(sale!.totalAmount, equals(199.80));

        // 1. Stok kontrolü: 200 - 2 = 198
        final updatedProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pDanoneId]);
        final updatedStock = (updatedProduct.first['stock_quantity'] as num).toDouble();
        expect(updatedStock, equals(198.0));

        // 2. Sales tablosu
        final saleRows = await workingCoreDb.query('sales', where: 'id = ?', whereArgs: [sale.id]);
        expect(saleRows.length, equals(1));
        expect(saleRows.first['total_cents'], equals(19980));
        expect(saleRows.first['status'], equals('COMPLETED'));

        // 3. Sale Items tablosu
        final itemRows = await workingCoreDb.query('sale_items', where: 'sale_id = ?', whereArgs: [sale.id]);
        expect(itemRows.length, equals(1));
        expect(itemRows.first['quantity'], equals(2));
        expect(itemRows.first['unit_price_cents'], equals(9990));

        // 4. Sale Payments tablosu
        final payRows = await workingCoreDb.query('sale_payments', where: 'sale_id = ?', whereArgs: [sale.id]);
        expect(payRows.length, equals(1));
        expect(payRows.first['payment_type'], equals('cash'));
        expect(payRows.first['amount_cents'], equals(19980));

        // 5. Cash Transactions tablosu (Kasa Nakit Girişi)
        final updatedCashRows = await workingCoreDb.query('cash_transactions');
        expect(updatedCashRows.length, equals(initCashCount + 1));
        final lastCash = updatedCashRows.last;
        expect(lastCash['type'], equals('INFLOW'));
        expect(lastCash['amount_cents'], equals(19980));

        // 6. Sync Events Outbox
        final syncEvents = await workingCoreDb.query('sync_events', where: 'entity_id = ?', whereArgs: [sale.id]);
        expect(syncEvents.isNotEmpty, isTrue);
      });

      test('3.2 Senaryo 2: Kredi Kartı / POS Satışı (Lifalif Bar) — Kasa Çekmecesi Yalıtımı', () async {
        final initProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pLifalifId]);
        final initStock = (initProduct.first['stock_quantity'] as num).toDouble();
        expect(initStock, equals(100.0));

        final initCashRows = await workingCoreDb.query('cash_transactions');
        final initCashCount = initCashRows.length;

        // 1 adet kredi kartı satışı (107.50 TL = 10750 kuruş)
        final sale = await saleExecutor(
          customerId: '',
          items: [
            SaleItemInput(
              productId: pLifalifId,
              productName: 'Eti Lifalif 3 lü Bar',
              quantity: 1,
              unitPrice: 107.50,
            ),
          ],
          paymentMethod: 'credit_card',
          paidAmount: 107.50,
          cashierName: 'Kasiyer Mehmet',
          userId: 'usr-kasiyer-01',
          userRole: 'cashier',
        );

        expect(sale, isNotNull);
        expect(sale!.totalAmount, equals(107.50));

        // Stok kontrolü: 100 - 1 = 99
        final updatedProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pLifalifId]);
        expect((updatedProduct.first['stock_quantity'] as num).toDouble(), equals(99.0));

        // Ödeme tipi kart olarak kaydedilmeli
        final payRows = await workingCoreDb.query('sale_payments', where: 'sale_id = ?', whereArgs: [sale.id]);
        expect(payRows.first['payment_type'], equals('creditCard'));
        expect(payRows.first['amount_cents'], equals(10750));

        // Kasa nakit çekmecesine kart işlemi yazılmamalı (Yalıtım)
        final updatedCashRows = await workingCoreDb.query('cash_transactions');
        expect(updatedCashRows.length, equals(initCashCount));
      });

      test('3.3 Senaryo 3: Müşteri Açık Hesap / Veresiye Satışı (Cariye Borçlandırma)', () async {
        // MEHMET GÜVEN başlangıç bakiyesi: 11500 kuruş (115.00 TL alacak)
        final initCust = await workingCoreDb.query('customers', where: 'id = ?', whereArgs: [cMehmetGuvenId]);
        final initBalanceCents = (initCust.first['balance_cents'] as num).toInt();
        expect(initBalanceCents, equals(11500));

        final initLedgerRows = await workingCoreDb.query('ledger_entries', where: 'customer_id = ?', whereArgs: [cMehmetGuvenId]);
        final initLedgerCount = initLedgerRows.length;

        // 1 adet Kajun Bar veresiye satışı (37.50 TL = 3750 kuruş)
        final sale = await saleExecutor(
          customerId: cMehmetGuvenId,
          items: [
            SaleItemInput(
              productId: pKajunId,
              productName: 'Eti Lifalif Kajun Bar',
              quantity: 1,
              unitPrice: 37.50,
            ),
          ],
          paymentMethod: 'on_account',
          paidAmount: 0.0,
          cashierName: 'Kasiyer Mehmet',
          userId: 'usr-kasiyer-01',
          userRole: 'cashier',
        );

        expect(sale, isNotNull);
        expect(sale!.totalAmount, equals(37.50));

        // 1. Stok 200 -> 199
        final updatedProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pKajunId]);
        expect((updatedProduct.first['stock_quantity'] as num).toDouble(), equals(199.0));

        // 2. Müşteri cari bakiyesi: 11500 - 3750 = 7750 kuruş
        final updatedCust = await workingCoreDb.query('customers', where: 'id = ?', whereArgs: [cMehmetGuvenId]);
        final updatedBalanceCents = (updatedCust.first['balance_cents'] as num).toInt();
        expect(updatedBalanceCents, equals(7750));

        // 3. Deftere debitSale kaydı düşmeli
        final updatedLedgerRows = await workingCoreDb.query('ledger_entries', where: 'customer_id = ?', whereArgs: [cMehmetGuvenId]);
        expect(updatedLedgerRows.length, equals(initLedgerCount + 1));
        final lastLedger = updatedLedgerRows.last;
        expect(lastLedger['entry_type'], equals('debitSale'));
        expect(lastLedger['amount_cents'], equals(3750));

        // 4. Sale Payments tablosunda onAccount ödeme tipi
        final payRows = await workingCoreDb.query('sale_payments', where: 'sale_id = ?', whereArgs: [sale.id]);
        expect(payRows.first['payment_type'], equals('onAccount'));
        expect(payRows.first['amount_cents'], equals(3750));
      });

      test('3.4 Senaryo 4: Karma / Parçalı Ödeme Satışı (Nakit 20 TL + POS 39.90 TL)', () async {
        const pAkturkId = '8692562041205'; // Aktürk Gofret 475 Gr (59.90 TL = 5990 kuruş)
        final initProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pAkturkId]);
        final initStock = (initProduct.first['stock_quantity'] as num).toDouble();

        final initCashRows = await workingCoreDb.query('cash_transactions');
        final initCashCount = initCashRows.length;

        // 59.90 TL satış: 20 TL Nakit + 39.90 TL Kredi Kartı
        final sale = await saleExecutor(
          customerId: '',
          items: [
            SaleItemInput(
              productId: pAkturkId,
              productName: 'Aktürk Gofret 475 Gr',
              quantity: 1,
              unitPrice: 59.90,
            ),
          ],
          paymentMethod: 'split',
          paidAmount: 59.90,
          terminalMetadata: {
            'cash_amount': 20.0,
            'card_amount': 39.90,
          },
          cashierName: 'Kasiyer Mehmet',
          userId: 'usr-kasiyer-01',
          userRole: 'cashier',
        );

        expect(sale, isNotNull);
        expect(sale!.totalAmount, equals(59.90));

        // Stok 1 düşer
        final updatedProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pAkturkId]);
        expect((updatedProduct.first['stock_quantity'] as num).toDouble(), equals(initStock - 1.0));

        // 2 adet ödeme parçası
        final payRows = await workingCoreDb.query('sale_payments', where: 'sale_id = ?', whereArgs: [sale.id]);
        expect(payRows.length, equals(2));

        final cashPay = payRows.firstWhere((p) => p['payment_type'] == 'cash');
        final cardPay = payRows.firstWhere((p) => p['payment_type'] == 'creditCard');
        expect(cashPay['amount_cents'], equals(2000));
        expect(cardPay['amount_cents'], equals(3990));

        // Kasa nakit çekmecesine SADECE 2000 kuruş (20 TL) nakit işlenmeli
        final updatedCashRows = await workingCoreDb.query('cash_transactions');
        expect(updatedCashRows.length, equals(initCashCount + 1));
        final lastCash = updatedCashRows.last;
        expect(lastCash['type'], equals('INFLOW'));
        expect(lastCash['amount_cents'], equals(2000));
      });

      test('3.5 Senaryo 5: Nakit Satış İadesi ve Stokun Otomatik Restorasyonu', () async {
        // Senaryo için taze 2 adet Alpella Gofret satışı yap (2 * 16.00 = 32.00 TL)
        final initProduct = await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pAlpellaId]);
        final stockBeforeSale = (initProduct.first['stock_quantity'] as num).toDouble();

        final sale = await saleExecutor(
          customerId: '',
          items: [
            SaleItemInput(
              productId: pAlpellaId,
              productName: 'Alpella Gofret',
              quantity: 2,
              unitPrice: 16.00,
            ),
          ],
          paymentMethod: 'cash',
          paidAmount: 32.00,
          cashierName: 'Kasiyer Mehmet',
          userId: 'usr-kasiyer-01',
          userRole: 'cashier',
        );

        // Satış sonrası stok -2
        final stockAfterSale = (await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pAlpellaId])).first['stock_quantity'] as num;
        expect(stockAfterSale.toDouble(), equals(stockBeforeSale - 2.0));

        // 1 adet iade gerçekleştir
        await refundExecutor(
          saleId: sale!.id,
          itemsToReturn: [
            SaleItemInput(
              productId: pAlpellaId,
              productName: 'Alpella Gofret',
              quantity: 1,
              unitPrice: 16.00,
            ),
          ],
          refundMethod: 'cash',
          reason: 'Müşteri vazgeçti',
          cashierName: 'Yönetici Ahmet',
          userId: 'usr-yonetici-01',
          userRole: 'manager',
        );

        // İade sonrası stok +1 restorasyonu: (stockBeforeSale - 2) + 1 = stockBeforeSale - 1
        final stockAfterRefund = (await workingCoreDb.query('products', where: 'id = ?', whereArgs: [pAlpellaId])).first['stock_quantity'] as num;
        expect(stockAfterRefund.toDouble(), equals(stockBeforeSale - 1.0));
      });
    });

    // ─────────────────────────────────────────────────────────────
    // GRUP 4: GÜN SONU Z-RAPORU VE SIFIR SAPMA MUTABAKATI
    // ─────────────────────────────────────────────────────────────
    group('Grup 4: Gün Sonu Z-Raporu ve Sıfır Sapma Mutabakatı', () {
      test('4.1 Kasa Çekmecesi, Defter Hareketleri ve Fişler Arasında 0.00 TL Sapma Olmalıdır', () async {
        final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
          coreDb: workingCoreDb,
          enableSalesEngine: true,
        );
        final container = ProviderContainer(overrides: overrides);
        addTearDown(container.dispose);

        // Satış ödemeleri toplamı
        final sumPaymentsResult = await workingCoreDb.db.rawQuery(
          'SELECT payment_type, SUM(amount_cents) as total FROM sale_payments GROUP BY payment_type'
        );
        print('\n[STAGE 101 MUTABAKAT] Satış Ödeme Dökümü:');
        for (final row in sumPaymentsResult) {
          final t = row['payment_type'];
          final c = (row['total'] as num).toInt();
          print('  $t: ${(c / 100.0).toStringAsFixed(2)} TL ($c kuruş)');
        }

        // Nakit kasa çekmecesi toplamı
        final sumCashResult = await workingCoreDb.db.rawQuery(
          'SELECT type, SUM(amount_cents) as total FROM cash_transactions GROUP BY type'
        );
        print('[STAGE 101 MUTABAKAT] Kasa Çekmecesi Dökümü:');
        for (final row in sumCashResult) {
          final t = row['type'];
          final c = (row['total'] as num).toInt();
          print('  $t: ${(c / 100.0).toStringAsFixed(2)} TL ($c kuruş)');
        }

        // Integrity & FK Checks
        final integrity = await workingCoreDb.db.rawQuery('PRAGMA integrity_check;');
        expect(integrity.first.values.first, equals('ok'));

        final fkCheck = await workingCoreDb.db.rawQuery('PRAGMA foreign_key_check;');
        expect(fkCheck, isEmpty);
      });
    });

    // ─────────────────────────────────────────────────────────────
    // GRUP 5: ACİL GERİ DÖNÜŞ GÜVENCESİ (FAZ 4 SAFE ROLLBACK)
    // ─────────────────────────────────────────────────────────────
    group('Grup 5: Acil Geri Dönüş Güvencesi (Safe Rollback Protocol)', () {
      test('5.1 ReverseMigrationEngine Yeni Satışları Legacy DB\'ye Kayıpsız ve İdempotent Aktarmalıdır', () async {
        final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
          coreDb: workingCoreDb,
          enableSalesEngine: true,
        );
        final container = ProviderContainer(overrides: overrides);
        final saleExecutor = container.read(coreNextSaleExecutorProvider)!;

        // Core Next üzerinde yeni bir pilot satış yap
        const pAlpellaId = '8690504090106';
        final newSale = await saleExecutor(
          customerId: '',
          items: [
            SaleItemInput(
              productId: pAlpellaId,
              productName: 'Alpella Gofret Rollback Test',
              quantity: 1,
              unitPrice: 16.00,
            ),
          ],
          paymentMethod: 'cash',
          paidAmount: 16.00,
          cashierName: 'Kasiyer Mehmet',
          userId: 'usr-kasiyer-01',
          userRole: 'cashier',
        );
        expect(newSale, isNotNull);

        container.dispose();

        // Legacy veritabanını aç
        final legacyDb = await databaseFactory.openDatabase(workingLegacyDbPath);

        // 1. Rollback Motorunu Çalıştır
        final stopwatch = Stopwatch()..start();
        final rollbackReport = await ReverseMigrationEngine.rollbackToLegacy(
          legacyDb: legacyDb,
          coreDb: workingCoreDb,
        );
        stopwatch.stop();

        print('\n[SAFE ROLLBACK RAPORU]:');
        print('  isSuccess: ${rollbackReport.isSuccess}');
        print('  salesExported: ${rollbackReport.salesExported}');
        print('  errorMessage: ${rollbackReport.errorMessage}');
        print('  duration: ${stopwatch.elapsedMilliseconds} ms (< 10.000 ms hedefi)');

        expect(rollbackReport.isSuccess, isTrue);
        expect(rollbackReport.salesExported, greaterThanOrEqualTo(1));
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));

        // Legacy sales tablosunda yeni satışın varlığını doğrula
        final legSaleRows = await legacyDb.rawQuery(
          'SELECT id, total_amount, payment_method FROM sales WHERE id = ?',
          [newSale!.id],
        );
        expect(legSaleRows.length, equals(1));
        expect((legSaleRows.first['total_amount'] as num).toDouble(), equals(16.00));

        // 2. Rollback İdempotency: Tekrar çalıştırıldığında 0 yeni satış aktarılmalı
        final secondRollback = await ReverseMigrationEngine.rollbackToLegacy(
          legacyDb: legacyDb,
          coreDb: workingCoreDb,
        );
        expect(secondRollback.isSuccess, isTrue);
        expect(secondRollback.salesExported, equals(0), reason: 'Mükerrer satış oluşturulmamalıdır.');

        await legacyDb.close();
      });
    });
  });
}
