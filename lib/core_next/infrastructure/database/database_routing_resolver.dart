import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/services/tenant_identity_resolver.dart';

enum RoutingDecision {
  targetSelected,
  legacyFallback,
  blockedFailClosed,
}

class DatabaseRoutingResult {
  final RoutingDecision decision;
  final String resolvedPath;
  final String reason;
  final bool isTargetSelected;

  const DatabaseRoutingResult({
    required this.decision,
    required this.resolvedPath,
    required this.reason,
    required this.isTargetSelected,
  });

  @override
  String toString() =>
      'DatabaseRoutingResult(decision: $decision, path: $resolvedPath, reason: $reason)';
}

class UnsafeRollbackException implements Exception {
  final String message;
  const UnsafeRollbackException(this.message);
  @override
  String toString() => 'UnsafeRollbackException: $message';
}

class DatabaseRoutingResolver {
  static const int expectedCoreNextSchemaVersion = 7;

  const DatabaseRoutingResolver();

  /// Güvenli Veritabanı Yönlendirme Çözücüsü
  /// 
  /// Kurallar:
  /// 1. Asla hedef dosya yokken boş DB açmaz (legacy fallback).
  /// 2. Tenant ID veya Company ID uyuşmazlığında fail-closed durdurur.
  /// 3. PRAGMA integrity_check ve şema sürümünü doğrular.
  /// 4. Göç tamamlanmadıysa hedef dosyayı seçmez.
  /// 5. Yeni DB'ye işlem yazıldıktan sonra sessiz geri dönüşü (silent rollback) KESİNLİKLE ENGELLER.
  Future<DatabaseRoutingResult> resolve({
    required String requestedTenantId,
    required String legacyDbPath,
    String? targetDbPath,
    bool migrationStateCompleted = false,
    DatabaseFactory? dbFactory,
  }) async {
    final factory = dbFactory ?? databaseFactoryFfi;

    // 1. Hedef dosya yolu tanımlı değilse doğrudan Legacy
    if (targetDbPath == null || targetDbPath.trim().isEmpty) {
      return DatabaseRoutingResult(
        decision: RoutingDecision.legacyFallback,
        resolvedPath: legacyDbPath,
        reason: 'Hedef Core Next dosya yolu tanımlı değil.',
        isTargetSelected: false,
      );
    }

    final targetFile = File(targetDbPath);

    // 2. Hedef dosya diskte fiziksel olarak yoksa -> ASLA boş dosya oluşturma!
    if (!targetFile.existsSync()) {
      return DatabaseRoutingResult(
        decision: RoutingDecision.legacyFallback,
        resolvedPath: legacyDbPath,
        reason: 'Hedef dosya diskte bulunamadı. Boş DB oluşturulması engellendi.',
        isTargetSelected: false,
      );
    }

    // 3. Hedef dosya boş veya SQLite header boyutu (< 512 bayt) altındaysa
    if (targetFile.lengthSync() < 512) {
      return DatabaseRoutingResult(
        decision: RoutingDecision.blockedFailClosed,
        resolvedPath: legacyDbPath,
        reason: 'Hedef dosya bozuk veya 0 bayt.',
        isTargetSelected: false,
      );
    }

    // 4. Göç tamamlanmamışsa hedef DB açılamaz
    if (!migrationStateCompleted) {
      return DatabaseRoutingResult(
        decision: RoutingDecision.legacyFallback,
        resolvedPath: legacyDbPath,
        reason: 'Migration durumu tamamlanmadı (inProgress veya notStarted).',
        isTargetSelected: false,
      );
    }

    // 5. Hedef veritabanını salt-okunur açarak bütünlük ve tenant doğrulaması yap
    Database? targetDb;
    try {
      targetDb = await factory.openDatabase(
        targetDbPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      // A) PRAGMA Bütünlük Kontrolü
      final integrity = await targetDb.rawQuery('PRAGMA integrity_check;');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        return DatabaseRoutingResult(
          decision: RoutingDecision.blockedFailClosed,
          resolvedPath: legacyDbPath,
          reason: 'Hedef DB PRAGMA integrity_check bütünlük testini geçemedi.',
          isTargetSelected: false,
        );
      }

      // B) Şema Sürüm Kontrolü (v3 ve v4 desteklenir; v3 otomatik olarak v4'e yükseltilir)
      final versionRes = await targetDb.rawQuery('PRAGMA user_version;');
      final userVersion = (versionRes.first.values.first as num?)?.toInt() ?? 0;
      if (userVersion < 3 || userVersion > expectedCoreNextSchemaVersion) {
        return DatabaseRoutingResult(
          decision: RoutingDecision.blockedFailClosed,
          resolvedPath: legacyDbPath,
          reason: 'Hedef DB şema sürümü uyumsuz ($userVersion not in 3..$expectedCoreNextSchemaVersion).',
          isTargetSelected: false,
        );
      }

      // C) Tenant ID / Company ID Doğrulaması
      final tables = (await targetDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'",
      )).toList();

      if (tables.isNotEmpty) {
        final tenantRow = await targetDb.query(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['tenant_id'],
        );
        if (tenantRow.isNotEmpty) {
          final dbTenantId = tenantRow.first['value']?.toString().trim();
          if (!TenantIdentityResolver.matches(
            requestedTenantId: requestedTenantId,
            dbTenantId: dbTenantId,
          )) {
            return DatabaseRoutingResult(
              decision: RoutingDecision.blockedFailClosed,
              resolvedPath: legacyDbPath,
              reason: 'Tenant ID uyuşmazlığı: İstenen "$requestedTenantId" != DB "$dbTenantId".',
              isTargetSelected: false,
            );
          }
        }

        // Canlı mutabakat durumu kontrolü (blocked veya diverged durumunda hedef açılamaz)
        final cutoverRow = await targetDb.query(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['cutover_reconciliation_status'],
        );
        if (cutoverRow.isNotEmpty) {
          final cutoverStatus = cutoverRow.first['value']?.toString();
          if (cutoverStatus == 'blocked' || cutoverStatus == 'diverged') {
            return DatabaseRoutingResult(
              decision: RoutingDecision.legacyFallback,
              resolvedPath: legacyDbPath,
              reason: 'Canlı işlem mutabakatı engellendi (durum: $cutoverStatus). Güvenlik gereği Legacy veritabanı korunuyor.',
              isTargetSelected: false,
            );
          }
        }
      }

      // D) Gerekli kritik tabloların varlığı
      final existingTables = (await targetDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'].toString()).toSet();

      const requiredTables = {'products', 'customers', 'sales', 'ledger_entries', 'sync_events'};
      if (!requiredTables.every(existingTables.contains)) {
        return DatabaseRoutingResult(
          decision: RoutingDecision.blockedFailClosed,
          resolvedPath: legacyDbPath,
          reason: 'Hedef DB kritik Core Next tablolarını içermiyor.',
          isTargetSelected: false,
        );
      }

      // E) Başarılı yönlendirme
      return DatabaseRoutingResult(
        decision: RoutingDecision.targetSelected,
        resolvedPath: targetDbPath,
        reason: 'Triple-Check ve Tenant doğrulaması başarılı.',
        isTargetSelected: true,
      );
    } catch (e) {
      return DatabaseRoutingResult(
        decision: RoutingDecision.blockedFailClosed,
        resolvedPath: legacyDbPath,
        reason: 'Hedef DB doğrulama hatası: $e',
        isTargetSelected: false,
      );
    } finally {
      if (targetDb != null && targetDb.isOpen) {
        await targetDb.close();
      }
    }
  }

