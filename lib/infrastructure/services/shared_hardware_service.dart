import 'dart:async';
import 'dart:convert';

import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

class SharedHardwareDevice {
  final String id;
  final String name;
  final HardwareDeviceType type;
  final String connectionType;
  final String? language;
  final Map<String, Object?> capabilities;
  final bool online;
  final bool isLocal;
  final DateTime lastSeenAt;

  const SharedHardwareDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.connectionType,
    required this.capabilities,
    required this.online,
    required this.isLocal,
    required this.lastSeenAt,
    this.language,
  });

  factory SharedHardwareDevice.fromJson(Map<String, dynamic> json) =>
      SharedHardwareDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        type: HardwareDeviceType.values.byName(json['type'] as String),
        connectionType: json['connection_type'] as String,
        language: json['language'] as String?,
        capabilities: Map<String, Object?>.from(
          json['capabilities'] as Map? ?? const {},
        ),
        online: json['online'] == true,
        isLocal: json['is_local'] == true,
        lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
      );
}

class ClaimedHardwareJob {
  final String id;
  final String hardwareId;
  final String operation;
  final Map<String, dynamic> payload;

  const ClaimedHardwareJob({
    required this.id,
    required this.hardwareId,
    required this.operation,
    required this.payload,
  });

  factory ClaimedHardwareJob.fromJson(Map<String, dynamic> json) =>
      ClaimedHardwareJob(
        id: json['id'] as String,
        hardwareId: json['hardware_id'] as String,
        operation: json['operation'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
}

class SharedHardwareJobSummary {
  final String id;
  final String hardwareName;
  final String operation;
  final String state;
  final int attemptCount;
  final String? errorMessage;
  final DateTime createdAt;
  final bool requestedHere;
  final bool executedHere;

  const SharedHardwareJobSummary({
    required this.id,
    required this.hardwareName,
    required this.operation,
    required this.state,
    required this.attemptCount,
    required this.createdAt,
    required this.requestedHere,
    required this.executedHere,
    this.errorMessage,
  });

  factory SharedHardwareJobSummary.fromJson(Map<String, dynamic> json) =>
      SharedHardwareJobSummary(
        id: json['id'] as String,
        hardwareName: json['hardware_name'] as String,
        operation: json['operation'] as String,
        state: json['state'] as String,
        attemptCount: (json['attempt_count'] as num).toInt(),
        errorMessage: json['error_message'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        requestedHere: json['requested_here'] == true,
        executedHere: json['executed_here'] == true,
      );
}

/// Tenant-scoped API used by both requesters and the hardware-owner worker.
abstract interface class SharedHardwareJobGateway {
  Future<ClaimedHardwareJob?> claim();
  Future<void> markExecuting(String jobId);
  Future<void> reportResult(
    String jobId, {
    required String state,
    Map<String, Object?> result = const {},
    String? errorCode,
    String? errorMessage,
  });
}

class SharedHardwareService implements SharedHardwareJobGateway {
  final ApiClient _apiClient;
  final LicenseService _licenseService;

  const SharedHardwareService({
    required ApiClient apiClient,
    required LicenseService licenseService,
  })  : _apiClient = apiClient,
        _licenseService = licenseService;

  Map<String, dynamic>? get _identity {
    final license = _licenseService.getLicenseInfo();
    if (_apiClient.jwtToken?.isNotEmpty != true) {
      return null;
    }
    // activationId may be absent during trial or before first license sync;
    // deviceId alone is sufficient for shared-hardware API calls.
    final activationId = license?.activationId;
    final deviceId = license?.deviceId ?? _licenseService.getDeviceUuid();
    if (deviceId.isEmpty) {
      return null;
    }
    return {
      if (activationId?.isNotEmpty == true)
        'device_activation_id': activationId,
      'device_id': deviceId,
    };
  }

  Future<void> publishPresence(List<HardwareDevice> devices) async {
    final identity = _identity;
    if (identity == null) return;
    await _apiClient.put('/api/v4/sync/shared-hardware/presence', {
      ...identity,
      'hardware': devices.where((device) => device.enabled).map((device) {
        final json = device.toJson();
        final config = device.configuration;
        final capabilities = device.type == HardwareDeviceType.receiptPrinter
            ? <String, Object?>{
                'paperWidthMm': (config['paperWidth'] as num?)?.toInt() ?? 58,
                'printableWidthDots':
                    ((config['paperWidth'] as num?)?.toInt() ?? 58) <= 58
                        ? 384
                        : 576,
                'cutter': config['autoCut'] == true,
                'cashDrawer': config['openDrawer'] == true,
              }
            : device.type == HardwareDeviceType.labelPrinter
                ? <String, Object?>{
                    'dpi': (config['dpi'] as num?)?.toInt() ?? 203,
                    'mediaWidthMm':
                        (config['labelWidthMm'] as num?)?.toInt() ?? 50,
                    'mediaHeightMm':
                        (config['labelHeightMm'] as num?)?.toInt() ?? 30,
                    'gapMm': (config['labelGapMm'] as num?)?.toInt() ?? 2,
                    'printableWidthDots':
                        (config['printableWidthDots'] as num?)?.toInt() ?? 384,
                  }
                : const <String, Object?>{};
        return {
          ...json,
          'sharing_scope':
              device.configuration['sharingScope']?.toString() ?? 'company',
          'language': device.type == HardwareDeviceType.receiptPrinter
              ? 'escPos'
              : device.type == HardwareDeviceType.labelPrinter
                  ? (device.configuration['language']?.toString() ?? 'tspl')
                  : null,
          'capabilities': capabilities,
        };
      }).toList(growable: false),
    });
  }

  Future<List<SharedHardwareDevice>> list() async {
    final identity = _identity;
    if (identity == null) return const [];
    final response = await _apiClient.post(
      '/api/v4/sync/shared-hardware/list',
      identity,
    );
    final body = Map<String, dynamic>.from(response.json as Map);
    return (body['hardware'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => SharedHardwareDevice.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<String> queuePrint({
    required String hardwareId,
    required String operation,
    required List<int> bytes,
    required int copies,
    required String idempotencyKey,
  }) async {
    final identity = _identity;
    if (identity == null) {
      throw StateError('Ortak yazıcı için aktif oturum gerekli.');
    }
    final response = await _apiClient.post(
      '/api/v4/sync/hardware-jobs',
      {
        ...identity,
        'hardware_id': hardwareId,
        'operation': operation,
        'idempotency_key': idempotencyKey,
        'payload': {'bytes_base64': base64Encode(bytes), 'copies': copies},
      },
      idempotencyKey: idempotencyKey,
    );
    final body = Map<String, dynamic>.from(response.json as Map);
    return (body['job'] as Map)['id'] as String;
  }

  @override
  Future<ClaimedHardwareJob?> claim() async {
    final identity = _identity;
    if (identity == null) return null;
    final response = await _apiClient.post(
      '/api/v4/sync/hardware-jobs/claim',
      identity,
    );
    final body = Map<String, dynamic>.from(response.json as Map);
    if (body['job'] is! Map) return null;
    return ClaimedHardwareJob.fromJson(
      Map<String, dynamic>.from(body['job'] as Map),
    );
  }

  Future<List<SharedHardwareJobSummary>> listJobs() async {
    final identity = _identity;
    if (identity == null) return const [];
    final response = await _apiClient.post(
      '/api/v4/sync/hardware-jobs/list',
      identity,
    );
    final body = Map<String, dynamic>.from(response.json as Map);
    return (body['jobs'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => SharedHardwareJobSummary.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<void> actOnJob(String jobId, String action) async {
    final identity = _identity;
    if (identity == null) throw StateError('Donanım işi kimliği bulunamadı.');
    await _apiClient.post('/api/v4/sync/hardware-jobs/$jobId/action', {
      ...identity,
      'action': action,
    });
  }

  @override
  Future<void> markExecuting(String jobId) async {
    final identity = _identity;
    if (identity == null) throw StateError('Donanım işi kimliği bulunamadı.');
    await _apiClient.post(
      '/api/v4/sync/hardware-jobs/$jobId/start',
      identity,
    );
  }

  @override
  Future<void> reportResult(
    String jobId, {
    required String state,
    Map<String, Object?> result = const {},
    String? errorCode,
    String? errorMessage,
  }) async {
    final identity = _identity;
    if (identity == null) throw StateError('Donanım işi kimliği bulunamadı.');
    await _apiClient.post('/api/v4/sync/hardware-jobs/$jobId/result', {
      ...identity,
      'state': state,
      'result': result,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
    });
  }
}

class SharedHardwarePresenceRuntime {
  final SharedHardwareService service;
  final Future<List<HardwareDevice>> Function() loadDevices;
  final Duration interval;
  Timer? _timer;
  bool _running = false;

  SharedHardwarePresenceRuntime({
    required this.service,
    required this.loadDevices,
    this.interval = const Duration(minutes: 1),
  });

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(publishNow()));
    unawaited(publishNow());
  }

  Future<void> publishNow() async {
    if (_running) return;
    _running = true;
    try {
      final devices = await loadDevices();
      await service.publishPresence(devices
          .where((item) => item.connectionType != HardwareConnectionType.cloud)
          .toList(growable: false));
    } catch (_) {
      // Offline is normal; the durable local registry is retried next cycle.
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
