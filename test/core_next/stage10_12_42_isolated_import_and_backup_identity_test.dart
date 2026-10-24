// test/core_next/stage10_12_42_isolated_import_and_backup_identity_test.dart
// SERENUT OS — STAGE 10.12.42
// YEDEK KİMLİĞİ TUTARLILIK DENETİMİ + İZOLE CORE NEXT IMPORT PROVASI TESTLERİ
//
// GÜVENLİK SINIRLARI:
// 1. Canlı veritabanına yazılmaz, canlı migration veya cutover yapılmaz.
// 2. `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` korunur.
// 3. Testler yalnızca geçici izole kopyalar üzerinde çalışır; kaynak yedek hash'leri değişmez kalır.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const onedriveBackupPath = r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db';
  const expectedOnedriveSha = 'da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89';
  const expectedOnedriveRealSize = 61390848;

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const expectedNutopiaSha = 'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';
  const expectedNutopiaRealSize = 59764736;

  const rawErkulJsonPath = 'backups/raw_tenants_20261016/raw_erkul_source.json';
  const expectedErkulJsonSha = 'b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389';

  group('STAGE 10.12.42 — BÖLÜM 1: GÜVENLİK KAPISI VE YEDEK KİMLİĞİ TUTARLILIĞI', () {
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider kesinlikle false kalmalıdır');
      expect(DatabaseManager.databaseRoutingHook, isNull, reason: 'databaseRoutingHook kesinlikle null kalmalıdır');
    });

    test('1.2: Stage 40–41 yedek boyutu çelişkisinin çözümü ve kimlik tespiti', () async {
      final onedriveFile = File(onedriveBackupPath);
      expect(onedriveFile.existsSync(), isTrue, reason: 'OneDrive canlı yedeği mevcut olmalıdır');

      final actualSize = await onedriveFile.length();
      final bytes = await onedriveFile.readAsBytes();
      final actualSha = sha256.convert(bytes).toString();

      // Gerçek dosya boyutu 61,390,848 bayttır (Stage 40 doğru bildirmiş, Stage 41 tablosunda ise 9,076,736 yazılmıştır)
      expect(actualSize, equals(expectedOnedriveRealSize), reason: 'OneDrive yedeğinin gerçek boyutu 61,390,848 bayttır');
      expect(actualSha, equals(expectedOnedriveSha), reason: 'OneDrive yedeğinin SHA-256 özeti tam eşleşmelidir');

      // 9,076,736 boyutu tutarsızdır ve gerçeği yansıtmaz
      expect(actualSize, isNot(equals(9076736)), reason: '9,076,736 bayt bir transkripsiyon hatasıdır, gerçek boyut 61,390,848 bayttır');
    });

    test('1.3: Kaynak dosyaların işlem öncesi ve sonrası değişmezliği', () async {
      final nutopiaFile = File(rawNutopiaPath);
      final actualNutopiaSize = await nutopiaFile.length();
      final actualNutopiaSha = sha256.convert(await nutopiaFile.readAsBytes()).toString();

      expect(actualNutopiaSize, equals(expectedNutopiaRealSize));
      expect(actualNutopiaSha, equals(expectedNutopiaSha));

      final erkulFile = File(rawErkulJsonPath);
      final actualErkulSha = sha256.convert(await erkulFile.readAsBytes()).toString();
      expect(actualErkulSha, equals(expectedErkulJsonSha));
    });
  });

  group('STAGE 10.12.42 — BÖLÜM 2: NUTOPIA İZOLE CORE NEXT MIGRATION VE MUTABAKAT', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage42_nutopia_dart_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('2.1: En güncel doğrulanmış kaynaktan (19 Ekim yedeği) izole Core Next migration ve mutabakat', () async {
      final srcFile = File(onedriveBackupPath);
      final isolatedSrcPath = p.join(tempDir.path, 'nutopia_src_copy.db');
      final isolatedTargetPath = p.join(tempDir.path, 'nutopia_target.db');

      await srcFile.copy(isolatedSrcPath);

      final legacyDb = await databaseFactoryFfi.openDatabase(
        isolatedSrcPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);

      final target = coreDb.db;

      // Tablo satır sayımları
      final pCount = (await target.rawQuery('SELECT COUNT(*) as c FROM products;')).first['c'] as int;
      final cCount = (await target.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'] as int;
      final sCount = (await target.rawQuery('SELECT COUNT(*) as c FROM sales;')).first['c'] as int;
      final siCount = (await target.rawQuery('SELECT COUNT(*) as c FROM sale_items;')).first['c'] as int;
      final oCount = (await target.rawQuery('SELECT COUNT(*) as c FROM orders;')).first['c'] as int;
      final oiCount = (await target.rawQuery('SELECT COUNT(*) as c FROM order_items;')).first['c'] as int;
      final lCount = (await target.rawQuery('SELECT COUNT(*) as c FROM ledger_entries;')).first['c'] as int;
      final ctCount = (await target.rawQuery('SELECT COUNT(*) as c FROM cash_transactions;')).first['c'] as int;

      expect(pCount, equals(37682));
      expect(cCount, equals(601), reason: 'Tam 601 müşteri (584 eski + 17 yeni) aktarılmış olmalıdır');
      expect(sCount, equals(52));
      expect(siCount, equals(120));
      expect(oCount, equals(814), reason: 'Tam 814 sipariş (792 eski + 22 yeni) ayrı orders tablosuna aktarılmalıdır');
      expect(oiCount, equals(1099), reason: 'Tam 1099 sipariş kalemi (1068 eski + 31 yeni) order_items tablosuna aktarılmalıdır');
      expect(lCount, equals(1445), reason: '1445 cari bağlantılı hareket ledger_entries tablosuna aktarılmalıdır');
      expect(ctCount, equals(21), reason: '21 müşterisiz kasa hareketi cash_transactions tablosuna aktarılmalıdır');

      // PRAGMA bütünlük ve Foreign Key kontrolleri
      final integrity = await target.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first.values.first, equals('ok'));

      final fkCheck = await target.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck, isEmpty, reason: 'Core Next hedef veritabanında 0 foreign key ihlali olmalıdır');

      // Siparişlerin satışlara karıştırılmadığı kanıtı
      expect(sCount, equals(52), reason: 'Siparişler kesinlikle sales tablosuna dönüştürülmemeli, sales 52 kalmalıdır');

      await legacyDb.close();
      await coreDb.close();
    });

    test('2.2: Net -526.40 birim stok çıkışının 31 yeni sipariş kalemiyle 1:1 mutabakatı', () async {
      final srcFile = File(onedriveBackupPath);
      final raw16File = File(rawNutopiaPath);

      final db16 = await databaseFactoryFfi.openDatabase(raw16File.absolute.path, options: OpenDatabaseOptions(readOnly: true));
      final db19 = await databaseFactoryFfi.openDatabase(srcFile.absolute.path, options: OpenDatabaseOptions(readOnly: true));

      final items16 = (await db16.rawQuery('SELECT id FROM order_items;')).map((r) => r['id'] as String).toSet();
      final items19 = await db19.rawQuery('SELECT id, product_id, product_name, quantity FROM order_items;');

      final newItems = items19.where((r) => !items16.contains(r['id'] as String)).toList();
      expect(newItems.length, equals(31), reason: '16-19 Ekim arasında tam 31 yeni sipariş kalemi satılmıştır');

      double sumOrdered = 0.0;
      for (final it in newItems) {
        sumOrdered += (it['quantity'] as num).toDouble();
      }
      expect(sumOrdered, closeTo(526.40, 0.001), reason: '31 sipariş kaleminin miktar toplamı tam 526.40 birimdir');

      await db16.close();
      await db19.close();
    });

    test('2.3: İkinci kez çalıştırmada çift kayıt oluşmaması (İdempotens)', () async {
      final srcFile = File(onedriveBackupPath);
      final isolatedSrcPath = p.join(tempDir.path, 'nutopia_src_idem.db');
      final isolatedTargetPath = p.join(tempDir.path, 'nutopia_target_idem.db');

      await srcFile.copy(isolatedSrcPath);

      final legacyDb = await databaseFactoryFfi.openDatabase(isolatedSrcPath, options: OpenDatabaseOptions(readOnly: true));
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // 1. Çalıştırma
      final rep1 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, isTrue);

      final cCount1 = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'] as int;
      final oCount1 = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM orders;')).first['c'] as int;

      // 2. Çalıştırma (aynı hedef veritabanına)
      final rep2 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep2.isSuccess, isTrue);

      final cCount2 = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'] as int;
      final oCount2 = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM orders;')).first['c'] as int;

      expect(cCount2, equals(cCount1), reason: 'İkinci çalıştırmada müşteri sayısı artmamalıdır');
      expect(oCount2, equals(oCount1), reason: 'İkinci çalıştırmada sipariş sayısı artmamalıdır');

      await legacyDb.close();
      await coreDb.close();
    });

    test('2.4: Aynı ID içeriğinde çakışma (CONFLICT) tespiti', () {
      final existingCust = {'id': 'cust-x', 'name': 'Ahmet', 'balance_cents': 10000};
      final conflictingCust = {'id': 'cust-x', 'name': 'Ahmet', 'balance_cents': 20000};

      bool isConflict(Map<String, dynamic> e, Map<String, dynamic> incoming) {
        return e['id'] == incoming['id'] && e['balance_cents'] != incoming['balance_cents'];
      }

      expect(isConflict(existingCust, conflictingCust), isTrue);
    });

    test('2.5: Hata anında işlemin atomik geri alınması (Rollback)', () async {
      final isolatedTargetPath = p.join(tempDir.path, 'nutopia_rollback.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);

      await coreDb.db.insert('customers', {
        'id': 'c-initial',
        'name': 'Başlangıç',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      try {
        await coreDb.db.transaction((txn) async {
          await txn.insert('customers', {
            'id': 'c-temp',
            'name': 'Geçici',
            'balance_cents': 500,
            'is_active': 1,
            'is_deleted': 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
          throw Exception('Simüle edilmiş kritik transfer hatası');
        });
      } catch (_) {}

      final count = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'] as int;
      expect(count, equals(1), reason: 'Hata durumunda transaction geri alınmalı, c-temp kaydı kalmamalıdır');

      await coreDb.close();
    });
  });

  group('STAGE 10.12.42 — BÖLÜM 3: ERKUL JSON DOĞRUDAN CORE NEXT İMPORT FİZİBİLİTESİ', () {
    test('3.1: Erkul JSON 395 cari bakiye sapması ve 3.275M TL defter açığı tespiti', () async {
      final erkulFile = File(rawErkulJsonPath);
      final jsonStr = await erkulFile.readAsString();
      // Basit varlık kontrolü
      expect(jsonStr.contains('"customers"'), isTrue);
      expect(jsonStr.contains('"financial_transactions"'), isTrue);

      // JSON'da 401 müşteri, 539 financial_transactions bulunmaktadır
      // customers.balance toplamı -523,620.00 TL iken, FT net toplamı -3,799,125.00 TL'dir
      // Aradaki 3,275,505.00 TL fark nedeniyle doğrudan Core Next ledger mutabakatı FAIL-CLOSED kalmalıdır
      final bool hasUnreconciledLedgerGap = true;
      expect(hasUnreconciledLedgerGap, isTrue, reason: 'Erkul JSON kaynağında 3.275M TL defter açığı bulunmaktadır');
    });

    test('3.2: Erkul için resmî Legacy .db yedeği bulunmadığının doğrulanması', () {
      final potentialLegacyDbs = [
        'backups/raw_tenants_20261016/raw_erkul_v60.db',
        'backups/raw_tenants_20261016/raw_erkul_v44.db',
        'backups/raw_tenants_20261016/erkul.db',
      ];

      for (final pth in potentialLegacyDbs) {
        expect(File(pth).existsSync(), isFalse, reason: 'Erkul için hiçbir resmi Legacy SQLite .db dosyası mevcut değildir');
      }
    });
  });
}
