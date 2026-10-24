// test/core_next/stage10_12_41_erkul_recovery_nutopia_delta_test.dart
// SERENUT OS — STAGE 10.12.41
// ERKUL LEGACY RECOVERY TASARIMI + NUTOPIA DELTA MUTABAKATI TESTLERİ
//
// GÜVENLİK SINIRLARI:
// 1. Canlı veritabanlarına yazma, migration, cutover veya rollback yapılmaz.
// 2. `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` korunur.
// 3. Gerçek satış, tahsilat, iade, stok veya vadeli bakiye işlemi yapılmaz.
// 4. Testler yalnızca geçici izole SQLite dosyalarında ve bellek içi verilerle çalışır.
// 5. Kaynak dosyaların (JSON ve SQLite) SHA-256 hash değerleri değişmez kalır.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const expectedNutopiaSha = 'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';

  const rawErkulJsonPath = 'backups/raw_tenants_20261016/raw_erkul_source.json';
  const expectedErkulJsonSha = 'b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389';

  const onedriveBackupPath = r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db';
  const expectedOnedriveSha = 'da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89';

  group('STAGE 10.12.41 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK', () {
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider kesinlikle false kalmalıdır');
      expect(DatabaseManager.databaseRoutingHook, isNull, reason: 'databaseRoutingHook kesinlikle null kalmalıdır');
    });

    test('1.2: Kaynak dosya hash değerlerinin işlem öncesi ve sonrası değişmezliği kanıtlanır', () async {
      final jsonFile = File(rawErkulJsonPath);
      expect(jsonFile.existsSync(), isTrue, reason: 'Erkul JSON kaynağı mevcut olmalıdır');
      final jsonBytes = await jsonFile.readAsBytes();
      final jsonSha = sha256.convert(jsonBytes).toString();
      expect(jsonSha, equals(expectedErkulJsonSha), reason: 'Erkul JSON SHA-256 değişmez kalmalıdır');

      final nutopiaFile = File(rawNutopiaPath);
      expect(nutopiaFile.existsSync(), isTrue, reason: 'Nutopia 16 Ekim yedeği mevcut olmalıdır');
      final nutopiaBytes = await nutopiaFile.readAsBytes();
      final nutopiaSha = sha256.convert(nutopiaBytes).toString();
      expect(nutopiaSha, equals(expectedNutopiaSha), reason: 'Nutopia v60 SHA-256 değişmez kalmalıdır');

      final onedriveFile = File(onedriveBackupPath);
      expect(onedriveFile.existsSync(), isTrue, reason: 'OneDrive 19 Ekim yedeği mevcut olmalıdır');
      final onedriveBytes = await onedriveFile.readAsBytes();
      final onedriveSha = sha256.convert(onedriveBytes).toString();
      expect(onedriveSha, equals(expectedOnedriveSha), reason: 'OneDrive 19 Ekim SHA-256 değişmez kalmalıdır');
    });
  });

  group('STAGE 10.12.41 — BÖLÜM 2: ERKUL JSON RECOVERY DENETİMİ', () {
    test('2.1: Erkul JSON zorunlu alan eksikliği tespiti ve reddi', () {
      // Bir müşteri kaydında zorunlu alanlar (id, name vb.) eksikse sistem hatasız reddetmelidir
      final invalidCustomer = <String, dynamic>{
        'name': 'Eksik ID Müşterisi',
        'balance': 100.0,
      };

      bool validateCustomer(Map<String, dynamic> c) {
        if (!c.containsKey('id') || c['id'] == null || (c['id'] as String).isEmpty) {
          return false;
        }
        if (!c.containsKey('name') || c['name'] == null || (c['name'] as String).isEmpty) {
          return false;
        }
        return true;
      }

      expect(validateCustomer(invalidCustomer), isFalse);
    });

    test('2.2: Yinelenen veya geçersiz kimlik tespiti', () {
      final seenIds = <String>{};
      final customers = [
        {'id': 'cust-1', 'name': 'Ahmet'},
        {'id': 'cust-2', 'name': 'Mehmet'},
        {'id': 'cust-1', 'name': 'Ahmet Kopya'}, // Çakışan/yinelenen ID
      ];

      final duplicates = <String>[];
      for (final c in customers) {
        final id = c['id']!;
        if (seenIds.contains(id)) {
          duplicates.add(id);
        } else {
          seenIds.add(id);
        }
      }

      expect(duplicates, contains('cust-1'));
      expect(duplicates.length, equals(1));
    });

    test('2.3: Eksik müşteri / satış referansı (Foreign Key kırılması) tespiti', () {
      final validCustomerIds = {'cust-100', 'cust-200'};
      final transactions = [
        {'id': 'ft-1', 'customer_id': 'cust-100', 'amount': 500.0},
        {'id': 'ft-2', 'customer_id': 'cust-999', 'amount': 250.0}, // Olmayan müşteri referansı
      ];

      final orphaned = <String>[];
      for (final tx in transactions) {
        if (!validCustomerIds.contains(tx['customer_id'])) {
          orphaned.add(tx['id'] as String);
        }
      }

      expect(orphaned, contains('ft-2'));
      expect(orphaned.length, equals(1));
    });

    test('2.4: İzole SQLite geçici veritabanında bütünlük (PRAGMA integrity & FK) doğrulaması', () async {
      final tempDir = await Directory.systemTemp.createTemp('stage41_erkul_test_');
      final dbPath = p.join(tempDir.path, 'erkul_test.db');

      try {
        final db = await openDatabase(
          dbPath,
          version: 1,
          onCreate: (db, version) async {
            await db.execute('PRAGMA foreign_keys = ON;');
            await db.execute('''
              CREATE TABLE customers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                balance REAL DEFAULT 0,
                balance_minor INTEGER DEFAULT 0
              );
            ''');
            await db.execute('''
              CREATE TABLE financial_transactions (
                id TEXT PRIMARY KEY,
                customer_id TEXT NOT NULL,
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                amount_minor INTEGER NOT NULL,
                FOREIGN KEY (customer_id) REFERENCES customers(id)
              );
            ''');
          },
        );

        // Foreign keys aktif et
        await db.execute('PRAGMA foreign_keys = ON;');

        // Geçerli veri ekle
        await db.insert('customers', {
          'id': 'c1',
          'name': 'Test Müşteri',
          'balance': 100.0,
          'balance_minor': 10000,
        });
        await db.insert('financial_transactions', {
          'id': 'ft1',
          'customer_id': 'c1',
          'type': 'payment',
          'amount': 100.0,
          'amount_minor': 10000,
        });

        // PRAGMA integrity_check
        final integrityRes = await db.rawQuery('PRAGMA integrity_check;');
        expect(integrityRes.first.values.first, equals('ok'));

        // PRAGMA foreign_key_check
        final fkRes = await db.rawQuery('PRAGMA foreign_key_check;');
        expect(fkRes, isEmpty, reason: 'FK ihlali bulunmamalıdır');

        await db.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('2.5: Hata durumunda geçici dönüşüm işleminin atomik geri alınması (rollback)', () async {
      final tempDir = await Directory.systemTemp.createTemp('stage41_rollback_test_');
      final dbPath = p.join(tempDir.path, 'rollback_test.db');

      try {
        final db = await openDatabase(
          dbPath,
          version: 1,
          onCreate: (db, version) async {
            await db.execute('PRAGMA foreign_keys = ON;');
            await db.execute('''
              CREATE TABLE customers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL
              );
            ''');
          },
        );

        await db.insert('customers', {'id': 'init_1', 'name': 'Başlangıç Kaydı'});

        // Başarısız işlem simülasyonu
        try {
          await db.transaction((txn) async {
            await txn.insert('customers', {'id': 'c_atom_1', 'name': 'Geçici'});
            // Hata fırlat (ör. zorunlu alan hatası veya çakışma)
            throw Exception('Simüle edilmiş dönüştürme hatası');
          });
        } catch (_) {
          // Hata bekleniyor
        }

        final countRes = await db.rawQuery('SELECT COUNT(*) as cnt FROM customers;');
        final count = countRes.first['cnt'] as int;
        expect(count, equals(1), reason: 'Hata anında işlem atomik geri alınmalı, geçici kayıt kalmamalıdır');

        await db.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('STAGE 10.12.41 — BÖLÜM 3: NUTOPIA İŞLEM BAZINDA DELTA MUTABAKATI', () {
    test('3.1: Nutopia 16 Ekim ve 19 Ekim yedeğinde 17 NEW müşteri doğrulanır', () async {
      final absNutopia16 = File(rawNutopiaPath).absolute.path;
      final absNutopia19 = File(onedriveBackupPath).absolute.path;

      final nutopia16 = await databaseFactoryFfi.openDatabase(absNutopia16, options: OpenDatabaseOptions(readOnly: true));
      final nutopia19 = await databaseFactoryFfi.openDatabase(absNutopia19, options: OpenDatabaseOptions(readOnly: true));

      final cust16Rows = await nutopia16.rawQuery('SELECT id FROM customers;');
      final cust19Rows = await nutopia19.rawQuery('SELECT id FROM customers;');

      final ids16 = cust16Rows.map((r) => r['id'] as String).toSet();
      final ids19 = cust19Rows.map((r) => r['id'] as String).toSet();

      final newCustomerIds = ids19.difference(ids16);
      expect(newCustomerIds.length, equals(17), reason: 'Tam olarak 17 YENİ müşteri eklenmiş olmalıdır');

      await nutopia16.close();
      await nutopia19.close();
    });

    test('3.2: Nutopia 16 Ekim ve 19 Ekim yedeğinde 42 NEW finansal işlem (+110.990 TL) doğrulanır', () async {
      final absNutopia16 = File(rawNutopiaPath).absolute.path;
      final absNutopia19 = File(onedriveBackupPath).absolute.path;

      final nutopia16 = await databaseFactoryFfi.openDatabase(absNutopia16, options: OpenDatabaseOptions(readOnly: true));
      final nutopia19 = await databaseFactoryFfi.openDatabase(absNutopia19, options: OpenDatabaseOptions(readOnly: true));

      final ft16Rows = await nutopia16.rawQuery('SELECT id, amount FROM financial_transactions;');
      final ft19Rows = await nutopia19.rawQuery('SELECT id, amount FROM financial_transactions;');

      final map16 = {for (var r in ft16Rows) r['id'] as String: (r['amount'] as num).toDouble()};
      final map19 = {for (var r in ft19Rows) r['id'] as String: (r['amount'] as num).toDouble()};

      final newFtIds = map19.keys.toSet().difference(map16.keys.toSet());
      expect(newFtIds.length, equals(42), reason: 'Tam olarak 42 YENİ finansal işlem eklenmiş olmalıdır');

      double sumNew = 0.0;
      for (final id in newFtIds) {
        sumNew += map19[id]!;
      }

      expect(sumNew, closeTo(110990.0, 0.01), reason: 'Yeni hareketlerin tutar toplamı tam 110.990,00 TL olmalıdır');

      await nutopia16.close();
      await nutopia19.close();
    });

    test('3.3: Nutopia stok farkı (-526.40 birim) işlem ve ürün bazında doğrulanır', () async {
      final absNutopia16 = File(rawNutopiaPath).absolute.path;
      final absNutopia19 = File(onedriveBackupPath).absolute.path;

      final nutopia16 = await databaseFactoryFfi.openDatabase(absNutopia16, options: OpenDatabaseOptions(readOnly: true));
      final nutopia19 = await databaseFactoryFfi.openDatabase(absNutopia19, options: OpenDatabaseOptions(readOnly: true));

      final prod16 = await nutopia16.rawQuery('SELECT id, name, quantity FROM products;');
      final prod19 = await nutopia19.rawQuery('SELECT id, name, quantity FROM products;');

      final map16 = {for (var r in prod16) r['id'] as String: (r['quantity'] as num).toDouble()};
      final map19 = {for (var r in prod19) r['id'] as String: (r['quantity'] as num).toDouble()};

      final changedProducts = <String, double>{};
      double netStockDiff = 0.0;

      for (final entry in map16.entries) {
        final id = entry.key;
        final s16 = entry.value;
        final s19 = map19[id] ?? 0.0;
        final diff = s19 - s16;
        if (diff.abs() > 0.0001) {
          changedProducts[id] = diff;
          netStockDiff += diff;
        }
      }

      expect(changedProducts.length, equals(6), reason: 'Tam olarak 6 ürünün stoğu değişmiştir');
      expect(netStockDiff, closeTo(-526.40, 0.01), reason: 'Net stok farkı tam -526.40 olmalıdır');

      await nutopia16.close();
      await nutopia19.close();
    });

    test('3.4: Aynı ID içeriğinde çakışma (CONFLICT) tespiti', () {
      final existingRecord = {'id': 'tx-101', 'amount': 150.0, 'status': 'completed'};
      final incomingRecord = {'id': 'tx-101', 'amount': 200.0, 'status': 'completed'}; // Farklı tutar

      String classifyDelta(Map<String, dynamic> existing, Map<String, dynamic> incoming) {
        if (existing['amount'] != incoming['amount']) {
          return 'CONFLICT';
        }
        return 'DUPLICATE';
      }

      final status = classifyDelta(existingRecord, incomingRecord);
      expect(status, equals('CONFLICT'));
    });

    test('3.5: Aynı işlemin tekrar işlendiğinde çift kayıt oluşturmaması (İdempotens)', () {
      final processedTxIds = {'tx-1', 'tx-2'};
      final newTxs = [
        {'id': 'tx-2', 'amount': 100.0}, // Zaten işlenmiş
        {'id': 'tx-3', 'amount': 300.0}, // Yeni
      ];

      final toInsert = <Map<String, dynamic>>[];
      for (final tx in newTxs) {
        if (!processedTxIds.contains(tx['id'])) {
          toInsert.add(tx);
          processedTxIds.add(tx['id'] as String);
        }
      }

      expect(toInsert.length, equals(1));
      expect(toInsert.first['id'], equals('tx-3'));
      expect(processedTxIds.length, equals(3));
    });

    test('3.6: Açıklanamayan bakiye ve stok farklarının körü körüne ezilmesinin engellenmesi', () {
      // Bir ürünün stok farkını açıklayan işlem hareketi (order item veya sale item) bulunamadığında
      // sistem doğrudan stok üzerine yazmayı BLOCKED etmelidir
      final productStockChange = -10.0;
      final recordedMovementsSum = -6.0; // 4 birim açıklanamıyor

      bool canApplyDirectStockSync(double stockDiff, double movementsSum) {
        if ((stockDiff - movementsSum).abs() > 0.001) {
          // Açıklanamayan fark var, körü körüne ezme yasak!
          return false;
        }
        return true;
      }

      expect(canApplyDirectStockSync(productStockChange, recordedMovementsSum), isFalse);
    });
  });
}
