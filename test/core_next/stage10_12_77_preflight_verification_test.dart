// test/core_next/stage10_12_77_preflight_verification_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/services/tenant_identity_resolver.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const targetPath = 'backups/nutopia_live_20261021_2055/nutopia_core_next_live.db';
  const legacyBackupPath = 'backups/nutopia_live_20261021_2055/nutopia_live_backup.db';

  group('STAGE 10.12.77: Nutopia Kontrollü Preflight ve Güvenlik Denetimi', () {
    test('1. Tenant Eşleşmesi ve Lisans Doğrulaması', () {
      // 1. Nutopia Cloud Merchant ID <-> slug
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'comp-1785241628448-c7f5677d',
          dbTenantId: 'nutopia',
        ),
        isTrue,
      );

      // 2. Erkul Cloud ID Nutopia DB'sine verilirse -> Kesinlikle Ret
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'comp-1791194455402-bdc6d8d1',
          dbTenantId: 'nutopia',
        ),
        isFalse,
      );

      // 3. Bilinmeyen veya boş ID -> Kesinlikle Ret
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'unknown-merchant-id',
          dbTenantId: 'nutopia',
        ),
        isFalse,
      );
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: null,
          dbTenantId: 'nutopia',
        ),
        isFalse,
      );
    });

    test('2. AppBootstrap İçindeki Varsayılan Gate Durumu (Override Generator Enjeksiyonu)', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
        CoreNextBootstrapCoordinator.prefKeyBackupPath: File(legacyBackupPath).absolute.path,
      });
      final prefs = await SharedPreferences.getInstance();

      // AppBootstrap.initPreApp() default gate: const PilotCutoverGate() (overrideGenerator: null)
      const unconfiguredGate = PilotCutoverGate();

      final result = await unconfiguredGate.evaluate(
        prefs: prefs,
        legacyDbPath: File(legacyBackupPath).absolute.path,
        targetDbPath: File(targetPath).absolute.path,
        requestedTenantId: 'comp-1785241628448-c7f5677d',
      );

      print('UNCONFIGURED GATE EVAL: status=${result.status}, reason=${result.reason}');
      // Kanıt: Override generator enjekte edilmemişse fail-closed koruması devreye girmeli
      expect(result.status, equals(PilotGateStatus.blockedMissingConfiguration));
      expect(result.isPilotActive, isFalse);
    });

    test('3. Hedef DB (nutopia_core_next_live.db) Salt-Okunur İşlev ve Veri Kontrolü', () async {
      final db = await openDatabase(
        File(targetPath).absolute.path,
        readOnly: true,
      );

      try {
        // A) PRAGMA Bütünlük ve Versiyon
        final integrity = await db.rawQuery('PRAGMA integrity_check;');
        expect(integrity.first.values.first, equals('ok'));

        final userVersion = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version;'));
        expect(userVersion, equals(3));

        // B) Firma Kimliği
        final settings = await db.rawQuery("SELECT key, value FROM app_settings;");
        final sMap = {for (var r in settings) r['key'] as String: r['value'] as String};
        expect(sMap['tenant_id'], equals('nutopia'));
        expect(sMap['business_name'], equals('Nutopia Fındık Değirmeni'));
        expect(sMap['legacy_migration_completed'], equals('true'));

        // C) Müşteriler ve Bakiye Okuma
        final custCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers;'));
        expect(custCount, equals(626));

        final targetBalanceSum = Sqflite.firstIntValue(
          await db.rawQuery('SELECT SUM(balance_cents) FROM customers'),
        );
        expect(targetBalanceSum, equals(-13526318)); // -135,263.18 TL

        final sampleCustomer = await db.rawQuery('SELECT id, name, balance_cents FROM customers LIMIT 3;');
        expect(sampleCustomer.length, equals(3));
        for (var c in sampleCustomer) {
          expect(c['name'], isNotNull);
          expect(c['balance_cents'], isNotNull);
        }

        // D) Ürünler ve Stok Okuma
        final prodCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products;'));
        expect(prodCount, equals(37682));

        final sampleProduct = await db.rawQuery('SELECT id, name, stock_quantity, price_cents FROM products LIMIT 3;');
        expect(sampleProduct.length, equals(3));
        for (var p in sampleProduct) {
          expect(p['name'], isNotNull);
          expect(p['stock_quantity'], isNotNull);
          expect(p['price_cents'], isNotNull);
        }

        // E) Satışlar, Siparişler, Senetler, Taksitler ve Finansal Hareketler
        final saleCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sales;'));
        expect(saleCount, equals(52));

        final ledgerCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ledger_entries;'));
        expect(ledgerCount, equals(1505));

        final cashCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM cash_transactions;'));
        expect(cashCount, equals(21));
        expect(ledgerCount! + cashCount!, equals(1526));

        final orderCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM orders;'));
        expect(orderCount, equals(846));

        final planCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customer_installment_plans;'));
        expect(planCount, equals(2));

        final installmentCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customer_installments;'));
        expect(installmentCount, equals(9));

        final negInst = await db.rawQuery(
          "SELECT id, amount_cents FROM customer_installments WHERE id = 'inst-ab6352d3-eeee-4f64-a2d0-923554147896';",
        );
        expect(negInst.first['amount_cents'], equals(-446532));

        print('TARGET DB AUDIT OK: 626 customers, 37682 products, 1505 ledger, 21 cash (1526 total), 52 sales, 846 orders, 2 plans, 9 installments (negative inst preserved)');
      } finally {
        await db.close();
      }
    });

    test('4. DualDatabaseRoutingCoordinator Nutopia Cloud ID ile Başarıyla Açılır ve Override Üretir', () async {
      final coordinator = const DualDatabaseRoutingCoordinator();
      final routing = await coordinator.resolveAndOpen(
        requestedTenantId: 'comp-1785241628448-c7f5677d',
        legacyDbPath: File(legacyBackupPath).absolute.path,
        targetDbPath: File(targetPath).absolute.path,
        migrationStateCompleted: true,
      );

      expect(routing.isSuccess, isTrue);
      expect(routing.targetDatabase, isNotNull);

      final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: routing.targetDatabase!,
        enableSalesEngine: false,
      );

      expect(overrides.length, equals(3)); // Customer, Product, FinancialTransaction
      await routing.targetDatabase?.close();
    });
  });
}
