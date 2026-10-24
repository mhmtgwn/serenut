// test/services/dual_database_backup_service_test.dart
// SERENUT OS — STAGE 10.12.26
// ÇİFT VERİTABANI YEDEKLEME MOTORU VE BÜTÜNLÜK TESTLERİ

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/backup_service.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDocDir;
  MockPathProviderPlatform(this.tempDocDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDocDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDocDir;

  @override
  Future<String?> getTemporaryPath() async => tempDocDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testTempDir;
  late String legacyDbPath;
  late String coreNextDbPath;
  late String backupsDirPath;
  late BackupService backupService;

  Future<void> createValidLegacyDb() async {
    final db = await DatabaseManager.instance.getDatabase();
    await db.update('settings', {'business_name': 'Nutopia Gıda'});
    await db.insert('products', {
      'id': 'p-legacy-1',
      'name': 'Fındık İçi',
      'price': 250.0,
      'quantity': 100,
      'category': 'Kuruyemiş',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createValidCoreNextDb(String path) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 3),
    );
    await db.execute('PRAGMA user_version = 3;');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT,
        barcode TEXT,
        price_cents INTEGER,
        stock_quantity REAL
      );
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT,
        balance_cents INTEGER DEFAULT 0
      );
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        receipt_no TEXT,
        total_amount_cents INTEGER,
        created_at INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE ledger_entries (
        id TEXT PRIMARY KEY,
        customer_id TEXT,
        amount_cents INTEGER,
        entry_type TEXT,
        created_at INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE sync_events (
        id TEXT PRIMARY KEY,
        entity_name TEXT,
        operation TEXT,
        status TEXT
      );
    ''');
    await db.insert('app_settings', {
      'key': 'tenant_id',
      'value': 'tenant_serenut_001',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('products', {
      'id': 'cn-p1',
      'name': 'Core Fındık',
      'barcode': '869002',
      'price_cents': 25000,
      'stock_quantity': 50.0,
    });
    await db.close();
  }

  Future<String> calculateSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp('serenut_backup_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(testTempDir.path);
    SharedPreferences.setMockInitialValues({});

    final dbsDir = Directory(p.join(testTempDir.path, 'databases'));
    await dbsDir.create(recursive: true);

    legacyDbPath = p.join(dbsDir.path, 'serenut_pos.db');
    coreNextDbPath = p.join(dbsDir.path, 'serenut_core_v2.db');
    backupsDirPath = p.join(testTempDir.path, 'SerenutBackups');

    DatabaseManager.overrideDatabasePath = legacyDbPath;
    DatabaseManager.overrideCoreNextDatabasePath = coreNextDbPath;
    DatabaseManager.instance.reset();

    backupService = BackupService();
  });

  tearDown(() async {
    try {
      await DatabaseManager.instance.close();
    } catch (_) {}
    DatabaseManager.overrideDatabasePath = null;
    DatabaseManager.overrideCoreNextDatabasePath = null;
    DatabaseManager.instance.reset();
    try {
      if (await testTempDir.exists()) {
        await testTempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 10.12.26 — Dual Database Backup Integration Tests', () {
    test('1. Hem Legacy hem de Core Next mevcutken ikisi de atomik yedeklenir ve manifest üretilir', () async {
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath);

      final legacyShaBefore = await calculateSha256(File(legacyDbPath));
      final coreNextShaBefore = await calculateSha256(File(coreNextDbPath));

      final result = await backupService.backupDualDatabases();

      expect(result.isSuccess, isTrue);
      expect(result.legacyBackup, isNotNull);
      expect(result.coreNextBackup, isNotNull);
      expect(result.manifestPath, isNotNull);

      // Dosya varlığı kontrolleri
      final legacyBackupFile = File(result.legacyBackup!.backupPath);
      final coreNextBackupFile = File(result.coreNextBackup!.backupPath);
      final manifestFile = File(result.manifestPath!);

      expect(await legacyBackupFile.exists(), isTrue);
      expect(await coreNextBackupFile.exists(), isTrue);
      expect(await manifestFile.exists(), isTrue);

      // SHA-256 bütünlük doğrulaması
      final verifiedLegacySha = await calculateSha256(legacyBackupFile);
      final verifiedCoreNextSha = await calculateSha256(coreNextBackupFile);
      expect(result.legacyBackup!.sha256Hash, equals(verifiedLegacySha));
      expect(result.coreNextBackup!.sha256Hash, equals(verifiedCoreNextSha));

      // Manifest içeriği kontrolü
      final manifestJson = jsonDecode(await manifestFile.readAsString());
      expect(manifestJson['manifestVersion'], equals(1));
      expect(manifestJson['legacyBackup']['dbIdentifier'], equals('legacy'));
      expect(manifestJson['coreNextBackup']['dbIdentifier'], equals('core_next'));
      expect(manifestJson['atomicityLimitationNotice'], contains('Cross-database atomicity'));

      // Kaynak dosyaların test sonrası SHA-256 karşılaştırması (0 Bayt Mutasyon)
      final legacyShaAfter = await calculateSha256(File(legacyDbPath));
      final coreNextShaAfter = await calculateSha256(File(coreNextDbPath));
      expect(legacyShaAfter, equals(legacyShaBefore));
      expect(coreNextShaAfter, equals(coreNextShaBefore));
    });

    test('2. Yalnızca Legacy veritabanı mevcutken başarılı yedek oluşturulur, Core Next atlanır', () async {
      await createValidLegacyDb();
      expect(await File(coreNextDbPath).exists(), isFalse);

      final result = await backupService.backupDualDatabases(requireBoth: false);

      expect(result.isSuccess, isTrue);
      expect(result.legacyBackup, isNotNull);
      expect(result.coreNextBackup, isNull);
      expect(await File(result.legacyBackup!.backupPath).exists(), isTrue);
    });

    test('3. Yalnızca Core Next veritabanı mevcutken başarılı yedek oluşturulur, Legacy atlanır', () async {
      // Legacy dosyasını sil ve bulunamaz kıl
      DatabaseManager.overrideDatabasePath = p.join(testTempDir.path, 'non_existent.db');
      await createValidCoreNextDb(coreNextDbPath);

      final result = await backupService.backupDualDatabases(requireBoth: false);

      expect(result.isSuccess, isTrue);
      expect(result.coreNextBackup, isNotNull);
      expect(result.legacyBackup, isNull);
      expect(await File(result.coreNextBackup!.backupPath).exists(), isTrue);
    });

    test('4. Hiçbir veritabanı bulunamadığında fail-closed olur ve hata raporlar', () async {
      DatabaseManager.overrideDatabasePath = p.join(testTempDir.path, 'missing_legacy.db');
      DatabaseManager.overrideCoreNextDatabasePath = p.join(testTempDir.path, 'missing_core.db');

      final result = await backupService.backupDualDatabases();

      expect(result.isSuccess, isFalse);
      expect(result.failedStep, equals('presence_check'));
      expect(result.errorMessage, contains('bulunamadı'));
    });

    test('5. requireBoth = true olduğunda veritabanlarından biri eksikse fail-closed olur', () async {
      await createValidLegacyDb();
      expect(await File(coreNextDbPath).exists(), isFalse);

      final result = await backupService.backupDualDatabases(requireBoth: true);

      expect(result.isSuccess, isFalse);
      expect(result.failedStep, equals('presence_check'));
      expect(result.errorMessage, contains('Her iki veritabanı yedeği zorunlu kılındı'));
    });

    test('6. Bozuk SQLite dosyası tespit edildiğinde yedekleme durdurulur ve geçici dosya temizlenir', () async {
      await createValidLegacyDb();
      // Core Next dosyasını 100 baytlık çöp veriyle oluştur
      final corruptCoreFile = File(coreNextDbPath);
      await corruptCoreFile.writeAsBytes(List.filled(100, 42));

      final result = await backupService.backupDualDatabases();

      expect(result.isSuccess, isFalse);
      expect(result.failedDatabase, equals('core_next'));

      // Geriye hiçbir .tmp kalmadığını doğrula
      final backupsDir = Directory(backupsDirPath);
      if (await backupsDir.exists()) {
        final tmpFiles = backupsDir.listSync().where((f) => f.path.endsWith('.tmp'));
        expect(tmpFiles, isEmpty);
      }
    });

    test('7. Kısmi başarısızlıkta (Legacy OK, Core Next Bozuk) fail-closed olur ve artık dosya bırakmaz', () async {
      await createValidLegacyDb();
      // Core Next dosyasını bozuk olarak oluştur
      final corruptCoreFile = File(coreNextDbPath);
      await corruptCoreFile.writeAsBytes(List.filled(100, 99));

      final result = await backupService.backupDualDatabases();

      expect(result.isSuccess, isFalse);
      expect(result.failedDatabase, equals('core_next'));

      // Geçici .tmp dosyalarının silindiğini doğrula
      final backupsDir = Directory(backupsDirPath);
      if (await backupsDir.exists()) {
        final tmpFiles = backupsDir.listSync().where((f) => f.path.endsWith('.tmp'));
        expect(tmpFiles, isEmpty);
      }
    });

    test('8. backupDatabase() geriye dönük uyumlu çalışır ve geçerli bir dosya yolu döner', () async {
      await createValidLegacyDb();

      final returnedPath = await backupService.backupDatabase();
      expect(returnedPath, isNotEmpty);
      expect(await File(returnedPath).exists(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_backup_date'), isNotNull);
    });

    test('9. getBackupFiles() hem Legacy hem Core Next yedeklerini tarihe göre sıralı listeler', () async {
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath);

      final result = await backupService.backupDualDatabases();
      expect(result.isSuccess, isTrue);

      final files = await backupService.getBackupFiles();
      expect(files.length, greaterThanOrEqualTo(2));
      final names = files.map((f) => p.basename(f.path)).toList();
      expect(names.any((n) => n.startsWith('serenut_pos_backup_')), isTrue);
      expect(names.any((n) => n.startsWith('serenut_core_v2_backup_')), isTrue);
    });

    test('10. restoreDatabase() şemayı algılar ve doğru hedef veritabanına geri yükler', () async {
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath);

      final backupResult = await backupService.backupDualDatabases();
      expect(backupResult.isSuccess, isTrue);

      final legacyBackupPath = backupResult.legacyBackup!.backupPath;
      final coreNextBackupPath = backupResult.coreNextBackup!.backupPath;

      // 1. Legacy veritabanını kapat ve sil
      await DatabaseManager.instance.close();
      await File(legacyDbPath).delete();
      expect(await File(legacyDbPath).exists(), isFalse);

      // Legacy yedeğini geri yükle
      final restoredLegacy = await backupService.restoreDatabase(legacyBackupPath);
      expect(restoredLegacy, isTrue);
      expect(await File(legacyDbPath).exists(), isTrue);

      // Geri yüklenen veriyi doğrula
      final restoredLegacyDb = await DatabaseManager.instance.getDatabase();
      final settings = await restoredLegacyDb.query('settings');
      expect(settings.first['business_name'], equals('Nutopia Gıda'));

      // 2. Core Next veritabanını sil
      await File(coreNextDbPath).delete();
      expect(await File(coreNextDbPath).exists(), isFalse);

      // Core Next yedeğini geri yükle
      final restoredCoreNext = await backupService.restoreDatabase(coreNextBackupPath);
      expect(restoredCoreNext, isTrue);
      expect(await File(coreNextDbPath).exists(), isTrue);

      // Geri yüklenen Core Next verisini doğrula
      final restoredCoreDb = await databaseFactory.openDatabase(coreNextDbPath);
      final appSettings = await restoredCoreDb.query('app_settings');
      expect(appSettings.first['value'], equals('tenant_serenut_001'));
      await restoredCoreDb.close();
    });
  });
}
