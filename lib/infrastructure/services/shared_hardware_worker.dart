import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/services/shared_hardware_service.dart';

typedef PrinterProfileLoader = Future<PrinterDeviceProfile?> Function(
    String id);
typedef ActivationIdLoader = String Function();
typedef SharedHardwareTelemetry = Future<void> Function(
  String event,
  Map<String, Object?> metadata,
);

/// Executes cloud jobs only for printers physically registered on this device.
class SharedHardwareWorker {
  final SharedHardwareJobGateway service;
  final PrinterProfileLoader loadPrinter;
  final ActivationIdLoader loadActivationId;
  final List<PrintTransport> transports;
  final Duration pollInterval;
  final SharedHardwareTelemetry? telemetry;

  Timer? _timer;
  bool _busy = false;

  SharedHardwareWorker({
    required this.service,
    PrintingRepository? repository,
    PrinterProfileLoader? loadPrinter,
    LicenseService? licenseService,
    ActivationIdLoader? loadActivationId,
    required this.transports,
    this.pollInterval = const Duration(seconds: 3),
    this.telemetry,
  })  : assert(repository != null || loadPrinter != null),
        assert(licenseService != null || loadActivationId != null),
        loadActivationId = loadActivationId ??
            (() => licenseService!.getLicenseInfo()?.activationId ?? ''),
        loadPrinter = loadPrinter ?? repository!.getDevice;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(processNow()));
    unawaited(processNow());
  }

  Future<void> processNow() async {
    if (_busy) return;
    _busy = true;
    try {
      for (var count = 0; count < 10; count++) {
        final job = await service.claim();
        if (job == null) return;
        await _execute(job);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _execute(ClaimedHardwareJob job) async {
    try {
      final activationId = loadActivationId();
      final prefix = '$activationId:';
      if (!job.hardwareId.startsWith(prefix)) {
        throw const PrintTransportException(
          code: 'hardware_owner_mismatch',
          message: 'İş bu cihazın donanımına ait değil.',
          retryable: false,
        );
      }
      final localId = job.hardwareId.substring(prefix.length);
      final device = await loadPrinter(localId);
      if (device == null ||
          !device.enabled ||
          device.transport == PrinterTransportKind.cloudRelay) {
        throw const PrintTransportException(
          code: 'local_hardware_unavailable',
          message: 'Yerel yazıcı bulunamadı veya devre dışı.',
          retryable: true,
        );
      }
      final transport =
          transports.where((item) => item.supports(device.transport));
      if (transport.isEmpty) {
        throw PrintTransportException(
          code: 'local_transport_unavailable',
          message: '${device.transport.name} bağlantı sürücüsü bulunamadı.',
          retryable: false,
        );
      }
      final encoded = job.payload['bytes_base64'];
      final copies = (job.payload['copies'] as num?)?.toInt() ?? 1;
      if (encoded is! String || copies < 1 || copies > 20) {
        throw const PrintTransportException(
          code: 'invalid_remote_payload',
          message: 'Uzak yazdırma verisi geçersiz.',
          retryable: false,
        );
      }
      final bytes = Uint8List.fromList(base64Decode(encoded));
      if (bytes.isEmpty || bytes.length > 384000) {
        throw const PrintTransportException(
          code: 'invalid_remote_payload',
          message: 'Uzak yazdırma verisi boş veya çok büyük.',
          retryable: false,
        );
      }
      await service.markExecuting(job.id);
      final observation = await transport.single.send(
        bytes: bytes,
        copies: copies,
        configuration: device.transportConfig,
      );
      await service.reportResult(
        job.id,
        state: observation.physicalConfirmationRequired
            ? 'requires_confirmation'
            : 'succeeded',
        result: jsonDecode(observation.toJson()) as Map<String, Object?>,
      );
      _record('shared_hardware_job_succeeded', {
        'job_id': job.id,
        'hardware_id': job.hardwareId,
        'transport': observation.transport,
      });
    } on PrintTransportException catch (error) {
      await service.reportResult(
        job.id,
        state: error.deliveryUncertain
            ? 'requires_confirmation'
            : error.retryable
                ? 'retry_wait'
                : 'failed',
        errorCode: error.code,
        errorMessage: error.message,
      );
      _record('shared_hardware_job_transport_error', {
        'job_id': job.id,
        'hardware_id': job.hardwareId,
        'error_code': error.code,
        'retryable': error.retryable,
        'delivery_uncertain': error.deliveryUncertain,
      });
    } catch (error) {
      await service.reportResult(
        job.id,
        state: 'failed',
        errorCode: 'worker_failure',
        errorMessage: error.toString(),
      );
      _record('shared_hardware_job_worker_error', {
        'job_id': job.id,
        'hardware_id': job.hardwareId,
        'error_type': error.runtimeType.toString(),
      });
    }
  }

  void _record(String event, Map<String, Object?> metadata) {
    final reporter = telemetry;
    if (reporter != null) unawaited(reporter(event, metadata));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
