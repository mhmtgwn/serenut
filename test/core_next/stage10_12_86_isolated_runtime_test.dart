// test/core_next/stage10_12_86_isolated_runtime_test.dart
// SERENUT OS — STAGE 10.12.86
// İZOLE FLUTTER RUNTIME VE GÜVENLİK DOĞRULAMA TESTİ

import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_product_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_financial_transaction_repository.dart';

class IsolatedPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String isolatedBaseDir;
  IsolatedPathProviderPlatform(this.isolatedBaseDir);

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(isolatedBaseDir, 'documents');

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(isolatedBaseDir, 'support');

  @override
  Future<String?> getTemporaryPath() async =>
      p.join(isolatedBaseDir, 'temp');

  @override
  Future<String?> getLibraryPath() async =>
      p.join(isolatedBaseDir, 'library');
}

String calculateSha256(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) return 'NOT_FOUND';
  final bytes = file.readAsBytesSync();
  return sha256.convert(bytes).toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const nutopiaMerchantId = 'comp-1785241628448-c7f5677d';
  const erkulMerchantId = 'comp-1791194455402-bdc6d8d1';

  final appDataDir = Platform.environment['APPDATA'] ?? '';
  final liveLegacyDbPath = p.join(appDataDir, 'Serenut OS Software Technologies A.Ş', 'Serenut OS', 'databases', 'serenut_pos.db');
  final liveCoreNextDbPath = p.join(appDataDir, 'Serenut OS Software Technologies A.Ş', 'Serenut OS', 'databases', 'serenut_core_v2.db');

  late Directory isolatedDir;
  late String isolatedLegacyPath;
  late String isolatedCoreNextPath;
  late String isolatedBackupPath;

  late String preLiveLegacySha;
  late String preLiveCoreSha;

  setUpAll(() async {
    // Canlı veritabanlarının test öncesi SHA-256 hashlerini kaydet
    preLiveLegacySha = calculateSha256(liveLegacyDbPath);
    preLiveCoreSha = calculateSha256(liveCoreNextDbPath);

    print('================================================================');
    print('[STAGE 10.12.86] CANLI VERİTABANI BAŞLANGIÇ HASH DEĞERLERİ:');
    print('  Canlı Legacy DB ($liveLegacyDbPath):');
    print('    SHA-256: $preLiveLegacySha');
    print('  Canlı Core Next DB ($liveCoreNextDbPath):');
    print('    SHA-256: $preLiveCoreSha');
    print('================================================================');
  });

  setUp(() async {
    // 1. Tamamen izole geçici çalışma dizini oluştur (Asla canlı AppData'ya dokunmaz)
    isolatedDir = await Directory.systemTemp.createTemp('serenut_stage86_isolated_');

    final dbsDir = Directory(p.join(isolatedDir.path, 'databases'))..createSync(recursive: true);
    final backupsDir = Directory(p.join(isolatedDir.path, 'backups'))..createSync(recursive: true);
    Directory(p.join(isolatedDir.path, 'documents')).createSync(recursive: true);
    Directory(p.join(isolatedDir.path, 'support')).createSync(recursive: true);
    Directory(p.join(isolatedDir.path, 'temp')).createSync(recursive: true);

    // 2. Doğrulanmış fixture dosyalarını izole hedeflere KOPYALA (Sembolik link veya junction KULLANILMAZ)
    isolatedLegacyPath = p.join(dbsDir.path, 'serenut_pos.db');
    isolatedCoreNextPath = p.join(dbsDir.path, 'serenut_core_v2.db');
    isolatedBackupPath = p.join(backupsDir.path, 'serenut_pos_backup.db');

    File('backups/nutopia_live_20261021_2055/nutopia_live_backup.db').copySync(isolatedLegacyPath);
    File('backups/nutopia_live_20261021_2055/nutopia_core_next_live.db').copySync(isolatedCoreNextPath);
    File('backups/nutopia_pre_cutover_rollback_20261021_2112/serenut_pos_pre_cutover_rollback.db').copySync(isolatedBackupPath);

    // 3. PathProviderPlatform'u izole dizine bağla
    PathProviderPlatform.instance = IsolatedPathProviderPlatform(isolatedDir.path);

    // 4. DatabaseManager override yollarını izole hedeflere bağla
    DatabaseManager.overrideDatabasePath = isolatedLegacyPath;
    DatabaseManager.overrideCoreNextDatabasePath = isolatedCoreNextPath;

    // 5. SharedPreferences'ı izole olarak konfigüre et
    SharedPreferences.setMockInitialValues({
      'core_next_pilot_enabled': true,
      'core_next_kill_switch': false,
      'core_next_bootstrap_migration_state': 'completed',
      'last_backup_date': DateTime.now().toIso8601String(),
      'core_next_migration_backup_path': isolatedBackupPath,
    });
  });

  tearDown(() async {
    try {
      await DatabaseManager.instance.close();
    } catch (_) {}
    if (isolatedDir.existsSync()) {
      try {
        isolatedDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('STAGE 10.12.86: İzole Flutter Runtime Doğrulaması', () {
    test('1. Nutopia için izole Flutter runtime başarıyla Core Next depolarına yönlenir ve verileri okur', () async {
      print('\n--- TEST 1: Nutopia İzole Runtime Pipeline Başlatılıyor ---');
      print('  İzole Çalışma Dizini: ${isolatedDir.path}');
      print('  İzole Legacy DB Yolu: $isolatedLegacyPath');
      print('  İzole Core Next DB Yolu: $isolatedCoreNextPath');

      // Gerçek AppBootstrap.initPreApp() çağrısı işletilir
      final bootstrap = await AppBootstrap.initPreApp(
        requestedTenantId: nutopiaMerchantId,
      );

      final pilotResult = bootstrap.pilotGateResult;
      expect(pilotResult, isNotNull);
      print('  PilotGate Sonucu:');
      print('    isPilotActive: ${pilotResult!.isPilotActive}');
      print('    status: ${pilotResult.status}');
      print('    reason: ${pilotResult.reason}');
      print('    targetDbPath: ${pilotResult.targetDbPath}');

      // 1. Kapı onayı kanıtı
      expect(pilotResult.isPilotActive, isTrue);
      expect(pilotResult.status, equals(PilotGateStatus.pilotActiveApproved));
      expect(pilotResult.targetDbPath, equals(isolatedCoreNextPath));

      // 2. Gerçek Riverpod ProviderContainer ayağa kaldırılır
      final container = ProviderContainer(
        overrides: bootstrap.overrides,
        observers: bootstrap.observers,
      );

      final productRepo = await container.read(productRepositoryProvider.future);
      final customerRepo = await container.read(customerRepositoryProvider.future);
      final financialRepo = await container.read(financialTransactionRepositoryProvider.future);
      final saleRepo = await container.read(saleRepositoryProvider.future);

      print('  Gerçek Repository Türleri:');
      print('    Product: ${productRepo.runtimeType}');
      print('    Customer: ${customerRepo.runtimeType}');
      print('    Financial: ${financialRepo.runtimeType}');
      print('    Sale: ${saleRepo.runtimeType}');

      expect(productRepo is CoreNextProductRepository, isTrue);
      expect(customerRepo is CoreNextCustomerRepository, isTrue);
      expect(financialRepo is CoreNextFinancialTransactionRepository, isTrue);
      // Satış motoru pilot güvenliği gereği legacy olarak tutulur
      expect(saleRepo is SqliteSaleRepository, isTrue);

      // 3. İzole Core Next deposundan okuma doğrulaması
      final activeProducts = await productRepo.findAll();
      final activeCustomers = await customerRepo.findAll();
      print('  İzole Depodan Okunan Kayıtlar:');
      print('    Aktif Ürün Sayısı: ${activeProducts.length}');
      print('    Aktif Müşteri Sayısı: ${activeCustomers.length}');

      expect(activeProducts.length, equals(17));
      expect(activeCustomers.length, equals(619));

      // 4. Doğrudan izole SQLite DB'den toplam tablo satırlarını doğrula
      final directDb = await databaseFactory.openDatabase(
        isolatedCoreNextPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final totalProducts = (await directDb.rawQuery('SELECT COUNT(*) as c FROM products;')).first['c'];
      final totalCustomers = (await directDb.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'];
      final totalLedger = (await directDb.rawQuery('SELECT COUNT(*) as c FROM ledger_entries;')).first['c'];
      final totalOrders = (await directDb.rawQuery('SELECT COUNT(*) as c FROM orders;')).first['c'];
      await directDb.close();

      print('  İzole DB Tablo Toplamları:');
      print('    products: $totalProducts');
      print('    customers: $totalCustomers');
      print('    ledger_entries: $totalLedger');
      print('    orders: $totalOrders');

      expect(totalProducts, equals(37682));
      expect(totalCustomers, equals(626));
      expect(totalLedger, equals(1505));
      expect(totalOrders, equals(846));

      container.dispose();
      print('  [PASS] Test 1 başarıyla tamamlandı.');
    });

    test('2. Erkul Çeyiz Nutopia veritabanına erişemez (Fail-Closed Tenant İzolasyonu)', () async {
      print('\n--- TEST 2: Erkul Çeyiz Çapraz Erişim Engeli Test Ediliyor ---');

      // Erkul Merchant ID ile açılış denenir
      final erkulBootstrap = await AppBootstrap.initPreApp(
        requestedTenantId: erkulMerchantId,
      );

      final erkulPilot = erkulBootstrap.pilotGateResult;
      expect(erkulPilot, isNotNull);
      print('  Erkul PilotGate Sonucu:');
      print('    isPilotActive: ${erkulPilot!.isPilotActive}');
      print('    status: ${erkulPilot.status}');
      print('    reason: ${erkulPilot.reason}');

      // Fail-Closed tenant koruması doğrulanır
      expect(erkulPilot.isPilotActive, isFalse);
      expect(erkulPilot.status, equals(PilotGateStatus.blockedTenantMismatch));

      // Erkul için repository'lerin Legacy SQLite olarak kaldığı doğrulanır
      final container = ProviderContainer(
        overrides: erkulBootstrap.overrides,
        observers: erkulBootstrap.observers,
      );

      final productRepo = await container.read(productRepositoryProvider.future);
      final customerRepo = await container.read(customerRepositoryProvider.future);

      print('  Erkul Repository Türleri:');
      print('    Product: ${productRepo.runtimeType}');
      print('    Customer: ${customerRepo.runtimeType}');

      expect(productRepo is SqliteProductRepository, isTrue);
      expect(customerRepo is SqliteCustomerRepository, isTrue);

      container.dispose();
      print('  [PASS] Test 2 başarıyla tamamlandı.');
    });

    test('3. Canlı veritabanlarının SHA-256 hashleri test öncesi ve sonrası kesinlikle değişmemiştir', () async {
      print('\n--- TEST 3: Canlı Veritabanı Değişmezlik Doğrulaması ---');

      final postLiveLegacySha = calculateSha256(liveLegacyDbPath);
      final postLiveCoreSha = calculateSha256(liveCoreNextDbPath);

      print('  Canlı Legacy DB ($liveLegacyDbPath):');
      print('    Önceki: $preLiveLegacySha');
      print('    Sonraki: $postLiveLegacySha');

      print('  Canlı Core Next DB ($liveCoreNextDbPath):');
      print('    Önceki: $preLiveCoreSha');
      print('    Sonraki: $postLiveCoreSha');

      expect(postLiveLegacySha, equals(preLiveLegacySha),
          reason: 'Canlı legacy veritabanına asla yazılmamalıdır.');
      expect(postLiveCoreSha, equals(preLiveCoreSha),
          reason: 'Canlı Core Next veritabanına asla yazılmamalıdır.');

      print('  [PASS] Canlı veritabanlarının sıfır mutasyon ile korunduğu kesin olarak kanıtlandı.');
    });
  });
}
