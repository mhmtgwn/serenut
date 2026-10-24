// test/core_next/stage10_12_40_backup_restore_rehearsal_test.dart
// SERENUT OS — STAGE 10.12.40
// YEDEK DOĞRULAMA, GERİ YÜKLEME PROVASI VE İŞLETME BAZLI MUTABAKAT HAZIRLIĞI TESTLERİ
//
// GÜVENLİK SINIRLARI:
// 1. Canlı veritabanlarına yazma, migration veya cutover yapılmaz.
// 2. `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` korunur.
// 3. Gerçek satış, tahsilat, iade veya stok işlemi yapılmaz.
// 4. Testler yalnızca geçici izole kopyalar üzerinde çalışır; kaynak yedek hash'leri değişmez kalır.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const expectedNutopiaSha = 'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';

  const rawSerenutPath = 'backups/raw_tenants_20261016/raw_serenut_v44.db';
  const expectedSerenutSha = '9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d';

  const rawErkulJsonPath = 'backups/raw_tenants_20261016/raw_erkul_source.json';
  const expectedErkulJsonSha = 'b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389';

  const onedriveBackupPath = r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db';
  const expectedOnedriveSha = 'da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89';

  const onedriveSnapshotCoreDir = r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next';

  group('STAGE 10.12.40 — BÖLÜM 1: GÜVENLİK KAPISI VE SABİTLER', () {
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider kesinlikle false kalmalıdır');
      expect(DatabaseManager.databaseRoutingHook, isNull, reason: 'databaseRoutingHook kesinlikle null kalmalıdır');
    });

    test('1.2: Bilinen OneDrive canlı yedeği mevcut, boyutu ve SHA-256 değeri tam eşleşmelidir', () async {
      final file = File(onedriveBackupPath);
      expect(await file.exists(), isTrue, reason: 'serenut_pos_backup_20261019_161042.db diskte mevcut olmalıdır');
      expect(await file.length(), equals(61390848), reason: 'Dosya boyutu tam 61.390.848 bayt olmalıdır');

      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      expect(hash.toLowerCase(), equals(expectedOnedriveSha.toLowerCase()), reason: 'SHA-256 tam eşleşmelidir');
    });
  });

  group('STAGE 10.12.40 — BÖLÜM 2: YEDEK ENVANTERİ VE KAYNAK DEĞİŞMEZLİĞİ', () {
    test('2.1: Nutopia, Serenut ve Erkul arşivlerinin SHA-256 değerleri doğrulanır', () async {
      final nutopiaFile = File(rawNutopiaPath);
      expect(await nutopiaFile.exists(), isTrue);
      expect(sha256.convert(await nutopiaFile.readAsBytes()).toString().toLowerCase(), equals(expectedNutopiaSha));

      final serenutFile = File(rawSerenutPath);
      expect(await serenutFile.exists(), isTrue);
      expect(sha256.convert(await serenutFile.readAsBytes()).toString().toLowerCase(), equals(expectedSerenutSha));

      final erkulFile = File(rawErkulJsonPath);
      expect(await erkulFile.exists(), isTrue);
      expect(sha256.convert(await erkulFile.readAsBytes()).toString().toLowerCase(), equals(expectedErkulJsonSha));
    });

    test('2.2: Erkul Çeyiz için Legacy .db formatında dosya olmadığını teyit eder (BLOCKED durumu tespiti)', () async {
      const erkulDbCandidate = 'backups/raw_tenants_20261016/raw_erkul_v60.db';
      expect(await File(erkulDbCandidate).exists(), isFalse,
          reason: 'Erkul Çeyiz için SQLite formatında legacy yedek mevcut değildir; kaynak yalnızca JSON formatındadır.');
    });
  });

  group('STAGE 10.12.40 — BÖLÜM 3: İZOLE GERİ YÜKLEME PROVASI', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage40_dart_rehearsal_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('3.1: Nutopia OneDrive yedeği izole hedefe kopyalanır, PRAGMA bütünlüğü ve satır sayıları doğrulanır', () async {
      final srcFile = File(onedriveBackupPath);
      final initialSha = sha256.convert(await srcFile.readAsBytes()).toString();

      final isolatedTarget = p.join(tempDir.path, 'restored_nutopia_onedrive.db');
      await srcFile.copy(isolatedTarget);

      final db = await databaseFactoryFfi.openDatabase(isolatedTarget, options: OpenDatabaseOptions(readOnly: true));

      final integrity = await db.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first.values.first, equals('ok'), reason: 'Geri yüklenen kopya integrity_check = ok olmalıdır');

      final fkCheck = await db.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck.isEmpty, isTrue, reason: 'Geri yüklenen kopyada FK ihlali olmamalıdır');

      final userVersion = (await db.rawQuery('PRAGMA user_version;')).first.values.first;
      expect(userVersion, equals(60));

      final prodCount = (await db.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(prodCount, equals(37682));

      final custCount = (await db.rawQuery('SELECT COUNT(*) as c FROM customers')).first['c'] as int;
      expect(custCount, equals(601));

      final salesCount = (await db.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(salesCount, equals(52));

      final ftCount = (await db.rawQuery('SELECT COUNT(*) as c FROM financial_transactions')).first['c'] as int;
      expect(ftCount, equals(1466));

      await db.close();

      // Kaynak yedeğin değişmezliğini doğrula
      final postSha = sha256.convert(await srcFile.readAsBytes()).toString();
      expect(postSha, equals(initialSha), reason: 'Kaynak yedeğin SHA-256 değeri provadan sonra da aynı kalmalıdır');
    });

    test('3.2: Serenut v44 yedeği izole hedefe kopyalanır, bütünlük ve satır sayıları doğrulanır', () async {
      final srcFile = File(rawSerenutPath);
      final initialSha = sha256.convert(await srcFile.readAsBytes()).toString();

      final isolatedTarget = p.join(tempDir.path, 'restored_serenut_v44.db');
      await srcFile.copy(isolatedTarget);

      final db = await databaseFactoryFfi.openDatabase(isolatedTarget, options: OpenDatabaseOptions(readOnly: true));

      final integrity = await db.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first.values.first, equals('ok'));

      final fkCheck = await db.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck.isEmpty, isTrue);

      final userVersion = (await db.rawQuery('PRAGMA user_version;')).first.values.first;
      expect(userVersion, equals(44));

      final prodCount = (await db.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(prodCount, equals(6377));

      final custCount = (await db.rawQuery('SELECT COUNT(*) as c FROM customers')).first['c'] as int;
      expect(custCount, equals(7));

      final salesCount = (await db.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(salesCount, equals(15));

      await db.close();

      final postSha = sha256.convert(await srcFile.readAsBytes()).toString();
      expect(postSha, equals(initialSha));
    });

    test('3.3: Core Next Snapshot veritabanları (Nutopia, Serenut, Erkul) izole ortamda doğrulanır', () async {
      final nutopiaCore = p.join(onedriveSnapshotCoreDir, 'nutopia_pos.db');
      final serenutCore = p.join(onedriveSnapshotCoreDir, 'serenut_pos.db');
      final erkulCore = p.join(onedriveSnapshotCoreDir, 'erkul_pos.db');

      for (final corePath in [nutopiaCore, serenutCore, erkulCore]) {
        final f = File(corePath);
        expect(await f.exists(), isTrue, reason: 'Snapshot Core Next DB mevcut olmalıdır: $corePath');

        final target = p.join(tempDir.path, p.basename(corePath));
        await f.copy(target);

        final db = await databaseFactoryFfi.openDatabase(target, options: OpenDatabaseOptions(readOnly: true));
        final integrity = await db.rawQuery('PRAGMA integrity_check;');
        expect(integrity.first.values.first, equals('ok'));

        final userVersion = (await db.rawQuery('PRAGMA user_version;')).first.values.first;
        expect(userVersion, equals(3), reason: 'Core Next şema versiyonu 3 olmalıdır');

        await db.close();
      }
    });
  });

  group('STAGE 10.12.40 — BÖLÜM 4: İŞLETME AYRIMI VE TENANT İZOLASYONU', () {
    test('4.1: Nutopia ve Serenut yedeklerinin işletme adı ve vergi numaraları teyit edilir', () async {
      // 1. Nutopia
      final nutopiaDb = await databaseFactoryFfi.openDatabase(File(rawNutopiaPath).absolute.path, options: OpenDatabaseOptions(readOnly: true));
      final nutopiaBusiness = (await nutopiaDb.query('business_profile', limit: 1)).first;
      expect(nutopiaBusiness['name'], equals('Nutopia Fındık Değirmeni'));
      expect(nutopiaBusiness['tax_number'], equals('4500498890'));
      await nutopiaDb.close();

      // 2. Serenut
      final serenutDb = await databaseFactoryFfi.openDatabase(File(rawSerenutPath).absolute.path, options: OpenDatabaseOptions(readOnly: true));
      final serenutBusiness = (await serenutDb.query('business_profile', limit: 1)).first;
      expect(serenutBusiness['name'], equals('serenut'));
      expect(serenutBusiness['tax_number'], equals('70960098324'));
      await serenutDb.close();
    });

    test('4.2: Erkul Çeyiz kaynak verisi doğrulanır ve Core Next eşleşmesi kontrol edilir', () async {
      final jsonFile = File(rawErkulJsonPath);
      final jsonContent = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;

      expect((jsonContent['customers'] as List).length, equals(401));
      expect((jsonContent['products'] as List).length, equals(26));
      expect((jsonContent['sales'] as List).length, equals(5));
      expect((jsonContent['financial_transactions'] as List).length, equals(539));

      // Core Next Erkul kontrolü
      final erkulCorePath = p.join(onedriveSnapshotCoreDir, 'erkul_pos.db');
      final db = await databaseFactoryFfi.openDatabase(erkulCorePath, options: OpenDatabaseOptions(readOnly: true));

      final custCount = (await db.rawQuery('SELECT COUNT(*) as c FROM customers')).first['c'] as int;
      expect(custCount, equals(401), reason: 'JSON customers (401) ile Core Next customers (401) tam eşleşmelidir');

      final prodCount = (await db.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(prodCount, equals(26), reason: 'JSON products (26) ile Core Next products (26) tam eşleşmelidir');

      final salesCount = (await db.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(salesCount, equals(5), reason: 'JSON sales (5) ile Core Next sales (5) tam eşleşmelidir');

      final ledgerCount = (await db.rawQuery('SELECT COUNT(*) as c FROM ledger_entries')).first['c'] as int;
      expect(ledgerCount, equals(539), reason: 'JSON financial_transactions (539) ile Core Next ledger_entries (539) tam eşleşmelidir');

      final appSettings = await db.query('app_settings');
      final settingsMap = {for (final r in appSettings) r['key'].toString(): r['value']?.toString()};
      expect(settingsMap['business_name'], contains('ERKUL'));

      await db.close();
    });
  });
}