  /// Yeni DB'ye işlem yazıldıktan sonra sessiz geri dönüş yapılabilir mi denetler.
  /// 
  /// Eğer hedef veritabanında göç sonrası yeni bir satış veya defter kaydı oluşmuşsa,
  /// eski sisteme geri dönmek bu yeni kayıtların görünmez olmasına yol açar.
  /// Bu durumda açıkça [UnsafeRollbackException] fırlatılır!
  Future<void> assertSafeRollback({
    required Database targetDb,
    required int initialMigrationCutoffTimestamp,
  }) async {
    // 1. Yeni satış kontrolü
    final newSales = await targetDb.rawQuery(
      'SELECT COUNT(*) as c FROM sales WHERE created_at > ?',
      [initialMigrationCutoffTimestamp],
    );
    final saleCount = (newSales.first['c'] as num?)?.toInt() ?? 0;

    // 2. Yeni defter/cari hareket kontrolü
    int ledgerCount = 0;
    final ledgerTable = await targetDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='ledger_entries'",
    );
    if (ledgerTable.isNotEmpty) {
      final newLedger = await targetDb.rawQuery(
        'SELECT COUNT(*) as c FROM ledger_entries WHERE created_at > ?',
        [initialMigrationCutoffTimestamp],
      );
      ledgerCount = (newLedger.first['c'] as num?)?.toInt() ?? 0;
    }

    // 3. Yeni kasa hareketi kontrolü
    int cashCount = 0;
    final cashTable = await targetDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='cash_transactions'",
    );
    if (cashTable.isNotEmpty) {
      final newCash = await targetDb.rawQuery(
        'SELECT COUNT(*) as c FROM cash_transactions WHERE created_at > ?',
        [initialMigrationCutoffTimestamp],
      );
      cashCount = (newCash.first['c'] as num?)?.toInt() ?? 0;
    }

    final totalNewFinancial = saleCount + ledgerCount + cashCount;
    if (totalNewFinancial > 0) {
      throw UnsafeRollbackException(
        'Yeni veritabanında $totalNewFinancial adet yeni işlem '
        '(yeni satış: $saleCount, yeni cari/defter: $ledgerCount, yeni kasa: $cashCount, Satış: $saleCount, Cari/Defter: $ledgerCount, Kasa: $cashCount) kaydedilmiş! '
        'Sessiz geri dönüş yeni kayıtların kaybolmasına neden olur. İşlem durduruldu.',
      );
    }
  }
}
