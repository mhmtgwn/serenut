// test/core_next/stage10_12_43_financial_reconciliation_and_adapter_audit_test.dart
// SERENUT OS — STAGE 10.12.43
// Canlı Veri Güvenliği, Adaptör Doğrulama ve Finansal Mutabakat Test Paketi

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/providers/repository_providers.dart';

String _calcSha256(String path) {
  final file = File(path);
  if (!file.existsSync()) return '';
  return sha256.convert(file.readAsBytesSync()).toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const rawSerenutPath = 'backups/raw_tenants_20261016/raw_serenut_v44.db';
  const rawErkulJsonPath = 'backups/raw_tenants_20261016/raw_erkul_source.json';
  const liveBackupPath =
      r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db';

  group('SERENUT OS — STAGE 10.12.43 AUDIT SUITE', () {
    // ══════════════════════════════════════════════════════════════════════════
    // GRUP 1: Güvenlik Sabitleri ve Pilot Kapısı İncelemesi
    // ══════════════════════════════════════════════════════════════════════════
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isCoreNextEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(isCoreNextEnabled, isFalse,
          reason: 'Canlı güvenlik sabiti gereği coreNextSalesEngineEnabledProvider daima false olmalıdır.');
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Canlı güvenlik sabiti gereği DatabaseManager.databaseRoutingHook daima null olmalıdır.');
      expect(container.read(coreNextSaleExecutorProvider), isNull,
          reason: 'Core Next satış yönlendiricisi bağlı olmamalıdır.');
      expect(container.read(coreNextProductRepositoryProvider), isNull,
          reason: 'Core Next ürün reposu varsayılan olarak null olmalıdır.');
      expect(container.read(coreNextCustomerRepositoryProvider), isNull,
          reason: 'Core Next müşteri reposu varsayılan olarak null olmalıdır.');
    });

    test('1.2: PilotCutoverGate varsayılan durumda fail-closed kilitlidir (disabledByDefault)', () async {
      SharedPreferences.setMockInitialValues({
        'core_next_pilot_enabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      const gate = PilotCutoverGate();

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: 'tenant-nutopia',
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, PilotGateStatus.disabledByDefault);
      expect(result.reason, contains('core_next_pilot_enabled = false'));
      expect(result.overrides, isEmpty);
    });

    test('1.3: DatabaseManager Core Next şemasına bağlanmayı fail-closed engeller', () async {
      final dbManager = DatabaseManager.instance;
      // Geçici Core Next veritabanı oluştur
      final tempDir = Directory.systemTemp.createTempSync('stage43_schema_guard_');
      final coreDbFile = File('${tempDir.path}/fake_core_next.db');

      final db = await databaseFactory.openDatabase(coreDbFile.path);
      await db.execute('PRAGMA user_version = 3;');
      await db.execute('CREATE TABLE ledger_entries (id TEXT PRIMARY KEY);');
      await db.execute('CREATE TABLE sync_events (event_id TEXT PRIMARY KEY);');
      await db.close();

      DatabaseManager.overrideDatabasePath = coreDbFile.path;
      addTearDown(() {
        DatabaseManager.overrideDatabasePath = null;
        dbManager.reset();
        tempDir.deleteSync(recursive: true);
      });

      expect(
        () async => await dbManager.getDatabase(),
        throwsA(isA<IncompatibleDatabaseSchemaException>()),
        reason: 'Legacy DatabaseManager Core Next veritabanına bağlanmayı şema sınırı korumasıyla reddetmelidir.',
      );
    });

    // ══════════════════════════════════════════════════════════════════════════
    // GRUP 2: Erkul Çeyiz Finansal Adli Analizi ve Kök Neden Kanıtı
    // ══════════════════════════════════════════════════════════════════════════
    test('2.1: Erkul JSON 401 müşteriden 397 sinde card_balance == -collections eşitliği kanıtı', () {
      final erkulFile = File(rawErkulJsonPath);
      expect(erkulFile.existsSync(), isTrue);

      final content = erkulFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final customers = data['customers'] as List;
      final txs = data['financial_transactions'] as List;

      expect(customers.length, 401);
      expect(txs.length, 539);

      final custCollections = <String, double>{};
      for (final c in customers) {
        custCollections[c['id'].toString()] = 0.0;
      }

      for (final t in txs) {
        final tp = t['type']?.toString();
        final cid = t['customer_id']?.toString();
        if (cid != null && (tp == 'collection' || tp == 'payment')) {
          final paid = (t['paid_amount'] as num?)?.toDouble() ??
              (t['amount'] as num?)?.toDouble() ??
              0.0;
          custCollections[cid] = (custCollections[cid] ?? 0.0) + paid;
        }
      }

      int matchCount = 0;
      final mismatches = <Map<String, dynamic>>[];

      for (final c in customers) {
        final cid = c['id'].toString();
        final cardBal = (c['balance'] as num?)?.toDouble() ?? 0.0;
        final coll = custCollections[cid] ?? 0.0;
        final diff = (cardBal - (-coll)).abs();

        if (diff < 0.01) {
          matchCount++;
        } else {
          mismatches.add({
            'name': c['name'],
            'cardBal': cardBal,
            'collections': coll,
            'diff': diff,
          });
        }
      }

      // 401 müşteriden 397'sinde tam eşitlik vardır (%99.0)
      expect(matchCount, 397);
      expect(mismatches.length, 4);

      // Kalan 4 müşterinin tümü "TUNAHAN" adını taşır (dahili test kayıtları)
      for (final m in mismatches) {
        expect(m['name'].toString().toUpperCase(), contains('TUNAHAN'));
      }
    });

    test('2.2: Erkul Çeyiz için diskte hiçbir SQLite Legacy (.db) yedeği bulunmadığının kanıtı', () {
      // Diskte olabilecek tüm konumlarda .db araması
      final searchDirs = [
        Directory('backups'),
        Directory(r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups'),
      ];

      final foundErkulLegacyDbs = <String>[];
      for (final dir in searchDirs) {
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true)) {
          if (f is File &&
              f.path.toLowerCase().contains('erkul') &&
              f.path.endsWith('.db') &&
              !f.path.contains('core_next')) {
            foundErkulLegacyDbs.add(f.path);
          }
        }
      }

      expect(foundErkulLegacyDbs, isEmpty,
          reason: 'Erkul Çeyiz için hiçbir Legacy SQLite (.db) yedeği mevcut değildir.');
    });

    // ══════════════════════════════════════════════════════════════════════════
    // GRUP 3: Nutopia 16–19 Ekim Mutabakatı ve Stok Çıkışı
    // ══════════════════════════════════════════════════════════════════════════
    test('3.1: Nutopia 16-19 Ekim farkı ve -526.40 stok çıkışı matematiksel mutabakatı', () async {
      final db16 = await databaseFactory.openDatabase(
        File(rawNutopiaPath).absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final db19 = await databaseFactory.openDatabase(
        File(liveBackupPath).absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(() async {
        await db16.close();
        await db19.close();
      });

      // Müşteri delta: +17
      final c16Count = Sqflite.firstIntValue(await db16.rawQuery('SELECT COUNT(*) FROM customers;'))!;
      final c19Count = Sqflite.firstIntValue(await db19.rawQuery('SELECT COUNT(*) FROM customers;'))!;
      expect(c16Count, 584);
      expect(c19Count, 601);
      expect(c19Count - c16Count, 17);

      // Sipariş delta: +22
      final o16Count = Sqflite.firstIntValue(await db16.rawQuery('SELECT COUNT(*) FROM orders;'))!;
      final o19Count = Sqflite.firstIntValue(await db19.rawQuery('SELECT COUNT(*) FROM orders;'))!;
      expect(o16Count, 792);
      expect(o19Count, 814);
      expect(o19Count - o16Count, 22);

      // Sipariş kalemi delta: +31
      final oi16Count = Sqflite.firstIntValue(await db16.rawQuery('SELECT COUNT(*) FROM order_items;'))!;
      final oi19Count = Sqflite.firstIntValue(await db19.rawQuery('SELECT COUNT(*) FROM order_items;'))!;
      expect(oi16Count, 1068);
      expect(oi19Count, 1099);
      expect(oi19Count - oi16Count, 31);

      // Finansal hareket delta: +42
      final ft16Count = Sqflite.firstIntValue(await db16.rawQuery('SELECT COUNT(*) FROM financial_transactions;'))!;
      final ft19Count = Sqflite.firstIntValue(await db19.rawQuery('SELECT COUNT(*) FROM financial_transactions;'))!;
      expect(ft16Count, 1424);
      expect(ft19Count, 1466);
      expect(ft19Count - ft16Count, 42);

      // Stok değişimi: Tam olarak -526.40 birim
      final s16Res = await db16.rawQuery('SELECT SUM(quantity) as tot FROM products;');
      final s19Res = await db19.rawQuery('SELECT SUM(quantity) as tot FROM products;');
      final s16Tot = (s16Res.first['tot'] as num).toDouble();
      final s19Tot = (s19Res.first['tot'] as num).toDouble();
      final stockDelta = s19Tot - s16Tot;

      expect((stockDelta - (-526.40)).abs() < 0.01, isTrue,
          reason: '16-19 Ekim arasındaki net stok değişimi -526.40 birim olmalıdır.');

      // 19 Ekim carili defter ve carisiz kasa ayrımı
      final anonCount = Sqflite.firstIntValue(await db19.rawQuery(
          "SELECT COUNT(*) FROM financial_transactions WHERE customer_id IS NULL OR customer_id = '' OR customer_id = 'customer-pesin-default';"))!;
      final ledgerCount = Sqflite.firstIntValue(await db19.rawQuery(
          "SELECT COUNT(*) FROM financial_transactions WHERE customer_id IS NOT NULL AND customer_id != '' AND customer_id != 'customer-pesin-default';"))!;
      expect(anonCount, 21);
      expect(ledgerCount, 1445);
      expect(anonCount + ledgerCount, 1466);
    });

    // ══════════════════════════════════════════════════════════════════════════
    // GRUP 4: Kaynak Dosyaların Değişmezlik ve Hash Doğrulaması
    // ══════════════════════════════════════════════════════════════════════════
    test('4.1: Kaynak dosyaların kriptografik özetleri (SHA-256) doğrulanır', () {
      expect(_calcSha256(liveBackupPath), 'da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89');
      expect(_calcSha256(rawNutopiaPath), 'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24');
      expect(_calcSha256(rawSerenutPath), '9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d');
      expect(_calcSha256(rawErkulJsonPath), 'b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389');
    });
  });
}
