// test/core_next/stage10_12_100_rollback_and_critical_flows_test.dart
// SERENUT OS — STAGE 10.12.100
// Geri Dönüş Güvencesi, Kritik İşlevler ve Çalışma Zamanı Korumaları Test Paketi
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart' as core;
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_sale_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.100 — Geri Dönüş ve Kritik İşlevler Testleri', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    late String backupPath;
    late CoreAppDatabase coreDb;

    const nutopiaTenantId = 'comp-nutopia-01';
    const testProductId = 'prod-stage100-01';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('stage10_12_100_test_');
      legacyDbPath = p.join(tempDir.path, 'serenut_pos_legacy.db');
      targetDbPath = p.join(tempDir.path, 'serenut_core_v2_target.db');
      backupPath = p.join(tempDir.path, 'test_backup.db');

      // 1. Sahte Yedek Dosyası (En az 512 bayt olmalı)
      final bFile = File(backupPath);
      await bFile.writeAsString('BACKUP_MOCK'.padRight(600, '0'));

      // 2. Legacy Veritabanı Oluştur
      final legDb = await openDatabase(legacyDbPath, version: 60);
      await legDb.execute('CREATE TABLE IF NOT EXISTS settings (id TEXT PRIMARY KEY, business_name TEXT);');
      await legDb.execute('''
        CREATE TABLE IF NOT EXISTS sales (
          id TEXT PRIMARY KEY,
          customer_id TEXT,
          total_amount REAL,
          total_amount_minor INTEGER,
          paid_amount REAL,
          discount_amount REAL,
          payment_method TEXT,
          status TEXT,
          created_at TEXT
        );
      ''');
      await legDb.execute('''
        CREATE TABLE IF NOT EXISTS customers (
          id TEXT PRIMARY KEY,
          name TEXT,
          balance REAL,
          balance_minor INTEGER,
          created_at TEXT
        );
      ''');
      await legDb.execute('''
        CREATE TABLE IF NOT EXISTS products (
          id TEXT PRIMARY KEY,
          name TEXT,
          price REAL,
          price_minor INTEGER,
          quantity REAL
        );
      ''');
      await legDb.execute('''
        CREATE TABLE IF NOT EXISTS financial_transactions (
          id TEXT PRIMARY KEY,
          customer_id TEXT,
          amount REAL,
          amount_minor INTEGER,
          type TEXT,
          reference_id TEXT,
          created_at TEXT
        );
      ''');
      await legDb.close();

      // 3. Hedef Core Next Veritabanı Oluştur (Şema v3)
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      await coreDb.db.rawQuery('PRAGMA user_version = 3;');

      // app_settings tenant ID kaydet
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': nutopiaTenantId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Test Ürünü Ekle
      await coreDb.db.insert('products', {
        'id': testProductId,
        'barcode': '8690001001',
        'name': 'Fındık Ezmesi Stage 100',
        'price_cents': 15000,
        'vat_rate': 1,
        'unit': 'piece',
        'stock_quantity': 25,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await coreDb.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Değişmez Kural: coreNextSalesEngineEnabledProvider varsayılan olarak false kalmalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(isEnabled, isFalse, reason: 'Canlı satış motoru kapalı kalmalıdır.');
      expect(coreNextSalesEngineEnabledProvider.name, equals('coreNextSalesEngineEnabledProvider'));
      expect(coreNextSaleExecutorProvider.name, equals('coreNextSaleExecutorProvider'));
      expect(coreNextRefundExecutorProvider.name, equals('coreNextRefundExecutorProvider'));
      expect(coreNextSaleRepositoryProvider.name, equals('coreNextSaleRepositoryProvider'));
    });

    test('2. Geri Dönüş Devam Ederken (in_progress) Pilot Gate Fail-Closed Engeller', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        CoreNextBootstrapCoordinator.prefKeyBackupPath: backupPath,
        'core_next_rollback_state': 'in_progress', // Geri dönüş bitmemiş
      });
      final prefs = await SharedPreferences.getInstance();

      final gate = PilotCutoverGate(
        overrideGenerator: ({
          required String requestedTenantId,
          required String legacyDbPath,
          required String targetDbPath,
          required bool enableSalesEngine,
          DatabaseFactory? dbFactory,
        }) async => [],
      );

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: nutopiaTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedUnsafeRollback));
    });

    test('3. Kısmi Tahsilat (recordPartialPayment) Core Next Motorunda UnsupportedError Fırlatır', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          saleRepositoryProvider.overrideWith(
            (ref) => Future.value(CoreNextSaleRepository.fromCoreAppDatabase(coreDb)),
          ),
          salesServiceProvider.overrideWith(
            (ref) => Future.value(_FakeSalesService()),
          ),
          coreNextSalesEngineEnabledProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(salesControllerProvider.notifier);
      await expectLater(
        controller.recordPartialPayment(
          saleId: 'sale-dummy-test',
          amount: 50.0,
          method: 'cash',
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('Cari tahsilatı müşteri detay sayfasından (Tahsilat Yap) yürütülmelidir'),
          ),
        ),
      );
    });

    test('4. Kartlı Satış İadesi: Harici POS Entegrasyonu Olmadığında Otomatik İade Engellenir', () async {
      // 1. Müşteri ve Kartlı Satış Kaydı Oluştur
      const cardSaleId = 'sale-card-test-01';
      await coreDb.db.insert('customers', {
        'id': 'cust-01',
        'name': 'Test Müşteri 01',
        'balance_cents': 0,
        'credit_limit_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sales', {
        'id': cardSaleId,
        'receipt_no': 'REC-CARD-001',
        'customer_id': 'cust-01',
        'subtotal_cents': 15000,
        'total_cents': 15000,
        'paid_cents': 15000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sale_items', {
        'id': 'item-card-01',
        'sale_id': cardSaleId,
        'product_id': testProductId,
        'barcode': '8690001001',
        'product_name': 'Fındık Ezmesi Stage 100',
        'unit_price_cents': 15000,
        'quantity': 1,
        'total_cents': 15000,
        'vat_rate': 1,
      });

      // Sadece Kredi Kartı Ödemesi Ekle
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-card-01',
        'sale_id': cardSaleId,
        'payment_type': 'creditCard',
        'amount_cents': 15000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final refundUseCase = CoreRefundUseCase(db: coreDb);
      final managerActor = ActorContext(
        userId: 'mgr-01',
        username: 'Yönetici',
        role: AppRole.manager,
      );

      // Kartlı satışa iade istendiğinde UnsupportedError fırlatılmalıdır
      await expectLater(
        refundUseCase.execute(
          RefundRequest(
            originalSaleId: cardSaleId,
            items: [RefundItemRequest(productId: testProductId, quantity: 1)],
            reason: 'Kartlı İade Denemesi',
            actor: managerActor,
          ),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('harici POS/kart terminali iade entegrasyonu bulunmamaktadır'),
          ),
        ),
      );
    });

    test('5. ReverseMigrationEngine İdempotency ve İçerik Çakışması Güvenliği', () async {
      final legDb = await openDatabase(legacyDbPath, version: 60);

      // Core Next DB'de yeni bir müşteri ve satış
      const newSaleId = 'sale-core-new-01';
      await coreDb.db.insert('customers', {
        'id': 'cust-new-01',
        'name': 'Yeni Core Müşteri',
        'balance_cents': 0,
        'credit_limit_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sales', {
        'id': newSaleId,
        'receipt_no': 'REC-NEW-001',
        'customer_id': 'cust-new-01',
        'subtotal_cents': 10000,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'discount_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // 1. İlk geri aktarım başarılı olmalı
      final report1 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legDb,
        coreDb: coreDb,
      );
      expect(report1.isSuccess, isTrue);
      expect(report1.salesExported, equals(1));

      // 2. İdempotency: Tekrar çalıştırıldığında 0 yeni satış aktarılmalı
      final report2 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legDb,
        coreDb: coreDb,
      );
      expect(report2.isSuccess, isTrue);
      expect(report2.salesExported, equals(0));

      // 3. İçerik Çakışması (Content Divergence): Legacy'deki satışın tutarı değiştirilirse işlem reddedilmeli
      await legDb.update('sales', {'total_amount': 250.0, 'total_amount_minor': 25000},
          where: 'id = ?', whereArgs: [newSaleId]);

      final report3 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legDb,
        coreDb: coreDb,
      );
      expect(report3.isSuccess, isFalse);
      expect(report3.errorMessage, contains('SATIŞ İÇERİK ÇAKIŞMASI TESPİT EDİLDİ'));

      await legDb.close();
    });
  });
}

class _FakeSalesService extends Fake implements SalesService {}
