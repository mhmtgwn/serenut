import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const nutopiaSourceDb = r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db';
  const serenutSourceDb = r'C:\Users\notop\AppData\Roaming\com.example\Serenut OS\databases\serenut_pos.db';
  const erkulSourceJson = r'C:\Users\notop\AppData\Local\Temp\sandbox_erkul_source.json';

  // Güvenli Yedekleme Dizinleri
  final workspaceBackupDir = Directory(r'C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016');
  final appDataBackupDir = Directory(r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\backups\raw_tenants_20261016');

  // Yeni Mimari Üretim Veritabanları Dizini
  final coreNextDatabasesDir = Directory(r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next');

  int count(List<Map<String, Object?>> rows) => (rows.first.values.first as num).toInt();

  String calculateSha256(File file) {
    final bytes = file.readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  group('STAGE 10.10.5 — 3 İŞLETMENİN GÜVENLİ YEDEKLENMESİ VE CORE NEXT MİMARİSİNE YERLEŞTİRİLMESİ', () {
    test('ADIM 1: 3 İşletmenin Ham Verilerinin Eksiksiz Yedeklenmesi ve Checksum Doğrulaması', () async {
      if (!workspaceBackupDir.existsSync()) {
        workspaceBackupDir.createSync(recursive: true);
      }
      if (!appDataBackupDir.existsSync()) {
        appDataBackupDir.createSync(recursive: true);
      }

      print('=== 1. YEDEKLEME: NUTOPIA FINDIK DEĞİRMENİ ===');
      expect(File(nutopiaSourceDb).existsSync(), isTrue);

      // WAL Checkpoint yaparak veriyi ana veritabanı dosyasına göm
      final nutopiaConn = await openDatabase(nutopiaSourceDb, readOnly: false);
      try {
        await nutopiaConn.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {
        print('Nutopia checkpoint note: $e');
      }
      await nutopiaConn.close();

      final nutopiaBackup1 = File('${workspaceBackupDir.path}\\raw_nutopia_v60.db');
      final nutopiaBackup2 = File('${appDataBackupDir.path}\\raw_nutopia_v60.db');
      await File(nutopiaSourceDb).copy(nutopiaBackup1.path);
      await File(nutopiaSourceDb).copy(nutopiaBackup2.path);

      final nutopiaSha = calculateSha256(nutopiaBackup1);
      print('Nutopia Yedek Boyutu: ${nutopiaBackup1.lengthSync()} bayt | SHA256: $nutopiaSha');

      // Yedek veritabanının bütünlük testi
      final checkNutopiaDb = await openDatabase(nutopiaBackup1.path, readOnly: true);
      final nIntegrity = await checkNutopiaDb.rawQuery('PRAGMA integrity_check');
      expect(nIntegrity.first.values.first, equals('ok'), reason: 'Nutopia yedeği PRAGMA integrity_check geçmelidir');
      final nProdCount = count(await checkNutopiaDb.rawQuery('SELECT count(*) FROM products'));
      expect(nProdCount, equals(37682));
      await checkNutopiaDb.close();

      print('\n=== 2. YEDEKLEME: SERENUT (ŞEMA V44) ===');
      expect(File(serenutSourceDb).existsSync(), isTrue);

      final serenutConn = await openDatabase(serenutSourceDb, readOnly: false);
      try {
        await serenutConn.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {
        print('Serenut checkpoint note: $e');
      }
      await serenutConn.close();

      final serenutBackup1 = File('${workspaceBackupDir.path}\\raw_serenut_v44.db');
      final serenutBackup2 = File('${appDataBackupDir.path}\\raw_serenut_v44.db');
      await File(serenutSourceDb).copy(serenutBackup1.path);
      await File(serenutSourceDb).copy(serenutBackup2.path);

      final serenutSha = calculateSha256(serenutBackup1);
      print('Serenut Yedek Boyutu: ${serenutBackup1.lengthSync()} bayt | SHA256: $serenutSha');

      final checkSerenutDb = await openDatabase(serenutBackup1.path, readOnly: true);
      final sIntegrity = await checkSerenutDb.rawQuery('PRAGMA integrity_check');
      expect(sIntegrity.first.values.first, equals('ok'), reason: 'Serenut yedeği PRAGMA integrity_check geçmelidir');
      final sProdCount = count(await checkSerenutDb.rawQuery('SELECT count(*) FROM products'));
      expect(sProdCount, equals(6377));
      await checkSerenutDb.close();

      print('\n=== 3. YEDEKLEME: ERKUL ÇEYİZ (POSTGRESQL VPS DUMP) ===');
      expect(File(erkulSourceJson).existsSync(), isTrue);

      final erkulBackup1 = File('${workspaceBackupDir.path}\\raw_erkul_source.json');
      final erkulBackup2 = File('${appDataBackupDir.path}\\raw_erkul_source.json');
      await File(erkulSourceJson).copy(erkulBackup1.path);
      await File(erkulSourceJson).copy(erkulBackup2.path);

      final erkulSha = calculateSha256(erkulBackup1);
      print('Erkul Yedek Boyutu: ${erkulBackup1.lengthSync()} bayt | SHA256: $erkulSha');

      final erkulJson = jsonDecode(erkulBackup1.readAsStringSync()) as Map<String, dynamic>;
      expect((erkulJson['customers'] as List).length, equals(401), reason: '401 müşterinin tamamı yedeğe girmelidir');

      // Checksum manifest dosyasını kaydet
      final manifest = '''
# Serenut OS Raw Tenant Backups SHA256 Manifest
# Date: ${DateTime.now().toIso8601String()}
$nutopiaSha  raw_nutopia_v60.db
$serenutSha  raw_serenut_v44.db
$erkulSha  raw_erkul_source.json
''';
      File('${workspaceBackupDir.path}\\SHA256SUMS.txt').writeAsStringSync(manifest);
      File('${appDataBackupDir.path}\\SHA256SUMS.txt').writeAsStringSync(manifest);
      print('Yedekleme ve SHA-256 doğrulama başarıyla tamamlandı.');
    });

    test('ADIM 2 & 3: Yeni Core Next Mimarisine Göre Veritabanlarının Oluşturulması ve Verilerin Yerleştirilmesi', () async {
      if (!coreNextDatabasesDir.existsSync()) {
        coreNextDatabasesDir.createSync(recursive: true);
      }

      // ── 1. NUTOPIA FINDIK DEĞİRMENİ CORE NEXT VERİTABANI ──────────────────
      print('\n=== NUTOPIA CORE NEXT VERİTABANI OLUŞTURULUYOR ===');
      final nutopiaCorePath = '${coreNextDatabasesDir.path}\\nutopia_pos.db';
      // Varsa temiz başlat
      if (File(nutopiaCorePath).existsSync()) {
        File(nutopiaCorePath).deleteSync();
      }

      final nutopiaCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaCorePath);
      final nutopiaBridge = MigrationBridgeEngine(nutopiaCoreDb);
      final nutopiaRawDb = await openDatabase('${workspaceBackupDir.path}\\raw_nutopia_v60.db', readOnly: true);

      final nutopiaReport = await nutopiaBridge.migrateFromLegacy(nutopiaRawDb, fullScope: true);
      await nutopiaRawDb.close();

      expect(nutopiaReport.isSuccess, isTrue, reason: nutopiaReport.errorMessage);
      expect(nutopiaReport.productsMigrated, equals(37682));
      expect(nutopiaReport.customersMigrated, equals(584));

      expect(nutopiaReport.ledgerEntriesMigrated, equals(1403));

      // Nutopia veritabanı adli doğrulama
      final nTarget = nutopiaCoreDb.db;
      final nIntegrity = await nTarget.rawQuery('PRAGMA integrity_check');
      expect(nIntegrity.first.values.first, equals('ok'));

      final nFkCheck = await nTarget.rawQuery('PRAGMA foreign_key_check');
      expect(nFkCheck.isEmpty, isTrue, reason: 'Yabancı anahtar ihlali olmamalıdır: $nFkCheck');

      final nStock = (await nTarget.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products')).first['s'];
      expect(nStock, equals(5179525.85));

      final nBal = (await nTarget.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'];
      expect(nBal, equals(-13450068)); // Canlı 18:27 WAL checkpoint sonrası güncel bakiye (-134,500.68 TL)

      await nutopiaCoreDb.close();
      print('Nutopia Core Next veritabanı başarıyla yerleştirildi: $nutopiaCorePath');

      // ── 2. SERENUT CORE NEXT VERİTABANI ───────────────────────────────────
      print('\n=== SERENUT CORE NEXT VERİTABANI OLUŞTURULUYOR ===');
      final serenutCorePath = '${coreNextDatabasesDir.path}\\serenut_pos.db';
      if (File(serenutCorePath).existsSync()) {
        File(serenutCorePath).deleteSync();
      }

      final serenutCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: serenutCorePath);
      final serenutBridge = MigrationBridgeEngine(serenutCoreDb);
      final serenutRawDb = await openDatabase('${workspaceBackupDir.path}\\raw_serenut_v44.db', readOnly: true);

      final serenutReport = await serenutBridge.migrateFromLegacy(serenutRawDb, fullScope: true);
      await serenutRawDb.close();

      expect(serenutReport.isSuccess, isTrue, reason: serenutReport.errorMessage);
      expect(serenutReport.productsMigrated, equals(6377));
      expect(serenutReport.customersMigrated, equals(7));

      final sTarget = serenutCoreDb.db;
      final sIntegrity = await sTarget.rawQuery('PRAGMA integrity_check');
      expect(sIntegrity.first.values.first, equals('ok'));

      final sFkCheck = await sTarget.rawQuery('PRAGMA foreign_key_check');
      expect(sFkCheck.isEmpty, isTrue, reason: 'Yabancı anahtar ihlali olmamalıdır: $sFkCheck');

      final sStock = (await sTarget.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products')).first['s'];
      expect(sStock, equals(637445.0));

      final sBal = (await sTarget.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'];
      expect(sBal, equals(-267300));

      await serenutCoreDb.close();
      print('Serenut Core Next veritabanı başarıyla yerleştirildi: $serenutCorePath');

      // ── 3. ERKUL ÇEYİZ CORE NEXT VERİTABANI ────────────────────────────────
      print('\n=== ERKUL ÇEYİZ CORE NEXT VERİTABANI OLUŞTURULUYOR ===');
      final erkulCorePath = '${coreNextDatabasesDir.path}\\erkul_pos.db';
      if (File(erkulCorePath).existsSync()) {
        File(erkulCorePath).deleteSync();
      }

      final erkulCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulCorePath);
      final erkulBridge = MigrationBridgeEngine(erkulCoreDb);
      final erkulRawContent = File('${workspaceBackupDir.path}\\raw_erkul_source.json').readAsStringSync();
      final erkulJsonMap = jsonDecode(erkulRawContent) as Map<String, dynamic>;

      final erkulReport = await erkulBridge.migrateFromErkulJson(erkulJsonMap);
      expect(erkulReport.isSuccess, isTrue, reason: erkulReport.errorMessage);
      expect(erkulReport.customersMigrated, equals(401));

      final eTarget = erkulCoreDb.db;
      final eIntegrity = await eTarget.rawQuery('PRAGMA integrity_check');
      expect(eIntegrity.first.values.first, equals('ok'));

      final eFkCheck = await eTarget.rawQuery('PRAGMA foreign_key_check');
      expect(eFkCheck.isEmpty, isTrue, reason: 'Yabancı anahtar ihlali olmamalıdır: $eFkCheck');

      final eCustCount = count(await eTarget.rawQuery('SELECT count(*) FROM customers'));
      expect(eCustCount, equals(401));

      final eBal = (await eTarget.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'];
      expect(eBal, equals(-52362000));

      final eLedgerCount = count(await eTarget.rawQuery('SELECT count(*) FROM ledger_entries'));
      expect(eLedgerCount, equals(539));

      await erkulCoreDb.close();
      print('Erkul Çeyiz Core Next veritabanı başarıyla yerleştirildi: $erkulCorePath');

      // Son Doğrulama: 3 veritabanı dosyasının varlığı ve boyutları
      print('\n=== TÜM YENİ VERİTABANLARI GÜVENLİK KONTROLÜ ===');
      for (final name in ['nutopia_pos.db', 'serenut_pos.db', 'erkul_pos.db']) {
        final f = File('${coreNextDatabasesDir.path}\\$name');
        expect(f.existsSync(), isTrue);
        print('  $name: ${f.lengthSync()} bayt | SHA256: ${calculateSha256(f)}');
      }
    });
  });
}
