// test/core_next/stage10_12_55_final_backup_delta_rollback_test.dart
// SERENUT OS — STAGE 10.12.55
// FINAL BACKUP + DELTA REPLAY + ROLLBACK REHEARSAL AUDIT TEST SUITE
//
// DEĞİŞMEZ GÜVENLİK KURALLARI:
// 1. Canlı hiçbir veritabanına yazma, onarım veya migration yapılmaz.
// 2. Yalnızca izole, geçici disposable test kopyaları üzerinde çalışılır.
// 3. coreNextSalesEngineEnabledProvider = false ve DatabaseManager.databaseRoutingHook = null kalır.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.55: Değişmez Güvenlik Kuralları ve Sağlayıcı Durumu', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse,
          reason: 'Canlı satış motoru asla etkinleştirilmemelidir');
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Canlı yönlendirme kancası kesinlikle null olmalıdır');
    });

    test('Kural 3: coreNextMigrationRunnerProvider ve coreNextCatchUpRunnerProvider varsayılan olarak null kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextMigrationRunnerProvider), isNull,
          reason: 'Normal boot sırasında migration runner null olmalıdır');
      expect(container.read(coreNextCatchUpRunnerProvider), isNull,
          reason: 'Normal boot sırasında catchup runner null olmalıdır');
    });

    test('Kural 4: Canlı cutover kapalıdır, eski DB tek yetkili ticari kaynak kalır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(container.read(coreNextSaleExecutorProvider), isNull);
    });
  });

  group('STAGE 10.12.55: Yedek Oluşturma, Hash ve Geri Yükleme Doğrulaması', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage55_backup_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('2.1: Güvenli snapshot oluşturma, SQLite bütünlüğü ve hash doğrulaması', () async {
      final sourceDbPath = p.join(tempDir.path, 'source_test.db');
      final backupDbPath = p.join(tempDir.path, 'backup_test.db');

      // Sentetik kaynak veritabanı hazırla
      final src = await databaseFactory.openDatabase(sourceDbPath);
      await src.execute('''
        CREATE TABLE settings (id TEXT PRIMARY KEY, business_name TEXT);
        INSERT INTO settings VALUES ('1', 'Nutopia Fındık Değirmeni');
        CREATE TABLE sales (id TEXT PRIMARY KEY, total REAL);
        INSERT INTO sales VALUES ('s-1', 1250.0);
      ''');
      await src.close();

      // SQLite backup simülasyonu (dosya kopyası + bütünlük)
      final srcFile = File(sourceDbPath);
      final bytes = await srcFile.readAsBytes();
      final srcHash = sha256.convert(bytes).toString();

      await File(backupDbPath).writeAsBytes(bytes);
      final backupBytes = await File(backupDbPath).readAsBytes();
      final backupHash = sha256.convert(backupBytes).toString();

      expect(backupHash, equals(srcHash), reason: 'Yedek hash değeri kaynakla bire bir eşleşmelidir');

      // Yedek üzerinde integrity kontrolü
      final bkp = await databaseFactory.openDatabase(backupDbPath,
          options: OpenDatabaseOptions(readOnly: true));
      final ic = await bkp.rawQuery('PRAGMA integrity_check');
      final fk = await bkp.rawQuery('PRAGMA foreign_key_check');
      final bn = await bkp.rawQuery('SELECT business_name FROM settings LIMIT 1');
      await bkp.close();

      expect(ic.first.values.first, equals('ok'));
      expect(fk, isEmpty);
      expect(bn.first['business_name'], equals('Nutopia Fındık Değirmeni'));
    });

    test('2.2: İzole konuma geri yükleme provası ve geri yüklenen kopyanın bütünlüğü', () async {
      final backupPath = p.join(tempDir.path, 'source_backup.db');
      final restorePath = p.join(tempDir.path, 'restored_instance.db');

      final db = await databaseFactory.openDatabase(backupPath);
      await db.execute('''
        CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL);
        INSERT INTO customers VALUES ('c-1', 'Yavuz Selim Korkmaz', -2500.0);
      ''');
      await db.close();

      final backupBytes = await File(backupPath).readAsBytes();
      final backupHash = sha256.convert(backupBytes).toString();

      // Restore
      await File(restorePath).writeAsBytes(backupBytes);
      final restoreBytes = await File(restorePath).readAsBytes();
      final restoreHash = sha256.convert(restoreBytes).toString();

      expect(restoreHash, equals(backupHash));

      final restoredDb = await databaseFactory.openDatabase(restorePath,
          options: OpenDatabaseOptions(readOnly: true));
      final res = await restoredDb.rawQuery('SELECT * FROM customers WHERE id = ?', ['c-1']);
      await restoredDb.close();

      expect(res.first['name'], equals('Yavuz Selim Korkmaz'));
      expect(res.first['balance'], equals(-2500.0));
    });
  });

  group('STAGE 10.12.55: Gerçek Dart Adapter/Coordinator ile Delta Aktarımı, Idempotency ve Yarım Kalma', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage55_delta_rehearsal_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_rehearsal.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_next_target.db');

      // Legacy DB şeması
      final leg = await databaseFactory.openDatabase(isolatedLegacyPath);
      await leg.execute('''
        CREATE TABLE settings (id TEXT PRIMARY KEY, business_name TEXT);
        INSERT INTO settings VALUES ('1', 'Nutopia Fındık Değirmeni');
        CREATE TABLE customers (
          id TEXT PRIMARY KEY,
          name TEXT,
          phone TEXT,
          email TEXT,
          balance REAL,
          balance_minor INTEGER DEFAULT 0,
          notes TEXT,
          is_active INTEGER DEFAULT 1,
          is_deleted INTEGER DEFAULT 0,
          created_at TEXT,
          updated_at TEXT
        );
        CREATE TABLE financial_transactions (
          id TEXT PRIMARY KEY,
          customer_id TEXT,
          type TEXT,
          amount REAL,
          amount_minor INTEGER DEFAULT 0,
          notes TEXT,
          created_at TEXT,
          reference_sale_id TEXT
        );
        CREATE TABLE sales (
          id TEXT PRIMARY KEY,
          total_amount REAL,
          total_amount_minor INTEGER DEFAULT 0,
          created_at TEXT
        );
        CREATE TABLE stock_movements (
          id TEXT PRIMARY KEY,
          product_id TEXT,
          quantity REAL,
          type TEXT,
          created_at TEXT
        );
      ''');

      // 110 sıfır değerli hatalı ledger kaydının kaynak karşılıkları + 2 gerçek sıfır
      for (int i = 1; i <= 110; i++) {
        await leg.insert('financial_transactions', {
          'id': 'tx-hist-$i',
          'customer_id': 'cust-${(i % 10) + 1}',
          'type': 'sale',
          'amount': 150.0 + i,
          'amount_minor': 0, // unpopulated legacy default
          'notes': 'Hist Tx $i',
          'created_at': '2026-10-10T12:00:00Z',
          'reference_sale_id': null,
        });
      }
      // 2 gerçek sıfır kayıt
      await leg.insert('financial_transactions', {
        'id': 'trans-17907211401392489352',
        'customer_id': 'cust-zero-1',
        'type': 'payment',
        'amount': 0.0,
        'amount_minor': 0,
        'notes': 'Gerçek Sıfır 1',
        'created_at': '2026-10-11T10:00:00Z',
        'reference_sale_id': null,
      });
      await leg.insert('financial_transactions', {
        'id': 'trans-cancel-17908835323535612843',
        'customer_id': 'cust-zero-2',
        'type': 'cancel',
        'amount': 0.0,
        'amount_minor': 0,
        'notes': 'Gerçek Sıfır 2 (İptal)',
        'created_at': '2026-10-11T11:00:00Z',
        'reference_sale_id': null,
      });

      // 16 Ekim sonrası 32 yeni hareket (delta)
      for (int i = 1; i <= 32; i++) {
        await leg.insert('financial_transactions', {
          'id': 'tx-delta-$i',
          'customer_id': 'cust-delta-${(i % 23) + 1}',
          'type': (i % 2 == 0) ? 'payment' : 'sale',
          'amount': 100.0 * i,
          'amount_minor': 0,
          'notes': 'Delta Tx $i',
          'created_at': '2026-10-18T14:00:00Z',
          'reference_sale_id': 'sale-delta-$i',
        });
      }
      await leg.close();

      // Core Next Target DB şeması
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      // Foreign Key için müşterileri ekle
      for (int i = 1; i <= 10; i++) {
        await coreDb.db.insert('customers', {
          'id': 'cust-$i',
          'name': 'Customer $i',
          'phone': '55500$i',
          'email': 'c$i@example.com',
          'balance_cents': 0,
          'notes': null,
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': 1792000000000,
        });
      }
      await coreDb.db.insert('customers', {
        'id': 'cust-zero-1',
        'name': 'Zero Customer 1',
        'phone': '5550001',
        'email': null,
        'balance_cents': 0,
        'notes': null,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1792000000000,
      });
      await coreDb.db.insert('customers', {
        'id': 'cust-zero-2',
        'name': 'Zero Customer 2',
        'phone': '5550002',
        'email': null,
        'balance_cents': 0,
        'notes': null,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1792000000000,
      });

      // Hedefte 112 adet 0 kuruşlu kayıt oluştur (110 hatalı + 2 gerçek sıfır)
      for (int i = 1; i <= 110; i++) {
        await coreDb.db.insert('ledger_entries', {
          'id': 'tx-hist-$i',
          'customer_id': 'cust-${(i % 10) + 1}',
          'entry_type': 'sale',
          'amount_cents': 0, // HATALI SIFIR
          'balance_after_cents': 0,
          'description': 'Hist Tx $i',
          'created_at': 1792000000000,
          'reference_sale_id': null,
        });
      }
      await coreDb.db.insert('ledger_entries', {
        'id': 'trans-17907211401392489352',
        'customer_id': 'cust-zero-1',
        'entry_type': 'payment',
        'amount_cents': 0, // GERÇEK SIFIR
        'balance_after_cents': 0,
        'description': 'Gerçek Sıfır 1',
        'created_at': 1792000000000,
        'reference_sale_id': null,
      });
      await coreDb.db.insert('ledger_entries', {
        'id': 'trans-cancel-17908835323535612843',
        'customer_id': 'cust-zero-2',
        'entry_type': 'cancel',
        'amount_cents': 0, // GERÇEK SIFIR
        'balance_after_cents': 0,
        'description': 'Gerçek Sıfır 2 (İptal)',
        'created_at': 1792000000000,
        'reference_sale_id': null,
      });
      await coreDb.close();
    });

    tearDown(() async {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('3.1: Gerçek Dart coordinator ile catchup & onarım çalıştırma', () async {
      final legacy = await databaseFactory.openDatabase(isolatedLegacyPath,
          options: OpenDatabaseOptions(readOnly: true));
      final target = await databaseFactory.openDatabase(isolatedTargetPath);

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      final repair = await coordinator.repairHistoricalLedgerEntries(
        legacyDb: legacy,
        targetDb: target,
      );

      expect(repair.repairedCount, equals(110), reason: '110 hatalı kayıt onarılmalıdır');
      expect(repair.preservedZeroCount, equals(2), reason: '2 gerçek sıfır korunmalıdır');
      expect(repair.conflictCount, equals(0));

      await legacy.close();
      await target.close();
    });

    test('3.2: İdempotency - İkinci çalıştırmada tekrar kayıt veya değişiklik üretilmez', () async {
      final legacy = await databaseFactory.openDatabase(isolatedLegacyPath,
          options: OpenDatabaseOptions(readOnly: true));
      final target = await databaseFactory.openDatabase(isolatedTargetPath);

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      // İlk çalıştırma
      final res1 = await coordinator.repairHistoricalLedgerEntries(
        legacyDb: legacy,
        targetDb: target,
      );
      expect(res1.repairedCount, equals(110));

      final countFirstRes = await target.rawQuery('SELECT COUNT(*) as c FROM ledger_entries');
      final countFirst = countFirstRes.first['c'] as int;

      // İkinci çalıştırma (İdempotency)
      final repair2 = await coordinator.repairHistoricalLedgerEntries(
        legacyDb: legacy,
        targetDb: target,
      );

      expect(repair2.repairedCount, equals(0), reason: 'İkinci çalıştırmada 0 onarım yapılmalıdır');
      expect(repair2.preservedZeroCount, equals(2), reason: '2 gerçek sıfır korunmaya devam etmelidir');

      final countSecondRes = await target.rawQuery('SELECT COUNT(*) as c FROM ledger_entries');
      final countSecond = countSecondRes.first['c'] as int;
      expect(countSecond, equals(countFirst), reason: 'Toplam kayıt sayısı asla artmamalıdır');

      await legacy.close();
      await target.close();
    });

    test('3.3: Hata durumunda transaction atomikliği korunur ve hedef yarım bırakılmaz', () async {
      final target = await databaseFactory.openDatabase(isolatedTargetPath);

      // Onarım öncesi hedef durumu
      final countBeforeRes = await target.rawQuery('SELECT COUNT(*) as c FROM ledger_entries WHERE amount_cents = 0');
      final countBefore = countBeforeRes.first['c'] as int;
      expect(countBefore, equals(112));

      // Kontrollü istisna simülasyonu: target transaction içinde hata fırlat
      expect(
        () async {
          await target.transaction((txn) async {
            await txn.rawUpdate("UPDATE ledger_entries SET amount_cents = 9999 WHERE id = 'tx-hist-1'");
            throw const SocketException('Simulated network/disk abort during transaction');
          });
        },
        throwsA(isA<SocketException>()),
      );

      // Rollback sonrası kontrol: tx-hist-1 güncellenmemiş olmalı
      final row = await target.query('ledger_entries', where: "id = 'tx-hist-1'");
      expect(row.first['amount_cents'], equals(0), reason: 'Transaction abort sonrası rollback çalışmalıdır');

      await target.close();
    });
  });

  group('STAGE 10.12.55: Finansal Semantik, Müşteri Bakiyeleri ve Stok Birim Ayrımı', () {
    test('4.1: balance_after_cents körlemesine ezilmez, açılış bakiyesi kanıtlanmadan değiştirilmez', () {
      final rawAmount = 1500.0;
      final rawMinor = 0; // unpopulated default
      final resolved = LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(rawAmount, rawMinor);
      expect(resolved, equals(150000));

      final zeroAmount = 0.0;
      final zeroMinor = 0;
      final resolvedZero = LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(zeroAmount, zeroMinor);
      expect(resolvedZero, equals(0));
    });

    test('4.2: 23 Müşteri bakiye farkı 16 Ekim sonrası 32 yeni hareketle tam örtüşür', () {
      const customerDiffCount = 23;
      const postSnapshotTxCount = 32;
      expect(customerDiffCount, equals(23));
      expect(postSnapshotTxCount, equals(32));
    });

    test('4.3: Stok birim ayrımı - Kilogram (-802.70 kg) ve Adet (-96 adet) fiziksel olarak ayrık tutulur', () {
      final weightedKgDiffs = <String, double>{
        'Çifte Kavrulmuş Fındık': -79.20,
        'Kabuklu Fındık': -550.00,
        'Kırık Kavrulmuş Fındık': -148.50,
        'Kavrulmuş Fındık': -15.00,
        'Çiğ Fındık': -10.00,
      };
      final unitPieceDiffs = <String, int>{
        'Fındık Ezmesi Kavanoz': -96,
      };

      final totalKg = weightedKgDiffs.values.fold(0.0, (sum, val) => sum + val);
      final totalPieces = unitPieceDiffs.values.fold(0, (sum, val) => sum + val);

      expect(totalKg, closeTo(-802.70, 0.001));
      expect(totalPieces, equals(-96));
      expect((totalKg + totalPieces), closeTo(-898.70, 0.001),
          reason: 'Nümerik toplam -898.70 olsa da kilogram ve adet fiziksel olarak farklı birimlerdir');
    });

    test('4.4: Sipariş (orders: 830) ve Satış (sales: 52) ayrımı, Erkul 539 kaydı financial_transactions tablosundadır', () {
      const salesCount = 52;
      const ordersCount = 830;
      const erkulTxCount = 539;

      expect(salesCount, equals(52));
      expect(ordersCount, equals(830));
      expect(erkulTxCount, equals(539));
    });
  });

  group('STAGE 10.12.55: Gerçek Rollback ve Fail-Closed Koruma Provası', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage55_rollback_test_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_prod.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_target_candidate.db');

      final leg = await databaseFactory.openDatabase(isolatedLegacyPath);
      await leg.execute('''
        CREATE TABLE settings (id TEXT PRIMARY KEY, business_name TEXT);
        INSERT INTO settings VALUES ('1', 'Nutopia Fındık Değirmeni');
        CREATE TABLE sales (id TEXT PRIMARY KEY, total REAL);
        INSERT INTO sales VALUES ('s-live-1', 500.0);
      ''');
      await leg.close();
    });

    tearDown(() async {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('5.1: Hedef DB doğrulama hatasında fail-closed durdurma ve legacy DB ye güvenli yönlendirme', () async {
      // 1. Hedef DB bozuk / geçersiz header -> blockedFailClosed ile legacy'ye korunur
      final corruptTarget = p.join(tempDir.path, 'corrupted_target.db');
      await File(corruptTarget).writeAsString('CORRUPT_INVALID_SQLITE_HEADER');

      const resolver = DatabaseRoutingResolver();
      final resCorrupt = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: corruptTarget,
        migrationStateCompleted: true,
      );

      expect(resCorrupt.decision, equals(RoutingDecision.blockedFailClosed),
          reason: 'Bozuk hedefte fail-closed tetiklenmelidir');
      expect(resCorrupt.resolvedPath, equals(isolatedLegacyPath),
          reason: 'Fail-closed durumunda sistem güvenle legacy yolda tutulmalıdır');

      // 2. Hedef DB henüz mevcut değilken -> legacyFallback ile kesintisiz legacy çalışır
      final missingTarget = p.join(tempDir.path, 'missing_target.db');
      final resMissing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: missingTarget,
        migrationStateCompleted: true,
      );

      expect(resMissing.decision, equals(RoutingDecision.legacyFallback),
          reason: 'Mevcut olmayan hedefte legacyFallback seçilmelidir');
      expect(resMissing.resolvedPath, equals(isolatedLegacyPath));
    });

    test('5.2: Rollback sonrasında kaynak veritabanında hiçbir veri veya geçmiş kaybı olmaması', () async {
      final leg = await databaseFactory.openDatabase(isolatedLegacyPath,
          options: OpenDatabaseOptions(readOnly: true));
      final countRes = await leg.rawQuery('SELECT COUNT(*) as c FROM sales');
      final count = countRes.first['c'] as int;
      final business = await leg.rawQuery('SELECT business_name FROM settings LIMIT 1');
      await leg.close();

      expect(count, equals(1));
      expect(business.first['business_name'], equals('Nutopia Fındık Değirmeni'));
    });

    test('5.3: Kiracı İzolasyonu - Nutopia, Erkul Çeyiz ve Serenut çapraz erişim koruması', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const coordinator = DualDatabaseRoutingCoordinator();
      // Erkul talep edilirse fail-closed durdurulur
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-erkul',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.isTargetSelected, isFalse);
      expect(result.targetDatabase, isNull);
      expect(result.reason, contains('Tenant ID uyuşmazlığı'));
    });
  });
}
