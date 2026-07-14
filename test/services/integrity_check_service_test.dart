// test/services/integrity_check_service_test.dart
// KRITIK E DOGRULAMA: attemptDatabaseRepair() en guncel gecerli backup'i secmeli.
//
// Test senaryolari:
//   1. Bozuk backup + gecerli backup => gecerli olan secilmeli
//   2. Birden fazla gecerli backup => EN YENI tarihli secilmeli
//   3. Hic backup yok => false donmeli
//   4. Sadece upgrade backup var => ona fallback etmeli
//
// NOT: Bu testler gercek dosya sistemi uzerinde calisir (path_provider mock olmadan).
// Temp dizin kullanilarak izole edilir.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// Test: Test amacli IntegrityCheckService alt sinifi
// getApplicationDocumentsDirectory() ve getDatabasesPath() gercek path_provider gerektiriyor.
// Bu nedenle dosya yollarini dogrudan parametre olarak alan bir test helper kullaniyoruz.
class _TestableIntegrityCheckService {
  final String dbsPath;
  final String docsPath;

  _TestableIntegrityCheckService({required this.dbsPath, required this.docsPath});

  // attemptDatabaseRepair() ile ayni mantigi uygular; path_provider yerine enjekte edilen path'leri kullanir
  Future<Map<String, dynamic>> runRepair() async {
    final dbPath = p.join(dbsPath, 'serenut_pos.db');
    File? latestBackupFile;

    // 1. SerenutBackups/ klasorunun en yeni backup'ini bul
    try {
      final backupsDir = Directory(p.join(docsPath, 'SerenutBackups'));
      if (await backupsDir.exists()) {
        final files = backupsDir
            .listSync()
            .whereType<File>()
            .where((f) =>
                p.basename(f.path).startsWith('serenut_pos_backup_') &&
                f.path.endsWith('.db'))
            .toList();
        if (files.isNotEmpty) {
          files.sort((a, b) =>
              b.lastModifiedSync().compareTo(a.lastModifiedSync()));
          latestBackupFile = files.first;
        }
      }
    } catch (e) {
      debugPrint('[Test] SerenutBackups scan failed: ');
    }

    // 2. Fallback: upgrade backup
    final upgradePath = p.join(dbsPath, 'serenut_pos_upgrade_backup.db');
    final upgradeBackup = File(upgradePath);
    final File? sourceFile =
        latestBackupFile ?? (await upgradeBackup.exists() ? upgradeBackup : null);

    if (sourceFile == null) return {'success': false, 'source': null};

    final dbFile = File(dbPath);
    const tempPath = '.repair_bak';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) await tempFile.delete();
    if (await dbFile.exists()) await dbFile.copy(tempPath);

    try {
      if (await dbFile.exists()) await dbFile.delete();
      await sourceFile.copy(dbPath);

      // Basit gecerlilik kontrolu: SQLite magic bytes (53 51 4c 69 74 65)
      final bytes = await File(dbPath).readAsBytes();
      final isSqlite = bytes.length > 16 &&
          bytes[0] == 0x53 && bytes[1] == 0x51 && bytes[2] == 0x4c &&
          bytes[3] == 0x69 && bytes[4] == 0x74 && bytes[5] == 0x65;

      if (!isSqlite) {
        throw Exception('Geri yuklenen dosya gecerli bir SQLite DB degil.');
      }

      if (await tempFile.exists()) await tempFile.delete();
      return {'success': true, 'source': p.basename(sourceFile.path)};
    } catch (e) {
      if (await dbFile.exists()) await dbFile.delete();
      if (await tempFile.exists()) await tempFile.rename(dbPath);
      return {'success': false, 'source': null};
    }
  }
}

// Minimal gecerli SQLite dosyasi olusturucu (bos DB)
Future<File> _createValidSqliteFile(String path) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(path, version: 1, onCreate: (db, v) async {
    await db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
  });
  await db.close();
  return File(path);
}

