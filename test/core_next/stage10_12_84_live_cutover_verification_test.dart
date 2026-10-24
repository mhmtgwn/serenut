// test/core_next/stage10_12_84_live_cutover_verification_test.dart
// SERENUT OS — STAGE 10.12.84
// CANLI GEÇİŞ ÇALIŞMA ANINDA DOĞRULAMA TESTİ (LIVE RUNTIME VERIFICATION)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_product_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.84: Nutopia Canlı Geçiş Çalışma Anı Doğrulaması', () {
    const nutopiaMerchantId = 'comp-1785241628448-c7f5677d';
    const erkulMerchantId = 'comp-1791194455402-bdc6d8d1';
    final liveDeployedCorePath = r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_core_v2.db';
    final legacyDbPath = r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db';

    setUp(() {
      DatabaseManager.overrideDatabasePath = legacyDbPath;
      DatabaseManager.overrideCoreNextDatabasePath = liveDeployedCorePath;
    });

    test('1. Nutopia için AppBootstrap.initPreApp() Core Next depolarına yönlendirir ve 37.682 ürün doğrulanır', () async {
      SharedPreferences.setMockInitialValues({
        'core_next_pilot_enabled': true,
        'core_next_kill_switch': false,
        'core_next_bootstrap_migration_state': 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
        'core_next_migration_backup_path': legacyDbPath,
      });

      // AppBootstrap.initPreApp() çağrısı Nutopia Merchant ID ile işletilir
      final bootstrapResult = await AppBootstrap.initPreApp(
        requestedTenantId: nutopiaMerchantId,
      );

      final pilotResult = bootstrapResult.pilotGateResult;
      expect(pilotResult, isNotNull);
      print('NUTOPIA PILOT GATE RESULT:');
      print('  isPilotActive: ${pilotResult!.isPilotActive}');
      print('  status: ${pilotResult.status}');
      print('  reason: ${pilotResult.reason}');
      print('  targetDbPath: ${pilotResult.targetDbPath}');

      // Kanıt 1: Pilot Kapısı onaylandı
      expect(pilotResult.isPilotActive, isTrue);
      expect(pilotResult.status, equals(PilotGateStatus.pilotActiveApproved));

      // Kanıt 2: AppBootstrap tarafından üretilen Riverpod Container'ında Core Next repository'leri aktif
      final container = ProviderContainer(
        overrides: bootstrapResult.overrides,
        observers: bootstrapResult.observers,
      );

      final productRepo = await container.read(productRepositoryProvider.future);
      final customerRepo = await container.read(customerRepositoryProvider.future);

      expect(productRepo is CoreNextProductRepository, isTrue);
      expect(customerRepo is CoreNextCustomerRepository, isTrue);
      print('  Repository türleri: product=${productRepo.runtimeType}, customer=${customerRepo.runtimeType}');

      // Kanıt 3: Core Next reposundan doğrudan canlı veriler sorgulanır
      final allProducts = await productRepo.findAll();
      final allCustomers = await customerRepo.findAll();
      print('  Core Next canlı repo verileri: ${allProducts.length} aktif ürün, ${allCustomers.length} aktif müşteri');

      expect(allProducts.length, equals(17));
      expect(allCustomers.length, equals(619));

      // Kanıt 4: Doğrudan Core Next DB üzerinde toplam kayıt sayıları doğrulanır
      final directDb = await databaseFactory.openDatabase(liveDeployedCorePath, options: OpenDatabaseOptions(readOnly: true));
      final totalProducts = (await directDb.rawQuery('SELECT COUNT(*) as c FROM products;')).first['c'];
      final totalCustomers = (await directDb.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'];
      await directDb.close();

      print('  Core Next DB toplam kayıtları: $totalProducts ürün, $totalCustomers müşteri');
      expect(totalProducts, equals(37682));
      expect(totalCustomers, equals(626));

      container.dispose();
    });

    test('2. Erkul Çeyiz Nutopia DB açılışı denerse derhal fail-closed kilitlenir (Legacy Korunur)', () async {
      SharedPreferences.setMockInitialValues({
        'core_next_pilot_enabled': true,
        'core_next_kill_switch': false,
        'core_next_bootstrap_migration_state': 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
        'core_next_migration_backup_path': legacyDbPath,
      });

      final bootstrapResult = await AppBootstrap.initPreApp(
        requestedTenantId: erkulMerchantId,
      );

      final pilotResult = bootstrapResult.pilotGateResult;
      expect(pilotResult, isNotNull);
      print('ERKUL PILOT GATE RESULT:');
      print('  isPilotActive: ${pilotResult!.isPilotActive}');
      print('  status: ${pilotResult.status}');
      print('  reason: ${pilotResult.reason}');

      // Kanıt 4: Erkul Çeyiz için Core Next pilot KESİNLİKLE KAPALIDIR
      expect(pilotResult.isPilotActive, isFalse);
      expect(pilotResult.status, equals(PilotGateStatus.blockedTenantMismatch));

      // Kanıt 5: Erkul için repository'ler Legacy SQLite olarak kalır
      final container = ProviderContainer(
        overrides: bootstrapResult.overrides,
        observers: bootstrapResult.observers,
      );

      final productRepo = await container.read(productRepositoryProvider.future);
      final customerRepo = await container.read(customerRepositoryProvider.future);

      expect(productRepo is SqliteProductRepository, isTrue);
      expect(customerRepo is SqliteCustomerRepository, isTrue);
      print('  Erkul Repository türleri: product=${productRepo.runtimeType}, customer=${customerRepo.runtimeType}');

      container.dispose();
    });
  });
}
