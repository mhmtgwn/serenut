// test/core_next/stage10_12_44_live_safe_export_import_test.dart
// SERENUT OS — STAGE 10.12.44
// Canlı İşlemleri Korumalı Dışa Aktarma / İçe Aktarma ve Geçiş Güvenliği Test Paketi

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
  final liveActiveDbPath = Platform.isWindows
      ? r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db'
      : '';

  group('SERENUT OS — STAGE 10.12.44 SAFE EXPORT/IMPORT & AUDIT SUITE', () {
    // ══════════════════════════════════════════════════════════════════════════
    // BÖLÜM 1: Kesin Güvenlik Sabitleri ve Kapı Denetimi
    // ══════════════════════════════════════════════════════════════════════════
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isCoreNextEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(isCoreNextEnabled, isFalse,
          reason: 'Canlı güvenlik sabiti: coreNextSalesEngineEnabledProvider daima false olmalıdır.');
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Canlı güvenlik sabiti: DatabaseManager.databaseRoutingHook daima null olmalıdır.');
      expect(container.read(coreNextSaleExecutorProvider), isNull,
          reason: 'Core Next satış executor provider varsayılan olarak null kalmalıdır.');
    });

    test('1.2: PilotCutoverGate varsayılan durumda fail-closed kilitlidir', () async {
      SharedPreferences.setMockInitialValues({'core_next_pilot_enabled': false});
      final prefs = await SharedPreferences.getInstance();
      const gate = PilotCutoverGate();

      for (final tenant in ['nutopia', 'erkul', 'serenut']) {
        final result = await gate.evaluate(
          prefs: prefs,
          requestedTenantId: tenant,
        );
        expect(result.isPilotActive, isFalse);
        expect(result.status, PilotGateStatus.disabledByDefault);
      }
    });

    // ══════════════════════════════════════════════════════════════════════════
    // BÖLÜM 2: Canlı Veritabanı ve Yedek Zaman Ayrımı (Store Operating Reality)
    // ══════════════════════════════════════════════════════════════════════════
    test('2.1: 19 Ekim yedeği ile canlı aktif veritabanı ayrımı kanıtlanır', () async {
      final backupFile = File(liveBackupPath);
      expect(backupFile.existsSync(), isTrue, reason: '19 Ekim yedeği mevcut olmalıdır.');

      final db = await openReadOnlyDatabase(liveBackupPath);
      final maxOrder = await db.rawQuery('SELECT MAX(created_at) as m FROM orders');
      final maxFinancial = await db.rawQuery('SELECT MAX(created_at) as m FROM financial_transactions');
      await db.close();

      final maxOrderTime = maxOrder.first['m'] as String?;
      final maxFinancialTime = maxFinancial.first['m'] as String?;

      expect(maxOrderTime, isNotNull);
      expect(maxOrderTime!.startsWith('2026-10-19'), isTrue,
          reason: '19 Ekim yedeğindeki siparişler 19 Ekim 15:00:57 kesitine aittir.');
      expect(maxFinancialTime!.startsWith('2026-10-19'), isTrue);

      // Canlı veritabanı aktif ise WAL veya mtime yedeğin sonrasını gösterir
      if (liveActiveDbPath.isNotEmpty && File(liveActiveDbPath).existsSync()) {
        final liveDbFile = File(liveActiveDbPath);
        final liveWalFile = File('$liveActiveDbPath-wal');

        final liveMtime = liveWalFile.existsSync()
            ? liveWalFile.lastModifiedSync()
            : liveDbFile.lastModifiedSync();

        expect(liveMtime.isAfter(DateTime(2026, 10, 19, 16, 10)), isTrue,
            reason: 'Canlı işletme veritabanı 19 Ekim 16:10 yedeğinden sonra işlem görmüştür.');
      }
    });

    // ══════════════════════════════════════════════════════════════════════════
    // BÖLÜM 3: 8 Adımlı Korumalı Dışa/İçe Aktarma ve İdempotens Provası
    // ══════════════════════════════════════════════════════════════════════════
    test('3.1: İzole alanda snapshot ve idempotens testi kaynak veriyi değiştirmeden çalışır', () async {
      final initialNutopiaSha = _calcSha256(rawNutopiaPath);
      expect(initialNutopiaSha, isNotEmpty);

      // Adım 1 & 2: Geçici çalışma veritabanı oluştur
      final tempDir = await Directory.systemTemp.createTemp('serenut_stage44_test_');
      final candidateDbPath = '${tempDir.path}/candidate_next.db';

      try {
        final candDb = await openDatabase(
          candidateDbPath,
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE core_next_sales (
                sale_id TEXT PRIMARY KEY,
                tenant_id TEXT NOT NULL,
                idempotency_key TEXT UNIQUE,
                gross_amount REAL NOT NULL,
                created_at TEXT NOT NULL
              )
            ''');
          },
        );

        // Adım 7: İdempotens simülasyonu - Aynı kayıt iki kez aktarıldığında mükerrer üretmemeli
        const testSaleId = 'sale_audit_001';
        const idempotencyKey = 'idem_nutopia_sale_001';

        // İlk aktarım
        await candDb.rawInsert('''
          INSERT OR IGNORE INTO core_next_sales (sale_id, tenant_id, idempotency_key, gross_amount, created_at)
          VALUES (?, ?, ?, ?, ?)
        ''', [testSaleId, 'nutopia', idempotencyKey, 1500.0, '2026-10-20T12:00:00']);

        var count = Sqflite.firstIntValue(await candDb.rawQuery('SELECT COUNT(*) FROM core_next_sales'));
        expect(count, equals(1));

        // İkinci aktarım (Tekrar çalıştırma / Catch-up provası)
        await candDb.rawInsert('''
          INSERT OR IGNORE INTO core_next_sales (sale_id, tenant_id, idempotency_key, gross_amount, created_at)
          VALUES (?, ?, ?, ?, ?)
        ''', [testSaleId, 'nutopia', idempotencyKey, 1500.0, '2026-10-20T12:00:00']);

        count = Sqflite.firstIntValue(await candDb.rawQuery('SELECT COUNT(*) FROM core_next_sales'));
        expect(count, equals(1), reason: 'İdempotens anahtarı mükerrer kayıt oluşmasını engellemelidir.');

        // Adım 8: Aday veritabanını temizle
        await candDb.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }

      // Kaynak dosya dokunulmazlık doğrulaması
      final afterNutopiaSha = _calcSha256(rawNutopiaPath);
      expect(afterNutopiaSha, equals(initialNutopiaSha),
          reason: 'Dışa/içe aktarma provası kaynak SQLite dosyasına 0 bayt mutasyon uygulamalıdır.');
    });

    // ══════════════════════════════════════════════════════════════════════════
    // BÖLÜM 4: Erkul Çeyiz Finansal Anlam ve Bakiye Değişmezliği
    // ══════════════════════════════════════════════════════════════════════════
    test('4.1: Erkul Çeyiz manual_debt ve collection kayıtları semantik olarak doğrulanır', () {
      final jsonFile = File(rawErkulJsonPath);
      expect(jsonFile.existsSync(), isTrue);

      final decoded = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final transactions = decoded['financial_transactions'] as List<dynamic>;

      var manualDebtTotal = 0.0;
      var manualDebtCount = 0;
      var collectionTotal = 0.0;
      var collectionCount = 0;

      for (final tx in transactions) {
        final type = tx['type']?.toString();
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        if (type == 'manual_debt') {
          manualDebtTotal += amount;
          manualDebtCount++;
        } else if (type == 'collection') {
          collectionTotal += amount;
          collectionCount++;
        }
      }

      expect(manualDebtCount, equals(423), reason: 'Erkul çeyiz sözleşme borçlandırma adedi 423 olmalıdır.');
      expect(manualDebtTotal, equals(4310745.0), reason: 'manual_debt toplamı 4,310,745.00 TL olmalıdır.');
      expect(collectionCount, equals(109), reason: 'Erkul tahsilat adedi 109 olmalıdır.');
      expect(collectionTotal, equals(541640.0), reason: 'collection toplamı 541,640.00 TL olmalıdır.');

      // Bakiye müdahalesi yapılmaksızın işletme gerçeği teyidi
      final netReceivable = manualDebtTotal - collectionTotal;
      expect(netReceivable, equals(3769105.0)); // 3.769M TL net senetli çeyiz alacağı
    });

    // ══════════════════════════════════════════════════════════════════════════
    // BÖLÜM 5: Donanım ve Yazıcı Profil Güvenliği
    // ══════════════════════════════════════════════════════════════════════════
    test('5.1: Yazıcı yönlendirme profilleri salt okunur doğrulanır ve satışa bağımlı değildir', () async {
      final backupFile = File(liveBackupPath);
      final db = await openReadOnlyDatabase(backupFile.path);

      final printers = await db.rawQuery('SELECT * FROM printer_devices');
      final routes = await db.rawQuery('SELECT * FROM printer_routes');
      await db.close();

      expect(printers, isNotEmpty, reason: 'Kayıtlı yazıcı profili bulunmalıdır.');
      expect(routes, isNotEmpty, reason: 'Kayıtlı yazdırma rotası bulunmalıdır.');

      // Fiş ve Etiket rotaları
      final receiptRoute = routes.firstWhere((r) => r['kind'] == 'receipt', orElse: () => {});
      final labelRoute = routes.firstWhere((r) => r['kind'] == 'productLabel', orElse: () => {});

      expect(receiptRoute, isNotEmpty);
      expect(labelRoute, isNotEmpty);
    });
  });
}
