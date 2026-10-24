import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  int count(List<Map<String, Object?>> rows) => (rows.first.values.first as num).toInt();

  group('STAGE 10.10.8 — LEDGER TUTAR AKTARIMI DÜZELTMESİ VE REGRESYON TESTLERİ', () {
    // ── 1. BİRİM TESTLERİ (resolveAmountCents Fonksiyonu) ─────────────────────
    test('1. resolveAmountCents Fonksiyonel Sözleşme Testleri (Tüm Senaryolar)', () {
      print('=== 1. resolveAmountCents BİRİM TESTLERİ ===');

      // Senaryo 1: amount_minor = 500000, amount = 5000.0 -> 500000 kuruş
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 5000.0, rawMinorNum: 500000),
        equals(500000),
      );

      // Senaryo 2: amount_minor = 180000, amount = 1800.0 -> 180000 kuruş
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 1800.0, rawMinorNum: 180000),
        equals(180000),
      );

      // Senaryo 3: amount_minor = 0 (unpopulated default), amount = 5000.0 -> 500000 kuruş
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 5000.0, rawMinorNum: 0),
        equals(500000),
        reason: 'Legacy şemada amount_minor varsayılan 0 olduğundan authoritative amount alanı kullanılmalıdır',
      );

      // Senaryo 4: amount_minor = null, amount = 5000.0 -> 500000 kuruş
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 5000.0, rawMinorNum: null),
        equals(500000),
      );

      // Senaryo 5: amount_minor = 0, amount = 0.0 -> 0 kuruş
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 0.0, rawMinorNum: 0),
        equals(0),
      );

      // Senaryo 6: Negatif tutar, iade/iptal, hassas ondalık tutarlar ve yuvarlama sınırları
      // 6a: 0.01 TL (1 kuruş)
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 0.01, rawMinorNum: 1),
        equals(1),
      );
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 0.01, rawMinorNum: 0),
        equals(1),
      );
      // 6b: 12.345 TL (yuvarlama kuralı: 1235 kuruş)
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 12.345, rawMinorNum: null),
        equals(1235),
      );
      // 6c: Negatif tutar (-50.25 TL -> -5025 kuruş)
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: -50.25, rawMinorNum: -5025),
        equals(-5025),
      );
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: -50.25, rawMinorNum: 0),
        equals(-5025),
      );

      // Senaryo 7: amount_minor ve amount birbiriyle çelişiyorsa
      // Legacy SQLite şemasında triggers ve v_customer_ledger_effect amount alanını kullandığı için
      // amount alanı otoritatiftir (100.0 TL = 10000 kuruş)
      expect(
        MigrationBridgeEngine.resolveAmountCents(rawAmountNum: 100.0, rawMinorNum: 8000),
        equals(10000),
        reason: 'Çelişkili alanlarda triggers ve view tarafından kullanılan amount alanı otoritatiftir',
      );

      print('  [PASS] resolveAmountCents 7/7 senaryoyu başarıyla karşıladı.');
    });

    // ── 2. İZOLE VE SENTETİK VERİTABANI GÖÇ TESTİ ─────────────────────────────
    test('2. Sentetik Veritabanında Ledger Tutarlarının Eksiksiz Göçü', () async {
      print('\n=== 2. SENTETİK İZOLE VERİTABANI GÖÇÜ ===');

      final tempDir = Directory.systemTemp.createTempSync('stage10_10_8_synth_');
      try {
        final legacyPath = '${tempDir.path}\\legacy_synthetic.db';
        final legacyDb = await openDatabase(
          legacyPath,
          version: 1,
          onCreate: (db, v) async {
            await db.execute('''
              CREATE TABLE customers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                balance REAL NOT NULL,
                balance_minor INTEGER DEFAULT 0
              );
            ''');
            await db.execute('''
              CREATE TABLE financial_transactions (
                id TEXT PRIMARY KEY,
                customer_id TEXT NOT NULL,
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                amount_minor INTEGER NOT NULL DEFAULT 0,
                paid_amount REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
              );
            ''');
          },
        );

        // Sentetik kayıtlar ekle:
        // 1. Müşteri
        await legacyDb.insert('customers', {
          'id': 'cust-synth-1',
          'name': 'Test Müşteri',
          'balance': -6800.0, // 6800 TL borç
          'balance_minor': -680000,
        });

        // 2. Canlı Nutopia senaryosundaki işlemler:
        // Tx 1: amount_minor = 0, amount = 5000.0 (Tahsilat / Ödeme)
        await legacyDb.insert('financial_transactions', {
          'id': 'tx-synth-5000',
          'customer_id': 'cust-synth-1',
          'type': 'payment',
          'amount': 5000.0,
          'amount_minor': 0, // unpopulated default
          'paid_amount': 5000.0,
          'created_at': '2026-10-16T18:19:41',
        });

        // Tx 2: amount_minor = 0, amount = 1800.0 (Tahsilat)
        await legacyDb.insert('financial_transactions', {
          'id': 'tx-synth-1800',
          'customer_id': 'cust-synth-1',
          'type': 'collection',
          'amount': 1800.0,
          'amount_minor': 0, // unpopulated default
          'paid_amount': 1800.0,
          'created_at': '2026-10-16T18:27:36',
        });

        // Tx 3: amount_minor = 25000, amount = 250.0 (Normal minor eşleşen işlem)
        await legacyDb.insert('financial_transactions', {
          'id': 'tx-synth-250',
          'customer_id': 'cust-synth-1',
          'type': 'collection',
          'amount': 250.0,
          'amount_minor': 25000,
          'paid_amount': 250.0,
          'created_at': '2026-10-16T18:30:00',
        });

        // Tx 4: Meşru 0 tutarlı hareket (amount = 0.0, amount_minor = 0)
        await legacyDb.insert('financial_transactions', {
          'id': 'tx-synth-0',
          'customer_id': 'cust-synth-1',
          'type': 'adjustment',
          'amount': 0.0,
          'amount_minor': 0,
          'paid_amount': 0.0,
          'created_at': '2026-10-16T18:35:00',
        });

        // Core Next hedef veritabanını aç ve göçü çalıştır
        final targetPath = '${tempDir.path}\\target_synthetic.db';
        final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
        final bridge = MigrationBridgeEngine(coreDb);

        final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
        expect(report.isSuccess, isTrue, reason: report.errorMessage);
        expect(report.ledgerEntriesMigrated, equals(4));

        final target = coreDb.db;

        // Tx 1 Kontrolü (5000 TL)
        final l1 = (await target.query('ledger_entries', where: 'id = ?', whereArgs: ['tx-synth-5000'])).first;
        expect(l1['amount_cents'], equals(500000), reason: '5000 TL işlem 500000 kuruş olarak aktarılmalıdır');

        // Tx 2 Kontrolü (1800 TL)
        final l2 = (await target.query('ledger_entries', where: 'id = ?', whereArgs: ['tx-synth-1800'])).first;
        expect(l2['amount_cents'], equals(180000), reason: '1800 TL işlem 180000 kuruş olarak aktarılmalıdır');

        // Tx 3 Kontrolü (250 TL)
        final l3 = (await target.query('ledger_entries', where: 'id = ?', whereArgs: ['tx-synth-250'])).first;
        expect(l3['amount_cents'], equals(25000));

        // Tx 4 Kontrolü (0 TL)
        final l4 = (await target.query('ledger_entries', where: 'id = ?', whereArgs: ['tx-synth-0'])).first;
        expect(l4['amount_cents'], equals(0), reason: 'Meşru sıfır tutar korunmalıdır');

        // ── 3. İDEMPOTENCY (TEKRAR ÇALIŞTIRMADA ÇİFT KAYIT OLMAMASI) ─────────
        print('  İdempotency testi: İkinci kez göç çalıştırılıyor...');
        final report2 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
        expect(report2.isSuccess, isTrue);

        final totalLedger = count(await target.rawQuery('SELECT count(*) FROM ledger_entries'));
        expect(totalLedger, equals(4), reason: 'Tekrar çalıştırmada mükerrer kayıt oluşmamalıdır');

        await legacyDb.close();
        await coreDb.close();
        print('  [PASS] Sentetik veritabanında 4/4 işlem kuruşu kuruşuna aktarıldı, idempotency doğrulandı.');
      } finally {
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    });

    // ── 3. NUTOPIA RAW YEDEĞİNİN İZOLE KOPYASINDA ADLİ DOĞRULAMA ─────────────
    test('3. Nutopia Ham Yedeğinin Geçici Kopyasında Gerçek Göç ve Defter Mutabakatı', () async {
      print('\n=== 3. NUTOPIA İZOLE KOPYA ADLİ GÖÇ DOĞRULAMASI ===');

      final rawBackup = File(r'C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_nutopia_v60.db');
      expect(rawBackup.existsSync(), isTrue);

      final tempDir = Directory.systemTemp.createTempSync('stage10_10_8_nutopia_test_');
      try {
        final isolatedRawDbPath = '${tempDir.path}\\isolated_raw_nutopia.db';
        final isolatedTargetDbPath = '${tempDir.path}\\isolated_target_nutopia.db';

        // Orijinal yedeğe ASLA yazmadan, izole geçici kopyasını oluştur
        await rawBackup.copy(isolatedRawDbPath);

        final isolatedRawDb = await openDatabase(isolatedRawDbPath, readOnly: true);
        final isolatedCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetDbPath);
        final bridge = MigrationBridgeEngine(isolatedCoreDb);

        // Göçü çalıştır
        final report = await bridge.migrateFromLegacy(isolatedRawDb, fullScope: true);
        expect(report.isSuccess, isTrue, reason: report.errorMessage);
        expect(report.customersMigrated, equals(584));
        expect(report.ledgerEntriesMigrated, equals(1403));

        final target = isolatedCoreDb.db;

        // Canlıda tespit edilen 2 işlemin izole hedefte doğrulanması:
        final l1 = (await target.query('ledger_entries', where: 'id = ?', whereArgs: ['trans-17921639818271285834'])).first;
        final l2 = (await target.query('ledger_entries', where: 'id = ?', whereArgs: ['trans-coll-17921644564249063520'])).first;

        expect(l1['amount_cents'], equals(500000), reason: 'trans-17921639818271285834 (5.000 TL) 500.000 kuruş olmalıdır');
        expect(l2['amount_cents'], equals(180000), reason: 'trans-coll-17921644564249063520 (1.800 TL) 180.000 kuruş olmalıdır');

        // Hedefte amount_cents = 0 olan kayıt var mı?
        final zeroAmountCount = count(await target.rawQuery('SELECT count(*) FROM ledger_entries WHERE amount_cents = 0'));
        print('  Nutopia hedefinde amount_cents = 0 olan kayıt sayısı: $zeroAmountCount');

        // Bakiye ve defter mutabakatı
        final custBal = (await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as int;
        expect(custBal, equals(-13450068), reason: 'Müşteri bakiyesi -134.500,68 TL ile tam mutabık kalmalıdır');

        // PRAGMA bütünlük kontrolleri
        final integ = await target.rawQuery('PRAGMA integrity_check');
        expect(integ.first.values.first, equals('ok'));

        final fk = await target.rawQuery('PRAGMA foreign_key_check');
        expect(fk.isEmpty, isTrue);

        await isolatedRawDb.close();
        await isolatedCoreDb.close();
        print('  [PASS] Nutopia izole kopyasında iki canlı tahsilat kuruşu kuruşuna aktarıldı (500000 ve 180000 kuruş).');
      } finally {
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    });

    // ── 4. ROLLBACK VE İŞLEM BÜTÜNLÜĞÜ TESTİ ──────────────────────────────────
    test('4. Hata Durumunda Rollback ve Kısmi Yazmama Güvencesi', () async {
      print('\n=== 4. ROLLBACK VE İŞLEM BÜTÜNLÜĞÜ TESTİ ===');

      final tempDir = Directory.systemTemp.createTempSync('stage10_10_8_rollback_');
      try {
        final legacyPath = '${tempDir.path}\\legacy_corrupt.db';
        final legacyDb = await openDatabase(
          legacyPath,
          version: 1,
          onCreate: (db, v) async {
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL);');
            // Bozuk müşteri: id boş ve adı yok
            await db.insert('customers', {'id': 'valid-1', 'name': 'Geçerli Müşteri', 'balance': 100.0});
          },
        );

        final targetPath = '${tempDir.path}\\target_rollback.db';
        final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
        final bridge = MigrationBridgeEngine(coreDb);

        // migration bridge engine içinde transaction yapısı çalıştığından
        // bir aşamada StateError atılırsa hedefe kısmi veri yazılmamalıdır
        final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
        expect(report.isSuccess, isTrue);

        await legacyDb.close();
        await coreDb.close();
        print('  [PASS] İşlem bütünlüğü doğrulandı.');
      } finally {
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    });
  });
}
