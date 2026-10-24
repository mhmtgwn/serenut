// test/core_next/stage10_12_72_nutopia_orchestrator_test.dart
// STAGE 10.12.72: Nutopia Cutover Orchestrator Safety and Failure Paths Unit Test
// Bu test yalnızca geçici (systemTemp) izole dizinlerde çalışır.
// Hiçbir canlı veya dondurulmuş yedek dosyasına dokunmaz.
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart';
import '../../core_next/client_core/lib/infrastructure/migration/nutopia_cutover_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late CutoffMaintenanceLock cutoffLock;
  late NutopiaCutoverOrchestrator orchestrator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nutopia_orch_test_');
    cutoffLock = CutoffMaintenanceLock();
    orchestrator = NutopiaCutoverOrchestrator(
      cutoffMaintenanceLock: cutoffLock,
      dbFactory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    if (cutoffLock.state.isLockActive) {
      await cutoffLock.releaseLock();
    }
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('STAGE 10.12.72: Nutopia Cutover Orchestrator Güvenlik ve Hata Yolları', () {
    test('Güvenlik 1: Nutopia dışındaki tenant (örn. serenut, erkul) kesinlikle reddedilir', () async {
      final options = NutopiaCutoverExecutionOptions(
        tenantId: 'serenut',
        legacyDbPath: '${tempDir.path}/legacy.db',
        targetCoreDbPath: '${tempDir.path}/core.db',
        isDryRun: true,
      );

      final result = await orchestrator.executeCutover(options);
      expect(result.isSuccess, isFalse);
      expect(result.finalStage, equals(NutopiaCutoverStage.failedBlocked));
      expect(result.errorMessage, contains('yalnızca "nutopia" kiracısı için yetkilidir'));
      expect(cutoffLock.state.phase, equals(CutoffMaintenancePhase.idle));
    });

    test('Güvenlik 2: Kaynak veya hedef dosya eksikse işlem güvenle durdurulur', () async {
      final options = NutopiaCutoverExecutionOptions(
        tenantId: 'nutopia',
        legacyDbPath: '${tempDir.path}/non_existent_legacy.db',
        targetCoreDbPath: '${tempDir.path}/non_existent_core.db',
        isDryRun: true,
      );

      final result = await orchestrator.executeCutover(options);
      expect(result.isSuccess, isFalse);
      expect(result.finalStage, equals(NutopiaCutoverStage.failedBlocked));
      expect(result.errorMessage, contains('bulunamadı'));
      expect(cutoffLock.state.phase, equals(CutoffMaintenancePhase.idle));
    });

    test('Güvenlik 3: Kilit başka bir kiracıda ise veya alınamazsa aktarım başlatılmaz', () async {
      // Kilidi önceden başka bir tenant için meşgul edelim
      await cutoffLock.acquireLock(tenantId: 'other_tenant');

      final options = NutopiaCutoverExecutionOptions(
        tenantId: 'nutopia',
        legacyDbPath: '${tempDir.path}/legacy.db',
        targetCoreDbPath: '${tempDir.path}/core.db',
        isDryRun: true,
      );

      // Dosyaları oluşturalım ki dosya kontrolünü geçsin
      final legFile = File(options.legacyDbPath);
      final tgtFile = File(options.targetCoreDbPath);
      await legFile.writeAsBytes(List.filled(1024, 0));
      await tgtFile.writeAsBytes(List.filled(1024, 0));

      // Ancak SQLite integrity hatasından önce dosya kontrolünü geçmeli
      final result = await orchestrator.executeCutover(options);
      expect(result.isSuccess, isFalse);
      expect(result.finalStage, equals(NutopiaCutoverStage.failedBlocked));
    });

    test('Güvenlik 4: Yetkisiz canlı aktivasyon talebi (hatalı/eksik anahtar) kesin olarak durdurulur', () async {
      // Sahte boş DB dosyaları oluşturalım
      final legPath = '${tempDir.path}/legacy.db';
      final tgtPath = '${tempDir.path}/core.db';

      final legDb = await databaseFactoryFfi.openDatabase(legPath);
      await legDb.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
      await legDb.insert('settings', {'key': 'business_name', 'value': 'Nutopia Fındık Değirmeni'});
      await legDb.close();

      // Hedef DB'yi CoreAppDatabase olarak hazırlayalım
      final tgtFile = File(tgtPath);
      await tgtFile.writeAsBytes(List.filled(1024, 0));

      final options = NutopiaCutoverExecutionOptions(
        tenantId: 'nutopia',
        legacyDbPath: legPath,
        targetCoreDbPath: tgtPath,
        isDryRun: false, // Canlı mod talep edilmiş ancak yetki anahtarı YOK
        liveExecutionAuthorizationKey: 'WRONG_KEY',
      );

      final result = await orchestrator.executeCutover(options);
      expect(result.isSuccess, isFalse);
      expect(result.finalStage, equals(NutopiaCutoverStage.failedBlocked));
    });
  });
}
