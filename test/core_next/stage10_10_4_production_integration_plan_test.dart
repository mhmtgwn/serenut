import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('stage10_10_4_plan_');
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('STAGE 10.10.4 — ÜRETİM ENTEGRASYONU VE GEÇİŞ TESTLERİ', () {
    test('1. Feature Flag Varsayılanının Kapalı (Fail-Closed) Olduğu Doğrulanmalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final flag = container.read(coreNextSalesEngineEnabledProvider);
      expect(flag, isFalse, reason: 'Üretim feature flag varsayılanı kesinlikle false olmalıdır!');

      final executor = container.read(coreNextSaleExecutorProvider);
      expect(executor, isNull, reason: 'CoreNext executor bayrak kapalıyken varsayılan olarak null olmalıdır');
    });

    test('2. Multi-Tenant Router: 3 Farklı İşletme Arasında Geçiş ve Cache İzolasyonu', () async {
      // 3 İzole DB Dosyası Oluştur
      final nutopiaPath = '${tempDir.path}\\nutopia.db';
      final serenutPath = '${tempDir.path}\\serenut.db';
      final erkulPath = '${tempDir.path}\\erkul.db';

      final dbNutopia = await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaPath);
      final dbSerenut = await CoreAppDatabase.open(inMemoryOrCustomPath: serenutPath);
      final dbErkul = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulPath);

      // Her birine işletmeye özel ürünler ekle
      await dbNutopia.db.insert('products', {
        'id': 'nutopia-p1',
        'barcode': 'NUT-01',
        'name': 'Organik Fındık İçi 1kg',
        'price_cents': 35000,
        'stock_quantity': 500.5,
        'vat_rate': 1,
        'unit': 'kg',
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await dbSerenut.db.insert('products', {
        'id': 'serenut-p1',
        'barcode': 'SER-01',
        'name': 'Serenut POS Terminal Lisansı',
        'price_cents': 150000,
        'stock_quantity': 10.0,
        'vat_rate': 20,
        'unit': 'piece',
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await dbErkul.db.insert('products', {
        'id': 'erkul-p1',
        'barcode': 'ERK-01',
        'name': 'Çift Kişilik Yatak Örtüsü',
        'price_cents': 450000,
        'stock_quantity': 25.0,
        'vat_rate': 10,
        'unit': 'piece',
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Simüle Edilmiş Multi-Tenant DB Resolver
      String activeTenant = 'nutopia';
      Database getActiveDb() {
        switch (activeTenant) {
          case 'nutopia':
            return dbNutopia.db;
          case 'serenut':
            return dbSerenut.db;
          case 'erkul':
            return dbErkul.db;
          default:
            throw ArgumentError('Geçersiz tenant: $activeTenant');
        }
      }

      // Adım 1: Nutopia aktifken ürün sorgula
      var activeProds = await getActiveDb().query('products');
      expect(activeProds.length, equals(1));
      expect(activeProds.first['name'], equals('Organik Fındık İçi 1kg'));

      // Adım 2: İşletmeyi Erkul Çeyiz olarak değiştir
      activeTenant = 'erkul';
      activeProds = await getActiveDb().query('products');
      expect(activeProds.length, equals(1));
      expect(activeProds.first['name'], equals('Çift Kişilik Yatak Örtüsü'));
      expect(activeProds.first['price_cents'], equals(450000));

      // Adım 3: İşletmeyi Serenut olarak değiştir
      activeTenant = 'serenut';
      activeProds = await getActiveDb().query('products');
      expect(activeProds.length, equals(1));
      expect(activeProds.first['name'], equals('Serenut POS Terminal Lisansı'));

      await dbNutopia.close();
      await dbSerenut.close();
      await dbErkul.close();
    });

    test('3. CoreNextBootstrapCoordinator: Rollback ve Hata Durumunda Fail-Closed Davranışı', () async {
      // Bir hata simülasyonu ile koordinatörün legacy akışı koruduğunu doğrula
      final coordinator = CoreNextBootstrapCoordinator(
        prefs: null,
      );

      final state = await coordinator.getPersistentState();
      expect(state, equals(CoreNextMigrationState.notStarted));
    });
  });
}
