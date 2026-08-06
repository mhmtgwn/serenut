import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'printing_models.dart';
import 'printing_repository.dart';

class RenderedPrintDocument {
  final Uint8List bytes;
  final String mimeType;

  const RenderedPrintDocument({required this.bytes, required this.mimeType});
}

abstract interface class PrintRenderer {
  bool supports(PrintDocumentKind kind, String rendererVersion);
  Future<RenderedPrintDocument> render(PrintJobRecord job);
}

class PrintTransportObservation {
  final String transport;
  final DateTime acceptedAt;
  final Map<String, Object?> details;
  final bool physicalConfirmationRequired;

  const PrintTransportObservation({
    required this.transport,
    required this.acceptedAt,
    required this.details,
    this.physicalConfirmationRequired = false,
  });

  String toJson() => jsonEncode({
        'transport': transport,
        'acceptedAt': acceptedAt.toIso8601String(),
        'details': details,
        'physicalConfirmationRequired': physicalConfirmationRequired,
      });
}

abstract interface class PrintTransport {
  bool supports(PrinterTransportKind kind);
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  });
}

class PrintTransportException implements Exception {
  final String code;
  final String message;
  final bool retryable;
  final bool deliveryUncertain;

  const PrintTransportException({
    required this.code,
    required this.message,
    required this.retryable,
    this.deliveryUncertain = false,
  });

  @override
  String toString() => message;
}

enum PrintCoordinatorEventType {
  claimed,
  rendered,
  delivered,
  retryScheduled,
  awaitingUserCheck,
  failed,
}

class PrintCoordinatorEvent {
  final String jobId;
  final String deviceId;
  final PrintCoordinatorEventType type;
  final String message;

  const PrintCoordinatorEvent({
    required this.jobId,
    required this.deviceId,
    required this.type,
    required this.message,
  });
}

class PrintQueueCoordinator {
  final PrintingRepository repository;
  final List<PrintRenderer> renderers;
  final List<PrintTransport> transports;
  final _events = StreamController<PrintCoordinatorEvent>.broadcast();
  final Set<String> _busyDevices = {};

  PrintQueueCoordinator({
    required this.repository,
    required this.renderers,
    required this.transports,
  });

  Stream<PrintCoordinatorEvent> get events => _events.stream;

  bool supportsRenderer(PrintDocumentKind kind, String rendererVersion) =>
      renderers.any((renderer) => renderer.supports(kind, rendererVersion));

  Future<bool> processNext(String deviceId) async {
    if (!_busyDevices.add(deviceId)) return false;
    try {
      final job = await repository.claimNext(deviceId);
      if (job == null) return false;
      _emit(job, PrintCoordinatorEventType.claimed, 'İş işleniyor.');
      try {
        final renderer = renderers.where(
          (candidate) => candidate.supports(job.kind, job.rendererVersion),
        );
        if (renderer.isEmpty) {
          await repository.markAttemptFailed(
            job.id,
            errorCode: 'renderer_not_found',
            errorMessage: '${job.rendererVersion} renderer bulunamadı.',
            retryable: false,
          );
          _emit(job, PrintCoordinatorEventType.failed, 'Renderer bulunamadı.');
          return true;
        }
        final rendered = await renderer.single.render(job);
        final checksum = sha256.convert(rendered.bytes).toString();
        await repository.markRendered(job.id, checksum);
        _emit(job, PrintCoordinatorEventType.rendered, 'Belge oluşturuldu.');

        final snapshot = Map<String, Object?>.from(
          jsonDecode(job.transportSnapshotJson) as Map,
        );
        final kind = PrinterTransportKind.values.byName(
          snapshot['kind']! as String,
        );
        final transport = transports.where((value) => value.supports(kind));
        if (transport.isEmpty) {
          throw PrintTransportException(
            code: 'transport_not_found',
            message: '${kind.name} transport bulunamadı.',
            retryable: false,
          );
        }
        final observation = await transport.single.send(
          bytes: rendered.bytes,
          copies: job.copies,
          configuration: Map<String, Object?>.from(
            snapshot['config'] as Map? ?? const {},
          ),
        );
        await repository.markDelivered(job.id, observation.toJson());
        _emit(job, PrintCoordinatorEventType.delivered,
            'İş yazıcıya teslim edildi.');
      } on PrintTransportException catch (error) {
        if (error.deliveryUncertain) {
          await repository.markDeliveryUncertain(job.id, error.message);
          _emit(job, PrintCoordinatorEventType.awaitingUserCheck,
              'Fiziksel çıktı doğrulanmalı.');
        } else {
          await repository.markAttemptFailed(
            job.id,
            errorCode: error.code,
            errorMessage: error.message,
            retryable: error.retryable,
          );
          _emit(
            job,
            error.retryable
                ? PrintCoordinatorEventType.retryScheduled
                : PrintCoordinatorEventType.failed,
            error.message,
          );
        }
      } catch (error) {
        await repository.markAttemptFailed(
          job.id,
          errorCode: 'render_failed',
          errorMessage: error.toString(),
          retryable: false,
        );
        _emit(job, PrintCoordinatorEventType.failed, error.toString());
      }
      return true;
    } finally {
      _busyDevices.remove(deviceId);
    }
  }

  Future<PrintRecoverySummary> recoverOnStartup() =>
      repository.recoverInterruptedJobs();

  void _emit(
    PrintJobRecord job,
    PrintCoordinatorEventType type,
    String message,
  ) {
    if (_events.isClosed) return;
    _events.add(PrintCoordinatorEvent(
      jobId: job.id,
      deviceId: job.deviceId,
      type: type,
      message: message,
    ));
  }

  Future<void> dispose() => _events.close();
}