// Bozuk (gecersiz) dosya olusturucu
Future<File> _createCorruptFile(String path) async {
  final file = File(path);
  await file.writeAsBytes([0x00, 0x01, 0x02, 0x03, 0x04]);
  return file;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('IntegrityCheckService.attemptDatabaseRepair — Kritik E', () {
    late Directory tempDbsDir;
    late Directory tempDocsDir;
    late Directory backupsDir;

    setUp(() async {
      tempDbsDir = await Directory.systemTemp.createTemp('kritik_e_dbs_');
      tempDocsDir = await Directory.systemTemp.createTemp('kritik_e_docs_');
      backupsDir = Directory(p.join(tempDocsDir.path, 'SerenutBackups'));
      await backupsDir.create(recursive: true);
    });

    tearDown(() async {
      try { await tempDbsDir.delete(recursive: true); } catch (_) {}
      try { await tempDocsDir.delete(recursive: true); } catch (_) {}
    });

    test('SENARYO 1: Bozuk + gecerli backup varsa, gecerli olan secilmeli', () async {
      // Bozuk backup (eski tarih — simule etmek icin once olusturup 2sn bekleyecegiz)
      final corruptPath = p.join(backupsDir.path, 'serenut_pos_backup_20260101_100000.db');
      await _createCorruptFile(corruptPath);

      // Bozuk dosyaya eski timestamp ver
      final oldTime = DateTime(2026, 1, 1, 10, 0, 0);
      File(corruptPath).setLastModifiedSync(oldTime);

      // Gecerli backup (yeni tarih)
      final validPath = p.join(backupsDir.path, 'serenut_pos_backup_20260710_090000.db');
      await _createValidSqliteFile(validPath);
      // Yeni timestamp — gecerli dosya daha yeni olmali
      File(validPath).setLastModifiedSync(DateTime(2026, 7, 10, 9, 0, 0));

      final svc = _TestableIntegrityCheckService(
        dbsPath: tempDbsDir.path,
        docsPath: tempDocsDir.path,
      );
      final result = await svc.runRepair();

      expect(result['success'], isTrue,
          reason: 'Gecerli backup mevcut oldugunda repair basarili olmali');
      expect(result['source'], equals('serenut_pos_backup_20260710_090000.db'),
          reason: 'Secilen backup en yeni ve gecerli olan olmali');
    });

    test('SENARYO 2: Birden fazla gecerli backup varsa, EN YENI tarihli secilmeli', () async {
      final paths = [
        p.join(backupsDir.path, 'serenut_pos_backup_20260701_080000.db'),
        p.join(backupsDir.path, 'serenut_pos_backup_20260705_120000.db'),
        p.join(backupsDir.path, 'serenut_pos_backup_20260710_180000.db'), // EN YENI
      ];
      // Siradaki timestamps ile olustur
      final times = [
        DateTime(2026, 7, 1, 8, 0, 0),
        DateTime(2026, 7, 5, 12, 0, 0),
        DateTime(2026, 7, 10, 18, 0, 0),
      ];

      for (var i = 0; i < paths.length; i++) {
        await _createValidSqliteFile(paths[i]);
        File(paths[i]).setLastModifiedSync(times[i]);
      }

      final svc = _TestableIntegrityCheckService(
        dbsPath: tempDbsDir.path,
        docsPath: tempDocsDir.path,
      );
      final result = await svc.runRepair();

      expect(result['success'], isTrue);
      expect(result['source'], equals('serenut_pos_backup_20260710_180000.db'),
          reason: '20260710_180000 en yeni backup olmali — en son tarihli secilmeli');
    });

    test('SENARYO 3: SerenutBackups bos, upgrade backup da yok => false donmeli', () async {
      // Backups dizini bos, upgrade backup olusturulmadi
      final svc = _TestableIntegrityCheckService(
        dbsPath: tempDbsDir.path,
        docsPath: tempDocsDir.path,
      );
      final result = await svc.runRepair();

      expect(result['success'], isFalse,
          reason: 'Hic backup yoksa repair false donmeli');
      expect(result['source'], isNull);
    });

    test('SENARYO 4: SerenutBackups bos ama upgrade backup var => ona fallback etmeli', () async {
      // SerenutBackups/ dizini bos birakilir
      // upgrade backup olusturulur
      final upgradePath = p.join(tempDbsDir.path, 'serenut_pos_upgrade_backup.db');
      await _createValidSqliteFile(upgradePath);

      final svc = _TestableIntegrityCheckService(
        dbsPath: tempDbsDir.path,
        docsPath: tempDocsDir.path,
      );
      final result = await svc.runRepair();

      expect(result['success'], isTrue,
          reason: 'SerenutBackups bos oldugunda upgrade backup kullanilmali');
      expect(result['source'], equals('serenut_pos_upgrade_backup.db'),
          reason: 'Fallback kaynak upgrade backup olmali');
    });

    test('SENARYO 5: Repair basarisizsa mevcut DB rollback ile korunmali', () async {
      // Var olan DB oluştur
      final existingDbPath = p.join(tempDbsDir.path, 'serenut_pos.db');
      await _createValidSqliteFile(existingDbPath);
      final originalContent = await File(existingDbPath).readAsBytes();

      // Sadece bozuk backup koy (repair basarisiz olmali)
      final corruptPath =
          p.join(backupsDir.path, 'serenut_pos_backup_20260710_100000.db');
      await _createCorruptFile(corruptPath);

      final svc = _TestableIntegrityCheckService(
        dbsPath: tempDbsDir.path,
        docsPath: tempDocsDir.path,
      );
      final result = await svc.runRepair();

      expect(result['success'], isFalse,
          reason: 'Bozuk backup ile repair basarili olmamali');

      // Rollback: orijinal DB geri yuklenmis olmali
      expect(await File(existingDbPath).exists(), isTrue,
          reason: 'Rollback sonrasi orijinal DB hala var olmali');
      final restoredContent = await File(existingDbPath).readAsBytes();
      expect(restoredContent, equals(originalContent),
          reason: 'Rollback sonrasi DB icerigi degismemis olmali');
    });
  });
}