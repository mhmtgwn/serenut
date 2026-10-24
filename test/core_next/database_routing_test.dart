import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.12.4 — DATABASE ROUTING GÜVENLİK VE İZOLE TESTLERİ', () {
    late Directory tempDir;
    late String legacyDbPath;
    const resolver = DatabaseRoutingResolver();

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('stage10_12_4_routing_');
      legacyDbPath = p.join(tempDir.path, 'serenut_pos_legacy.db');

      // Legacy DB oluştur
      final legDb = await openDatabase(legacyDbPath, version: 60);
      await legDb.execute('CREATE TABLE IF NOT EXISTS settings (id TEXT PRIMARY KEY, business_name TEXT);');
      await legDb.insert('settings', {'id': 's1', 'business_name': 'Nutopia Fındık Değirmeni'});
      await legDb.close();
    });

    tearDownAll(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // 1. Doğru tenant ID ve doğrulanmış hedef DB
    test('1. Doğru tenant ID ve doğrulanmış hedef DB başarıyla seçilmelidir', () async {
      final targetPath = p.join(tempDir.path, 'nutopia_valid_target.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia-01',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.close();

      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.targetSelected));
      expect(result.resolvedPath, equals(targetPath));
      expect(result.isTargetSelected, isTrue);
    });

    // 2. Eksik hedef dosya (Boş dosya OLUŞTURULMAMALI, legacy'ye dönmeli)
    test('2. Eksik hedef dosya varsa ASLA boş DB açılmamalı, legacy açılmalıdır', () async {
      final missingPath = p.join(tempDir.path, 'non_existent_target.db');

      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: missingPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.legacyFallback));
      expect(result.resolvedPath, equals(legacyDbPath));
      expect(result.isTargetSelected, isFalse);
      expect(File(missingPath).existsSync(), isFalse, reason: 'Boş dosya yaratılmamış olmalı');
    });

    // 3. Bozuk DB
    test('3. Bozuk veya sıfır baytlık hedef DB fail-closed ile reddedilmelidir', () async {
      final corruptPath = p.join(tempDir.path, 'corrupt_target.db');
      File(corruptPath).writeAsBytesSync([1, 2, 3, 4]); // Geçersiz SQLite dosyası

      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: corruptPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.resolvedPath, equals(legacyDbPath));
    });

    // 4. Yanlış tenant ID
    test('4. Yanlış tenant ID tespit edildiğinde hedef dosya reddedilmelidir', () async {
      final targetPath = p.join(tempDir.path, 'tenant_mismatch_target.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-erkul-02',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.close();

      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.reason, contains('Tenant ID uyuşmazlığı'));
    });

    // 5. Yanlış şema sürümü
    test('5. Hedef DB şema sürümü Core Next v3 değilse reddedilmelidir', () async {
      final wrongVersionPath = p.join(tempDir.path, 'wrong_version_target.db');
      final db = await openDatabase(wrongVersionPath, version: 1);
      await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT, updated_at INTEGER);');
      await db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia-01',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await db.close();

      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: wrongVersionPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.reason, contains('şema sürümü uyumsuz'));
    });

    // 6. Eksik veya yarım aktarım durumu
    test('6. Migration durumu tamamlanmadıysa (inProgress) hedef dosya seçilmemelidir', () async {
      final targetPath = p.join(tempDir.path, 'incomplete_target.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await coreDb.close();

      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetPath,
        migrationStateCompleted: false, // Yarım kalmış
      );

      expect(result.decision, equals(RoutingDecision.legacyFallback));
      expect(result.resolvedPath, equals(legacyDbPath));
    });

    // 7. Aynı isimli fakat farklı kimlikli işletme
    test('7. İşletme adı aynı olsa bile Tenant ID farklıysa hedef reddedilmelidir', () async {
      final targetPath = p.join(tempDir.path, 'name_collision_target.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'comp-FAKE-999',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('app_settings', {
        'key': 'business_name',
        'value': 'Nutopia Fındık Değirmeni',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.close();

      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-REAL',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.isTargetSelected, isFalse);
    });

    // 8. İki farklı işletmenin aynı cihazda bulunması
    test('8. İki farklı işletme için izole ve farklı DB yolları çözülmelidir', () async {
      final nutopiaPath = p.join(tempDir.path, 'nutopia_tenant.db');
      final serenutPath = p.join(tempDir.path, 'serenut_tenant.db');

      final coreNutopia = await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaPath);
      await coreNutopia.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreNutopia.close();

      final coreSerenut = await CoreAppDatabase.open(inMemoryOrCustomPath: serenutPath);
      await coreSerenut.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-serenut',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreSerenut.close();

      final resNutopia = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: nutopiaPath,
        migrationStateCompleted: true,
      );

      final resSerenut = await resolver.resolve(
        requestedTenantId: 'tenant-serenut',
        legacyDbPath: legacyDbPath,
        targetDbPath: serenutPath,
        migrationStateCompleted: true,
      );

      expect(resNutopia.resolvedPath, equals(nutopiaPath));
      expect(resSerenut.resolvedPath, equals(serenutPath));
      expect(resNutopia.resolvedPath, isNot(equals(resSerenut.resolvedPath)));
    });

    // 9. Aktarım sırasında hata veya uygulamanın kapanması
    test('9. Aktarım sırasında kapanış veya kilit durumunda legacy fallback çalışmalıdır', () async {
      final result = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: null,
        migrationStateCompleted: false,
      );

      expect(result.decision, equals(RoutingDecision.legacyFallback));
      expect(result.resolvedPath, equals(legacyDbPath));
    });

    // 10. İlk yazımdan sonra geri dönüş talebi (Sessiz geri dönüş ENGELLENMELİ!)
    test('10. Yeni DB ye işlem yazıldıktan sonra sessiz geri dönüş UnsafeRollbackException fırlatmalıdır', () async {
      final targetPath = p.join(tempDir.path, 'post_write_target.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);

      final cutoverTimestamp = DateTime.now().millisecondsSinceEpoch - 1000;

      // Yeni DB'ye satış yaz
      await coreDb.db.insert('sales', {
        'id': 'sale-post-cutover-1',
        'receipt_no': 'REC-POST-1',
        'subtotal_cents': 1000,
        'total_cents': 1000,
        'paid_cents': 1000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Geri dönüşü dene -> Yeni satış olduğu için hata fırlatmalıdır!
      expect(
        () => resolver.assertSafeRollback(
          targetDb: coreDb.db,
          initialMigrationCutoffTimestamp: cutoverTimestamp,
        ),
        throwsA(isA<UnsafeRollbackException>()),
      );

      await coreDb.close();
    });

    // 11. DB'nin yeniden açılması
    test('11. Hedef DB kapatılıp yeniden açıldığında tutarlılık korunmalıdır', () async {
      final targetPath = p.join(tempDir.path, 'reopen_target.db');
      var coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-reopen-01',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.close();

      // İkinci kez resolve et ve aç
      final result = await resolver.resolve(
        requestedTenantId: 'tenant-reopen-01',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetPath,
        migrationStateCompleted: true,
      );
      expect(result.decision, equals(RoutingDecision.targetSelected));

      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: result.resolvedPath);
      final check = await coreDb.db.query('app_settings', where: 'key = ?', whereArgs: ['tenant_id']);
      expect(check.first['value'], equals('tenant-reopen-01'));
      await coreDb.close();
    });

    // 12. Sync outbox ve idempotency kayıtlarının korunması
    test('12. Outbox mutasyonları ve idempotency anahtarları korunmalıdır', () async {
      final targetPath = p.join(tempDir.path, 'outbox_target.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);

      await coreDb.db.insert('sync_events', {
        'event_id': 'evt-uuid-001',
        'entity_type': 'sale',
        'entity_id': 'sale-001',
        'operation': 'UPSERT',
        'payload_json': '{"sale_id": "s1"}',
        'base_revision': 1,
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'PENDING',
        'attempts': 0,
        'causal_sequence': 1,
      });

      final rows = await coreDb.db.query('sync_events');
      expect(rows.length, equals(1));
      expect(rows.first['event_id'], equals('evt-uuid-001'));
      expect(rows.first['causal_sequence'], equals(1));

      await coreDb.close();
    });
  });
}
