// test/core_next/stage10_12_94_live_backup_delta_and_pilot_test.dart
// SERENUT OS — STAGE 10.12.94
// Nutopia Taze Canlı Yedekleme, Delta Analizi, Mutabakat ve Kontrollü Pilot Testi

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_product_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_financial_transaction_repository.dart';

String computeSha256(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) return 'NOT_FOUND';
  final bytes = file.readAsBytesSync();
  return sha256.convert(bytes).toString().toUpperCase();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const nutopiaMerchantId = 'comp-1785241628448-c7f5677d';
  const erkulMerchantId = 'comp-1791194455402-bdc6d8d1';

  final roaming = Platform.environment['APPDATA'] ?? '';
  final liveAppDir = p.join(roaming, 'Serenut OS Software Technologies A.Ş', 'Serenut OS');
  final liveLegacyPath = p.join(liveAppDir, 'databases', 'serenut_pos.db');
  final liveCorePath = p.join(liveAppDir, 'databases', 'serenut_core_v2.db');
  final liveCoreSubPath = p.join(liveAppDir, 'databases', 'core_next', 'serenut_core_v2.db');
  final livePrefsPath = p.join(liveAppDir, 'shared_preferences.json');

  final stage84BackupPath = p.join(Directory.current.path, 'backups', 'nutopia_pre_cutover_20261021_stage84', 'serenut_pos_live_backup.db');
  final targetBackupDir = Directory(p.join(Directory.current.path, 'backups', 'nutopia_live_20261022_stage94'));
  if (!targetBackupDir.existsSync()) {
    targetBackupDir.createSync(recursive: true);
  }

  group('STAGE 10.12.94: Nutopia Canlı Yedek, Delta ve Kontrollü Pilot', () {
    test('1. Taze Canlı Yedekleme ve WAL Checkpoint', () async {
      print('\n================================================================');
      print('🚀 [STAGE 10.12.94] NUTOPIA TAZE CANLI YEDEKLEME BAŞLADI');
      print('================================================================');

      final newBackupLegacyPath = p.join(targetBackupDir.path, 'serenut_pos_live_backup.db');
      final newBackupPrefsPath = p.join(targetBackupDir.path, 'shared_preferences_pre_cutover.json');

      for (final ext in ['', '-wal', '-shm']) {
        final src = File('$liveLegacyPath$ext');
        if (src.existsSync()) {
          src.copySync('$newBackupLegacyPath$ext');
          print('  [KOPYALANDI] serenut_pos.db$ext (${src.lengthSync()} bayt)');
        }
      }

      if (File(livePrefsPath).existsSync()) {
        File(livePrefsPath).copySync(newBackupPrefsPath);
        print('  [KOPYALANDI] shared_preferences.json (${File(livePrefsPath).lengthSync()} bayt)');
      }

      // Yedek üzerinde WAL Checkpoint yap
      final backupDb = await databaseFactory.openDatabase(newBackupLegacyPath);
      await backupDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
      final integrityRes = await backupDb.rawQuery('PRAGMA integrity_check;');
      final fkRes = await backupDb.rawQuery('PRAGMA foreign_key_check;');
      await backupDb.close();

      final newBackupSha256 = computeSha256(newBackupLegacyPath);
      final newBackupSize = File(newBackupLegacyPath).lengthSync();
      final stage84Sha256 = computeSha256(stage84BackupPath);

      print('  Yeni Yedek SHA-256 : $newBackupSha256 ($newBackupSize bayt)');
      print('  Stage 84 SHA-256   : $stage84Sha256');
      print('  Bütünlük Testi     : ${integrityRes.first.values.first}');
      print('  FK İhlalleri       : ${fkRes.length}');
      print('  Stage 84 Farkı     : ${newBackupSha256 != stage84Sha256 ? "FARKLI (YENİ HAREKETLER MEVCUT)" : "BİREBİR AYNI"}');

      expect(integrityRes.first.values.first, equals('ok'));
      expect(fkRes.isEmpty, isTrue);
    });

    test('2. Canlı Delta Tespiti ve Hedefe Güvenli Eşitleme', () async {
      print('\n================================================================');
      print('🚀 [STAGE 10.12.94] CANLI DELTA TESPİTİ VE HEDEFE EŞİTLEME');
      print('================================================================');

      final newBackupLegacyPath = p.join(targetBackupDir.path, 'serenut_pos_live_backup.db');
      final legDb = await databaseFactory.openDatabase(newBackupLegacyPath, options: OpenDatabaseOptions(readOnly: true));

      final recentSales = await legDb.rawQuery(
        'SELECT id, invoice_number, total_amount, payment_type, customer_id, created_at FROM sales ORDER BY created_at DESC LIMIT 5;'
      );
      print('  Legacy Son Satışlar:');
      for (final s in recentSales) {
        print('    Satış: ${s['id']} | Fatura: ${s['invoice_number']} | Tutar: ${s['total_amount']} TL | Ödeme: ${s['payment_type']} | Tarih: ${s['created_at']} | Cari: ${s['customer_id']}');
      }

      final post21Sales = await legDb.rawQuery(
        "SELECT id, total_amount, payment_type, customer_id, created_at FROM sales WHERE created_at >= '2026-10-21';"
      );
      print('  21 Ekim Sonrası Toplam Satış Sayısı: ${post21Sales.length}');

      final coreDb = await databaseFactory.openDatabase(liveCorePath);
      int migratedDeltaSales = 0;

      for (final s in post21Sales) {
        final saleId = s['id']?.toString() ?? '';
        final existsInCore = await coreDb.rawQuery('SELECT id FROM sales WHERE id = ?;', [saleId]);
        if (existsInCore.isEmpty) {
          final totalAmount = (s['total_amount'] as num?)?.toDouble() ?? 0.0;
          final totalCents = (totalAmount * 100).round();
          final createdAtStr = s['created_at']?.toString() ?? DateTime.now().toIso8601String();
          final createdAtMs = DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
          final customerId = s['customer_id']?.toString();

          await coreDb.insert('sales', {
            'id': saleId,
            'tenant_id': 'nutopia',
            'customer_id': customerId,
            'total_amount_cents': totalCents,
            'final_amount_cents': totalCents,
            'total_cents': totalCents,
            'payment_type': s['payment_type']?.toString() ?? 'CASH',
            'status': 'COMPLETED',
            'created_at': createdAtMs,
            'updated_at': createdAtMs,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);

          final items = await legDb.rawQuery('SELECT * FROM sale_items WHERE sale_id = ?;', [saleId]);
          for (final item in items) {
            final itemId = item['id']?.toString() ?? 'item-$saleId';
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
            final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            await coreDb.insert('sale_items', {
              'id': itemId,
              'sale_id': saleId,
              'product_id': item['product_id']?.toString(),
              'quantity': qty,
              'unit_price_cents': (price * 100).round(),
              'total_cents': (price * qty * 100).round(),
              'created_at': createdAtMs,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }

          await coreDb.insert('sale_payments', {
            'id': 'pay-$saleId',
            'sale_id': saleId,
            'payment_type': s['payment_type']?.toString() ?? 'CASH',
            'amount_cents': totalCents,
            'created_at': createdAtMs,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);

          migratedDeltaSales++;
          print('  [DELTA MIGRATED] Satış aktarıldı: $saleId ($totalAmount TL)');
        }
      }
      print('  Yeni aktarılan delta satış: $migratedDeltaSales');

      // Alt DB kopyasını senkronize et
      if (File(liveCoreSubPath).existsSync()) {
        File(liveCorePath).copySync(liveCoreSubPath);
      }

      // Mutabakat
      final coreProdCount = (await coreDb.rawQuery('SELECT COUNT(*) FROM products;')).first.values.first as int;
      final coreCustCount = (await coreDb.rawQuery('SELECT COUNT(*) FROM customers;')).first.values.first as int;
      final coreSaleCount = (await coreDb.rawQuery('SELECT COUNT(*) FROM sales;')).first.values.first as int;
      final coreLedgerCount = (await coreDb.rawQuery('SELECT COUNT(*) FROM ledger_entries;')).first.values.first as int;
      final coreStockSum = (await coreDb.rawQuery('SELECT COALESCE(SUM(stock_quantity), 0.0) FROM products;')).first.values.first as num;
      final coreCustBalCents = (await coreDb.rawQuery('SELECT COALESCE(SUM(balance_cents), 0) FROM customers;')).first.values.first as int;

      print('\n  Mutabakat Sonuçları:');
      print('    Ürün Sayısı     : $coreProdCount');
      print('    Toplam Stok     : ${coreStockSum.toDouble().toStringAsFixed(2)} birim');
      print('    Müşteri Sayısı  : $coreCustCount');
      print('    Müşteri Bakiye  : ${(coreCustBalCents / 100.0).toStringAsFixed(2)} TL ($coreCustBalCents kuruş)');
      print('    Satış Sayısı    : $coreSaleCount');
      print('    Defter Hareketi : $coreLedgerCount');

      // app_settings legacy_migration_completed mühürle
      await coreDb.insert('app_settings', {
        'key': 'legacy_migration_completed',
        'value': 'true',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreDb.close();
      await legDb.close();

      expect(coreProdCount, greaterThanOrEqualTo(37682));
      expect(coreCustCount, greaterThanOrEqualTo(619));
      expect(coreSaleCount, greaterThanOrEqualTo(52));
    });

    test('3. Bootstrap State ve Runtime Pilot Gate Doğrulaması', () async {
      print('\n================================================================');
      print('🚀 [STAGE 10.12.94] BOOTSTRAP VE RUNTIME PİLOT GATE DOĞRULAMASI');
      print('================================================================');

      final newBackupLegacyPath = p.join(targetBackupDir.path, 'serenut_pos_live_backup.db');

      // Canlı preferences dosyasını güncelle
      final prefsFile = File(livePrefsPath);
      Map<String, dynamic> prefsJson = {};
      if (prefsFile.existsSync()) {
        prefsJson = jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;
      }

      prefsJson['flutter.core_next_pilot_enabled'] = true;
      prefsJson['flutter.core_next_kill_switch'] = false;
      prefsJson['flutter.core_next_bootstrap_migration_state'] = 'completed';
      prefsJson['flutter.core_next_migration_completed_at'] = DateTime.now().toIso8601String();
      prefsJson['flutter.core_next_migration_backup_path'] = newBackupLegacyPath;
      prefsJson['flutter.last_backup_date'] = DateTime.now().toIso8601String();

      prefsFile.writeAsStringSync(jsonEncode(prefsJson));
      print('  [GÜNCELLENDİ] shared_preferences.json mühürlendi.');

      SharedPreferences.setMockInitialValues({
        'core_next_pilot_enabled': true,
        'core_next_kill_switch': false,
        'core_next_bootstrap_migration_state': 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
        'core_next_migration_backup_path': newBackupLegacyPath,
      });

      DatabaseManager.overrideDatabasePath = liveLegacyPath;
      DatabaseManager.overrideCoreNextDatabasePath = liveCorePath;

      final bootstrap = await AppBootstrap.initPreApp(
        requestedTenantId: nutopiaMerchantId,
      );

      final pilotResult = bootstrap.pilotGateResult;
      print('  PilotGate Değerlendirmesi:');
      print('    isPilotActive: ${pilotResult?.isPilotActive}');
      print('    status: ${pilotResult?.status}');
      print('    targetDbPath: ${pilotResult?.targetDbPath}');
      print('    reason: ${pilotResult?.reason}');

      expect(pilotResult?.isPilotActive, isTrue);
      expect(pilotResult?.status, equals(PilotGateStatus.pilotActiveApproved));
      expect(pilotResult?.targetDbPath, equals(liveCorePath));

      final container = ProviderContainer(
        overrides: bootstrap.overrides,
        observers: bootstrap.observers,
      );

      final productRepo = await container.read(productRepositoryProvider.future);
      final customerRepo = await container.read(customerRepositoryProvider.future);
      final financialRepo = await container.read(financialTransactionRepositoryProvider.future);
      final saleRepo = await container.read(saleRepositoryProvider.future);

      print('\n  Gerçek Repository Türleri:');
      print('    Product Repo   : ${productRepo.runtimeType}');
      print('    Customer Repo  : ${customerRepo.runtimeType}');
      print('    Financial Repo : ${financialRepo.runtimeType}');
      print('    Sale Repo      : ${saleRepo.runtimeType}');

      expect(productRepo.runtimeType, equals(CoreNextProductRepository));
      expect(customerRepo.runtimeType, equals(CoreNextCustomerRepository));
      expect(financialRepo.runtimeType, equals(CoreNextFinancialTransactionRepository));
      expect(saleRepo.runtimeType, equals(SqliteSaleRepository));

      // Erkul Çeyiz Çapraz Erişim Engeli
      final erkulBootstrap = await AppBootstrap.initPreApp(
        requestedTenantId: erkulMerchantId,
      );
      final erkulResult = erkulBootstrap.pilotGateResult;
      print('\n  Erkul Çeyiz Çapraz Erişim Engeli (Fail-Closed):');
      print('    Erkul isPilotActive: ${erkulResult?.isPilotActive}');
      print('    Erkul status: ${erkulResult?.status}');

      expect(erkulResult?.isPilotActive, isFalse);
      expect(erkulResult?.status, equals(PilotGateStatus.blockedTenantMismatch));

      // Adli Kanıt Kaydı
      final evidence = {
        'stage': '10.12.94',
        'timestamp': DateTime.now().toIso8601String(),
        'pilotActive': pilotResult?.isPilotActive,
        'pilotStatus': pilotResult?.status.toString(),
        'targetDbPath': pilotResult?.targetDbPath,
        'productRepoType': productRepo.runtimeType.toString(),
        'customerRepoType': customerRepo.runtimeType.toString(),
        'financialRepoType': financialRepo.runtimeType.toString(),
        'saleRepoType': saleRepo.runtimeType.toString(),
        'erkulPilotActive': erkulResult?.isPilotActive,
        'erkulStatus': erkulResult?.status.toString(),
      };

      final evidenceFile = File(p.join(targetBackupDir.path, 'stage94_cutover_result.json'));
      evidenceFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));
      print('\n✅ Adli kanıt dosyası yazıldı: ${evidenceFile.path}');
    });
  });
}
