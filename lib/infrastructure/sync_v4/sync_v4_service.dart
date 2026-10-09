import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/barcode_standard.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_dtos.dart';
import 'package:serenutos/infrastructure/services/data_reset_service.dart';
import 'package:serenutos/infrastructure/services/product_image_peer_service.dart';

part 'sync_v4_service_orchestration.dart';
part 'sync_v4_service_recovery.dart';
part 'sync_v4_service_materializer.dart';

Future<void> _noopAsync() async {}

int _syncInt(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _syncDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

class SyncV4Result {
  const SyncV4Result({
    required this.pushed,
    required this.pulled,
    this.reconciled = 0,
    this.failed = 0,
    this.errors = const [],
    this.pulledEntityTypes = const {},
  });
  final int pushed;
  final int pulled;
  final int reconciled;
  final int failed;
  final List<String> errors;
  final Set<String> pulledEntityTypes;
  int get synced => pushed;
  bool get success => failed == 0 && errors.isEmpty;
}

/// Crash-safe, cursor based replication. WebSocket is deliberately optional:
/// correctness comes from this pull loop, not from a live connection.
class SyncV4Service {
  SyncV4Service(
    this._api, {
    Future<String> Function()? deviceActivationIdResolver,
    Future<String> Function()? deviceIdResolver,
    Future<void> Function()? productImageCleaner,
    Future<void> Function()? catalogSourceResetter,
    ProductImagePeerService? productImagePeerService,
    LicenseService? licenseService,
  })  : _deviceActivationIdResolver = deviceActivationIdResolver,
        _deviceIdResolver = deviceIdResolver,
        _productImageCleaner =
            productImageCleaner ?? DataResetService.clearProductImages,
        _catalogSourceResetter = catalogSourceResetter ?? _noopAsync,
        _productImagePeerService =
            productImagePeerService ?? ProductImagePeerService.instance,
        _licenseService = licenseService;
  final ApiClient _api;
  final Future<String> Function()? _deviceActivationIdResolver;
  final Future<String> Function()? _deviceIdResolver;
  final Future<void> Function() _productImageCleaner;
  final Future<void> Function() _catalogSourceResetter;
  final ProductImagePeerService _productImagePeerService;
  final LicenseService? _licenseService;
  static const _legacySnapshotKey = 'sync_v4_legacy_snapshot_v1';
  static const _unsyncedProductRecoveryKey =
      'sync_v4_unsynced_product_recovery_v1';
  static const _companyVersionKey = 'sync_v4_company_version';
  static const _companySyncedAtKey = 'sync_v4_company_synced_at';

  /// Permanently resets the tenant's operational data on the server, then
  /// applies the returned reset barrier locally. The server revision prevents
  /// stale offline mutations from resurrecting pre-reset data.
  Future<int> resetOperationalData() async {
    final deviceActivationId = await _deviceActivationId();
    final deviceId = await _deviceId();
    final response = await _api.post('/api/v4/sync/operational-reset', {
      'device_activation_id': deviceActivationId,
      'device_id': deviceId,
    });
    final body = Map<String, dynamic>.from(response.json as Map);
    final revision = _syncInt(body['reset_revision']);
    if (revision <= 0) throw StateError('invalid_operational_reset_revision');

    if (!kIsWeb) {
      final db = await DatabaseManager().getDatabase();
      await db.transaction((txn) async {
        await DataResetService.clearOperationalTables(txn);
        await txn.insert(
          'sync_cursor_v4',
          {'key': 'global', 'cursor': revision},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await _productImageCleaner();
    }
    return revision;
  }

  /// Resets only the tenant product catalogue on the server and applies the
  /// returned barrier locally. Sales, customers and financial history remain.
  Future<int> resetProductCatalog() async {
    final deviceActivationId = await _deviceActivationId();
    final deviceId = await _deviceId();
    final response = await _api.post('/api/v4/sync/catalog-reset', {
      'device_activation_id': deviceActivationId,
      'device_id': deviceId,
    });
    final body = Map<String, dynamic>.from(response.json as Map);
    final revision = _syncInt(body['reset_revision']);
    if (revision <= 0) throw StateError('invalid_catalog_reset_revision');

    if (!kIsWeb) {
      await DatabaseManager.waitForWriteLock();
      final db = await DatabaseManager().getDatabase();
      await DatabaseManager.retryOnLock(() async {
        await db.transaction((txn) async {
          await DataResetService.clearProductCatalog(txn);
          await txn.insert(
            'sync_cursor_v4',
            {'key': 'global', 'cursor': revision},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
      });
      await _catalogSourceResetter();
      await _productImageCleaner();
    }
    return revision;
  }

  Future<String> _deviceId() async {
    final resolver = _deviceIdResolver;
    if (resolver != null) return resolver();
    final prefs = await SharedPreferences.getInstance();
    return DeviceManager.resolveDeviceId(prefs);
  }

  Future<String> _deviceActivationId() async {
    final resolver = _deviceActivationIdResolver;
    if (resolver != null) return resolver();
    final licenseService = _licenseService;
    if (licenseService != null) {
      final activationId = licenseService.getLicenseInfo()?.activationId;
      if (activationId != null && activationId.isNotEmpty) {
        return activationId;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final activationId = LicenseService(prefs).getLicenseInfo()?.activationId;
    if (activationId == null || activationId.isEmpty) {
      throw StateError('active_device_activation_required');
    }
    return activationId;
  }
}
