// test/core_next/stage10_12_87_desktop_runner.dart
// SERENUT OS — STAGE 10.12.87
// Gerçek Masaüstü Windows Uygulaması İzole Test Başlatıcısı (Isolated Desktop Test Launcher)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/main.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_product_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_financial_transaction_repository.dart';

class IsolatedPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String isolatedBaseDir;
  IsolatedPathProviderPlatform(this.isolatedBaseDir);

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(isolatedBaseDir, 'documents');

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(isolatedBaseDir, 'support');

  @override
  Future<String?> getTemporaryPath() async =>
      p.join(isolatedBaseDir, 'temp');

  @override
  Future<String?> getLibraryPath() async =>
      p.join(isolatedBaseDir, 'library');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sandboxDir = Platform.environment['SERENUT_ISOLATED_SANDBOX_DIR'] ??
      p.join(Platform.environment['LOCALAPPDATA'] ?? r'C:\Temp', 'Temp', 'serenut_desktop_sandbox_87');

  final appDataDir = Platform.environment['APPDATA'] ?? '';
  if (appDataDir.isNotEmpty && sandboxDir.toLowerCase().contains(appDataDir.toLowerCase())) {
    stderr.writeln('[FATAL SECURITY BREACH] Sandbox directory cannot be inside APPDATA! Aborting.');
    exit(1);
  }

  final sandboxFileDir = Directory(sandboxDir);
  if (!sandboxFileDir.existsSync()) {
    stderr.writeln('[FATAL] Sandbox directory does not exist: $sandboxDir');
    exit(1);
  }

  print('================================================================');
  print('🚀 [STAGE 10.12.87] SERENUT OS İZOLE MASAÜSTÜ TEST RUNTIME BAŞLATILDI');
  print('   Sandbox Dizin: $sandboxDir');
  print('================================================================');

  // 1. PathProvider platformunu sandbox'a kitle
  PathProviderPlatform.instance = IsolatedPathProviderPlatform(sandboxDir);

  // 2. DatabaseManager override yollarını sandbox'a yönlendir
  final isolatedLegacyPath = p.join(sandboxDir, 'databases', 'serenut_pos.db');
  final isolatedCoreNextPath = p.join(sandboxDir, 'databases', 'serenut_core_v2.db');
  final isolatedBackupPath = p.join(sandboxDir, 'backups', 'serenut_pos_backup.db');

  DatabaseManager.overrideDatabasePath = isolatedLegacyPath;
  DatabaseManager.overrideCoreNextDatabasePath = isolatedCoreNextPath;

  // 3. SharedPreferences mock initial values
  SharedPreferences.setMockInitialValues({
    'core_next_pilot_enabled': true,
    'core_next_kill_switch': false,
    'core_next_bootstrap_migration_state': 'completed',
    'last_backup_date': DateTime.now().toIso8601String(),
    'core_next_migration_backup_path': isolatedBackupPath,
  });

  // 4. AppBootstrap pre-app pipeline'ını Nutopia ile çalıştır
  const nutopiaMerchantId = 'comp-1785241628448-c7f5677d';
  const erkulMerchantId = 'comp-1791194455402-bdc6d8d1';

  final bootstrap = await AppBootstrap.initPreApp(
    requestedTenantId: nutopiaMerchantId,
  );

  final pilotResult = bootstrap.pilotGateResult;
  print('\n[DESKTOP_RUNTIME_PROOF] PILOT GATE DEĞERLENDİRME SONUCU:');
  print('  isPilotActive: ${pilotResult?.isPilotActive}');
  print('  status: ${pilotResult?.status}');
  print('  targetDbPath: ${pilotResult?.targetDbPath}');
  print('  reason: ${pilotResult?.reason}');

  // 5. ProviderContainer ile gerçek repository sınıflarını incele
  final container = ProviderContainer(
    overrides: bootstrap.overrides,
    observers: bootstrap.observers,
  );

  final productRepo = await container.read(productRepositoryProvider.future);
  final customerRepo = await container.read(customerRepositoryProvider.future);
  final financialRepo = await container.read(financialTransactionRepositoryProvider.future);
  final saleRepo = await container.read(saleRepositoryProvider.future);

  print('\n[DESKTOP_RUNTIME_PROOF] GERÇEK REPOSITORY SINIFLARI:');
  print('  Product Repository: ${productRepo.runtimeType}');
  print('  Customer Repository: ${customerRepo.runtimeType}');
  print('  Financial Repository: ${financialRepo.runtimeType}');
  print('  Sale Repository: ${saleRepo.runtimeType}');

  final activeProducts = await productRepo.findAll();
  final activeCustomers = await customerRepo.findAll();

  print('\n[DESKTOP_RUNTIME_PROOF] CORE NEXT VERİTABANINDAN OKUNAN VERİLER:');
  print('  Aktif Ürün Sayısı: ${activeProducts.length}');
  print('  Aktif Müşteri Sayısı: ${activeCustomers.length}');

  // 6. Erkul Çeyiz Çapraz Erişim Engeli Testi
  final erkulBootstrap = await AppBootstrap.initPreApp(
    requestedTenantId: erkulMerchantId,
  );
  final erkulResult = erkulBootstrap.pilotGateResult;
  print('\n[DESKTOP_RUNTIME_PROOF] ERKUL ÇEYİZ ÇAPRAZ ERİŞİM ENGELİ (FAIL-CLOSED):');
  print('  Erkul isPilotActive: ${erkulResult?.isPilotActive}');
  print('  Erkul status: ${erkulResult?.status}');

  final erkulContainer = ProviderContainer(
    overrides: erkulBootstrap.overrides,
    observers: erkulBootstrap.observers,
  );
  final erkulProductRepo = await erkulContainer.read(productRepositoryProvider.future);
  final erkulCustomerRepo = await erkulContainer.read(customerRepositoryProvider.future);
  print('  Erkul Product Repo: ${erkulProductRepo.runtimeType} (Legacy)');
  print('  Erkul Customer Repo: ${erkulCustomerRepo.runtimeType} (Legacy)');

  // 7. Doğrulama kanıtlarını dosyaya kaydet
  final verificationRecord = {
    'timestamp': DateTime.now().toIso8601String(),
    'stage': '10.12.87',
    'sandboxDir': sandboxDir,
    'pilotActive': pilotResult?.isPilotActive,
    'status': pilotResult?.status.toString(),
    'targetDbPath': pilotResult?.targetDbPath,
    'productRepoType': productRepo.runtimeType.toString(),
    'customerRepoType': customerRepo.runtimeType.toString(),
    'financialRepoType': financialRepo.runtimeType.toString(),
    'saleRepoType': saleRepo.runtimeType.toString(),
    'activeProductsCount': activeProducts.length,
    'activeCustomersCount': activeCustomers.length,
    'erkulPilotActive': erkulResult?.isPilotActive,
    'erkulStatus': erkulResult?.status.toString(),
    'erkulProductRepoType': erkulProductRepo.runtimeType.toString(),
    'erkulCustomerRepoType': erkulCustomerRepo.runtimeType.toString(),
  };

  final proofFile = File(p.join(sandboxDir, 'desktop_runtime_verification.json'));
  proofFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(verificationRecord));
  print('\n[DESKTOP_RUNTIME_PROOF] Adli kanıt dosyası yazıldı: ${proofFile.path}');

  // 8. 12 saniye sonra otomatik kapanacak şekilde zamanlayıcı kur (Hands-free temiz sonlanma)
  Timer(const Duration(seconds: 12), () {
    print('\n[DESKTOP_RUNTIME_PROOF] 12 saniyelik görsel masaüstü oturumu tamamlandı. Pencere güvenle kapatılıyor.');
    exit(0);
  });

  // 9. Gerçek Flutter masaüstü penceresini aç
  print('\n[DESKTOP_RUNTIME_PROOF] Flutter Windows masaüstü penceresi açılıyor...');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}
