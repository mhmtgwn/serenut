import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class PrintingConfigurationException implements Exception {
  final String message;

  const PrintingConfigurationException(this.message);

  @override
  String toString() => message;
}

class SqlitePrintingRepository implements PrintingRepository {
  static const _maxAttempts = 5;
  static const _uuid = Uuid();
  final DbGateway _gateway;

  const SqlitePrintingRepository(this._gateway);

  DbExecutor get _executor => _gateway;

  @override
  Future<List<PrintDesignProfile>> getDesignProfiles(
      PrintDocumentKind kind) async {
    final rows = await _executor.query(
      'print_design_profiles',
      where: 'kind = ?',
      whereArgs: [kind.name],
      orderBy: 'is_default DESC, name COLLATE NOCASE',
    );
    return rows.map(PrintDesignProfile.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveDesignProfile(PrintDesignProfile profile) async {
    await _gateway.transaction(() async {
      if (profile.isDefault) {
        await _executor.update(
          'print_design_profiles',
          {'is_default': 0},
          where: 'kind = ? AND id <> ?',
          whereArgs: [profile.kind.name, profile.id],
        );
      }
      await _executor.insert(
        'print_design_profiles',
        profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<List<PrinterDeviceProfile>> getDevices() async {
    final rows = await _executor.query(
      'printer_devices',
      orderBy: 'enabled DESC, name COLLATE NOCASE',
    );
    return rows.map(PrinterDeviceProfile.fromMap).toList(growable: false);
  }

  @override
  Future<PrinterDeviceProfile?> getDevice(String id) async {
    final rows = await _executor.query(
      'printer_devices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PrinterDeviceProfile.fromMap(rows.first);
  }

  @override
  Future<void> saveDevice(PrinterDeviceProfile device) async {
    await _executor.insert(
      'printer_devices',
      device.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteDevice(String id) async {
    final routes = await _executor.query(
      'printer_routes',
      columns: ['kind'],
      where: 'device_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (routes.isNotEmpty) {
      throw const PrintingConfigurationException(
        'Aktif bir yazdırma rotasında kullanılan cihaz silinemez.',
      );
    }
    await _executor.delete('printer_devices', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<PrinterRoute?> getRoute(PrintDocumentKind kind) async {
    final rows = await _executor.query(
      'printer_routes',
      where: 'kind = ?',
      whereArgs: [kind.name],
      limit: 1,
    );
    return rows.isEmpty ? null : PrinterRoute.fromMap(rows.first);
  }

  @override
  Future<void> saveRoute(PrinterRoute route) async {
    await _gateway.transaction(() async {
      final deviceRows = await _executor.query(
        'printer_devices',
        where: 'id = ? AND enabled = 1',
        whereArgs: [route.deviceId],
        limit: 1,
      );
      if (deviceRows.isEmpty) {
        throw const PrintingConfigurationException(
          'Rota için etkin bir yazıcı seçilmelidir.',
        );
      }
      final device = PrinterDeviceProfile.fromMap(deviceRows.first);
      final requiredLanguage = route.kind == PrintDocumentKind.receipt
          ? PrinterLanguage.escPos
          : PrinterLanguage.tspl;
      if (device.language != requiredLanguage) {
        throw PrintingConfigurationException(
          '${route.kind.name} işi ${device.language.name} cihazına yönlendirilemez.',
        );
      }
      final profileRows = await _executor.query(
        'print_design_profiles',
        where: 'id = ? AND kind = ?',
        whereArgs: [route.designProfileId, route.kind.name],
        limit: 1,
      );
      if (profileRows.isEmpty) {
        throw const PrintingConfigurationException(
          'Rota ile aynı türde bir tasarım profili seçilmelidir.',
        );
      }
      await _executor.insert(
        'printer_routes',
        route.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<void> createJob(PrintJobRecord job) async {
    if (job.state != PrintJobState.created &&
        job.state != PrintJobState.queued) {
      throw const PrintingConfigurationException(
        'Yeni iş yalnızca created veya queued durumunda oluşturulabilir.',
      );
    }
    await _executor.insert('print_jobs', job.toMap());
  }

  @override
  Future<PrintJobRecord> enqueue({
    required PrintDocumentKind kind,
    required String payloadJson,
    int copies = 1,
  }) async {
    if (copies < 1 || copies > 20) {
      throw const PrintingConfigurationException(
        'Kopya sayısı 1 ile 20 arasında olmalıdır.',
      );
    }
    late PrintJobRecord job;
    await _gateway.transaction(() async {
      final routes = await _executor.query(
        'printer_routes',
        where: 'kind = ?',
        whereArgs: [kind.name],
        limit: 1,
      );
      if (routes.isEmpty) {
        throw PrintingConfigurationException(
          '${kind.name} için yazıcı rotası tanımlanmamış.',
        );
      }
      final route = PrinterRoute.fromMap(routes.first);
      final devices = await _executor.query(
        'printer_devices',
        where: 'id = ? AND enabled = 1',
        whereArgs: [route.deviceId],
        limit: 1,
      );
      if (devices.isEmpty) {
        throw const PrintingConfigurationException(
          'Yazdırma rotasındaki cihaz bulunamadı veya devre dışı.',
        );
      }
      final profiles = await _executor.query(
        'print_design_profiles',
        where: 'id = ? AND kind = ?',
        whereArgs: [route.designProfileId, kind.name],
        limit: 1,
      );
      if (profiles.isEmpty) {
        throw const PrintingConfigurationException(
          'Yazdırma rotasındaki tasarım profili bulunamadı.',
        );
      }
      final device = PrinterDeviceProfile.fromMap(devices.first);
      final profile = PrintDesignProfile.fromMap(profiles.first);
      final now = DateTime.now();
      job = PrintJobRecord(
        id: _uuid.v4(),
        kind: kind,
        payloadJson: payloadJson,
        copies: copies,
        designProfileId: profile.id,
        designSnapshotJson: profiles.first['definition_json']! as String,
        deviceId: device.id,
        transportSnapshotJson: '{"kind":"${device.transport.name}",'
            '"config":${devices.first['transport_config_json']}}',
        capabilitySnapshotJson: devices.first['capabilities_json']! as String,
        rendererVersion: profile.rendererVersion,
        state: PrintJobState.queued,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
      );
      await _executor.insert('print_jobs', job.toMap());
    });
    return job;
  }

  @override
  Future<PrintJobRecord> enqueueForDevice({
    required PrintDocumentKind kind,
    required String deviceId,
    required String payloadJson,
    int copies = 1,
  }) async {
    if (copies < 1 || copies > 20) {
      throw const PrintingConfigurationException(
        'Kopya sayısı 1 ile 20 arasında olmalıdır.',
      );
    }
    late PrintJobRecord job;
    await _gateway.transaction(() async {
      final devices = await _executor.query(
        'printer_devices',
        where: 'id = ? AND enabled = 1',
        whereArgs: [deviceId],
        limit: 1,
      );
      if (devices.isEmpty) {
        throw const PrintingConfigurationException(
          'Test edilecek etkin yazıcı bulunamadı.',
        );
      }
      final device = PrinterDeviceProfile.fromMap(devices.single);
      final expectedLanguage = kind == PrintDocumentKind.receipt
          ? PrinterLanguage.escPos
          : PrinterLanguage.tspl;
      if (device.language != expectedLanguage) {
        throw const PrintingConfigurationException(
          'Test türü seçilen yazıcının diliyle uyumlu değil.',
        );
      }
      final profiles = await _executor.query(
        'print_design_profiles',
        where: 'kind = ? AND is_default = 1',
        whereArgs: [kind.name],
        limit: 1,
      );
      if (profiles.isEmpty) {
        throw const PrintingConfigurationException(
          'Test için varsayılan tasarım profili bulunamadı.',
        );
      }
      final profile = PrintDesignProfile.fromMap(profiles.single);
      final now = DateTime.now();
      job = PrintJobRecord(
        id: _uuid.v4(),
        kind: kind,
        payloadJson: payloadJson,
        copies: copies,
        designProfileId: profile.id,
        designSnapshotJson: profiles.single['definition_json']! as String,
        deviceId: device.id,
        transportSnapshotJson: '{"kind":"${device.transport.name}",'
            '"config":${devices.single['transport_config_json']}}',
        capabilitySnapshotJson: devices.single['capabilities_json']! as String,
        rendererVersion: profile.rendererVersion,
        state: PrintJobState.queued,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
      );
      await _executor.insert('print_jobs', job.toMap());
    });
    return job;
  }

  @override
  Future<PrintJobRecord?> getJob(String id) async {
    final rows = await _executor.query(
      'print_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PrintJobRecord.fromMap(rows.single);
  }

  @override
  Future<List<PrintJobRecord>> getJobs() async {
    final rows = await _executor.query(
      'print_jobs',
      orderBy: 'created_at DESC',
      limit: 500,
    );
    return rows.map(PrintJobRecord.fromMap).toList(growable: false);
  }

  @override
  Future<PrintJobRecord?> claimNext(String deviceId) async {
    PrintJobRecord? claimed;
    await _gateway.transaction(() async {
      final now = DateTime.now();
      final rows = await _executor.query(
        'print_jobs',
        where: '''device_id = ? AND state IN (?, ?) AND
          (next_attempt_at IS NULL OR next_attempt_at <= ?)''',
        whereArgs: [
          deviceId,
          PrintJobState.queued.name,
          PrintJobState.retryWait.name,
          now.toIso8601String(),
        ],
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (rows.isEmpty) return;
      final candidate = PrintJobRecord.fromMap(rows.first);
      final affected = await _executor.update(
        'print_jobs',
        {
          'state': PrintJobState.rendering.name,
          'attempt_count': candidate.attemptCount + 1,
          'updated_at': now.toIso8601String(),
          'next_attempt_at': null,
          'error_code': null,
          'error_message': null,
        },
        where: 'id = ? AND state = ?',
        whereArgs: [candidate.id, candidate.state.name],
      );
      if (affected != 1) return;
      await _executor.insert('print_job_attempts', {
        'job_id': candidate.id,
        'attempt_no': candidate.attemptCount + 1,
        'started_at': now.toIso8601String(),
      });
      final claimedRows = await _executor.query(
        'print_jobs',
        where: 'id = ?',
        whereArgs: [candidate.id],
        limit: 1,
      );
      claimed = PrintJobRecord.fromMap(claimedRows.single);
    });
    return claimed;
  }

  @override
  Future<void> markRendered(String id, String checksum) async {
    final affected = await _executor.update(
      'print_jobs',
      {
        'state': PrintJobState.sending.name,
        'rendered_checksum': checksum,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND state = ?',
      whereArgs: [id, PrintJobState.rendering.name],
    );
    _requireTransition(affected, id, 'rendering', 'sending');
  }

  @override
  Future<void> markDelivered(String id, String observationJson) async {
    await _gateway.transaction(() async {
      final now = DateTime.now().toIso8601String();
      final affected = await _executor.update(
        'print_jobs',
        {
          'state': PrintJobState.delivered.name,
          'delivery_observation_json': observationJson,
          'updated_at': now,
        },
        where: 'id = ? AND state = ?',
        whereArgs: [id, PrintJobState.sending.name],
      );
      _requireTransition(affected, id, 'sending', 'delivered');
      await _executor.update(
        'print_job_attempts',
        {'completed_at': now, 'outcome': 'delivered'},
        where: '''job_id = ? AND completed_at IS NULL''',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> markDeliveryUncertain(String id, String message) async {
    await _gateway.transaction(() async {
      final now = DateTime.now().toIso8601String();
      final affected = await _executor.update(
        'print_jobs',
        {
          'state': PrintJobState.awaitingUserCheck.name,
          'error_code': 'delivery_uncertain',
          'error_message': message,
          'updated_at': now,
        },
        where: 'id = ? AND state = ?',
        whereArgs: [id, PrintJobState.sending.name],
      );
      _requireTransition(affected, id, 'sending', 'awaitingUserCheck');
      await _executor.update(
        'print_job_attempts',
        {
          'completed_at': now,
          'outcome': 'deliveryUncertain',
          'error_code': 'delivery_uncertain',
          'error_message': message,
        },
        where: 'job_id = ? AND completed_at IS NULL',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> markAttemptFailed(
    String id, {
    required String errorCode,
    required String errorMessage,
    required bool retryable,
  }) async {
    await _gateway.transaction(() async {
      final rows = await _executor.query(
        'print_jobs',
        where: 'id = ? AND state IN (?, ?)',
        whereArgs: [
          id,
          PrintJobState.rendering.name,
          PrintJobState.sending.name,
        ],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw PrintingConfigurationException(
          '$id işi başarısız duruma geçirilemez.',
        );
      }
      final job = PrintJobRecord.fromMap(rows.single);
      final willRetry = retryable && job.attemptCount < _maxAttempts;
      final now = DateTime.now();
      final delaySeconds = (2 << (job.attemptCount - 1)).clamp(2, 300);
      await _executor.update(
        'print_jobs',
        {
          'state': willRetry
              ? PrintJobState.retryWait.name
              : PrintJobState.failed.name,
          'next_attempt_at': willRetry
              ? now.add(Duration(seconds: delaySeconds)).toIso8601String()
              : null,
          'error_code': errorCode,
          'error_message': errorMessage,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _executor.update(
        'print_job_attempts',
        {
          'completed_at': now.toIso8601String(),
          'outcome': willRetry ? 'retryWait' : 'failed',
          'error_code': errorCode,
          'error_message': errorMessage,
        },
        where: 'job_id = ? AND completed_at IS NULL',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> cancelJob(String id) async {
    final affected = await _executor.update(
      'print_jobs',
      {
        'state': PrintJobState.cancelled.name,
        'updated_at': DateTime.now().toIso8601String(),
        'next_attempt_at': null,
      },
      where: 'id = ? AND state IN (?, ?, ?, ?)',
      whereArgs: [
        id,
        PrintJobState.created.name,
        PrintJobState.queued.name,
        PrintJobState.retryWait.name,
        PrintJobState.awaitingUserCheck.name,
      ],
    );
    if (affected != 1) {
      throw PrintingConfigurationException('$id işi iptal edilemez.');
    }
  }

  @override
  Future<void> retryJob(String id) async {
    final affected = await _executor.update(
      'print_jobs',
      {
        'state': PrintJobState.queued.name,
        'attempt_count': 0,
        'next_attempt_at': null,
        'error_code': null,
        'error_message': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND state IN (?, ?, ?)',
      whereArgs: [
        id,
        PrintJobState.failed.name,
        PrintJobState.rejected.name,
        PrintJobState.cancelled.name,
      ],
    );
    if (affected != 1) {
      throw PrintingConfigurationException('$id işi tekrar kuyruğa alınamaz.');
    }
  }

  @override
  Future<void> confirmUncertainDelivery(
    String id, {
    required bool printed,
  }) async {
    final now = DateTime.now().toIso8601String();
    final affected = await _executor.update(
      'print_jobs',
      {
        'state':
            printed ? PrintJobState.confirmed.name : PrintJobState.queued.name,
        'error_code': null,
        'error_message': null,
        'updated_at': now,
      },
      where: 'id = ? AND state = ?',
      whereArgs: [id, PrintJobState.awaitingUserCheck.name],
    );
    _requireTransition(
      affected,
      id,
      'awaitingUserCheck',
      printed ? 'confirmed' : 'queued',
    );
  }

  @override
  Future<void> requestPhysicalConfirmation(String id) async {
    final affected = await _executor.update(
      'print_jobs',
      {
        'state': PrintJobState.awaitingUserCheck.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND state = ?',
      whereArgs: [id, PrintJobState.delivered.name],
    );
    _requireTransition(affected, id, 'delivered', 'awaitingUserCheck');
  }

  @override
  Future<void> resolvePhysicalConfirmation(
    String id, {
    required bool passed,
  }) async {
    final affected = await _executor.update(
      'print_jobs',
      {
        'state':
            passed ? PrintJobState.confirmed.name : PrintJobState.rejected.name,
        'error_code': passed ? null : 'physical_output_rejected',
        'error_message':
            passed ? null : 'Kullanıcı fiziksel test çıktısını reddetti.',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND state = ?',
      whereArgs: [id, PrintJobState.awaitingUserCheck.name],
    );
    _requireTransition(
      affected,
      id,
      'awaitingUserCheck',
      passed ? 'confirmed' : 'rejected',
    );
  }

  @override
  Future<PrintRecoverySummary> recoverInterruptedJobs() async {
    late int rendering;
    late int sending;
    await _gateway.transaction(() async {
      final now = DateTime.now().toIso8601String();
      rendering = await _executor.update(
        'print_jobs',
        {'state': PrintJobState.queued.name, 'updated_at': now},
        where: 'state = ?',
        whereArgs: [PrintJobState.rendering.name],
      );
      sending = await _executor.update(
        'print_jobs',
        {
          'state': PrintJobState.awaitingUserCheck.name,
          'error_code': 'delivery_unknown_after_restart',
          'error_message':
              'Uygulama gönderim sırasında kapandı; fiziksel çıktı doğrulanmalı.',
          'updated_at': now,
        },
        where: 'state = ?',
        whereArgs: [PrintJobState.sending.name],
      );
    });
    return PrintRecoverySummary(
      safelyRequeued: rendering,
      awaitingUserCheck: sending,
    );
  }

  static void _requireTransition(
    int affected,
    String id,
    String from,
    String to,
  ) {
    if (affected != 1) {
      throw PrintingConfigurationException(
        '$id işi $from durumundan $to durumuna geçirilemedi.',
      );
    }
  }

  @override
  Future<List<PrintJobRecord>> getRecoverableJobs() async {
    final now = DateTime.now().toIso8601String();
    final rows = await _executor.query(
      'print_jobs',
      where: '''state IN (?, ?, ?, ?) AND
        (next_attempt_at IS NULL OR next_attempt_at <= ?)''',
      whereArgs: [
        PrintJobState.queued.name,
        PrintJobState.rendering.name,
        PrintJobState.sending.name,
        PrintJobState.retryWait.name,
        now,
      ],
      orderBy: 'created_at ASC',
    );
    return rows.map(PrintJobRecord.fromMap).toList(growable: false);
  }
}
