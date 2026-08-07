import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/services/shared_hardware_service.dart';
import 'package:serenutos/infrastructure/services/shared_hardware_worker.dart';

void main() {
  test(
      'owner worker executes only its local physical printer and reports result',
      () async {
    final gateway = _Gateway(ClaimedHardwareJob(
      id: 'job-1',
      hardwareId: 'activation-a:receipt-primary',
      operation: 'printReceipt',
      payload: {
        'bytes_base64': base64Encode([27, 64, 10]),
        'copies': 2,
      },
    ));
    final transport = _Transport();
    final worker = SharedHardwareWorker(
      service: gateway,
      loadActivationId: () => 'activation-a',
      loadPrinter: (id) async {
        expect(id, 'receipt-primary');
        return _printer(id);
      },
      transports: [transport],
    );

    await worker.processNow();

    expect(gateway.started, ['job-1']);
    expect(transport.bytes, [27, 64, 10]);
    expect(transport.copies, 2);
    expect(gateway.results.single.state, 'succeeded');
    worker.dispose();
  });

  test('owner mismatch never reaches a physical transport', () async {
    final gateway = _Gateway(ClaimedHardwareJob(
      id: 'job-2',
      hardwareId: 'activation-b:receipt-primary',
      operation: 'printReceipt',
      payload: {
        'bytes_base64': base64Encode([1]),
        'copies': 1
      },
    ));
    final transport = _Transport();
    final worker = SharedHardwareWorker(
      service: gateway,
      loadActivationId: () => 'activation-a',
      loadPrinter: (_) async => _printer('receipt-primary'),
      transports: [transport],
    );

    await worker.processNow();

    expect(gateway.started, isEmpty);
    expect(transport.bytes, isEmpty);
    expect(gateway.results.single.state, 'failed');
    expect(gateway.results.single.errorCode, 'hardware_owner_mismatch');
    worker.dispose();
  });
}

PrinterDeviceProfile _printer(String id) {
  final now = DateTime(2026);
  return PrinterDeviceProfile(
    id: id,
    name: 'Sunmi Dahili',
    language: PrinterLanguage.escPos,
    transport: PrinterTransportKind.embedded,
    transportConfig: const {},
    capabilities: const {'paperWidthMm': 58},
    enabled: true,
    createdAt: now,
    updatedAt: now,
  );
}

class _Gateway implements SharedHardwareJobGateway {
  ClaimedHardwareJob? next;
  final List<String> started = [];
  final List<_Result> results = [];

  _Gateway(this.next);

  @override
  Future<ClaimedHardwareJob?> claim() async {
    final value = next;
    next = null;
    return value;
  }

  @override
  Future<void> markExecuting(String jobId) async => started.add(jobId);

  @override
  Future<void> reportResult(
    String jobId, {
    required String state,
    Map<String, Object?> result = const {},
    String? errorCode,
    String? errorMessage,
  }) async {
    results.add(_Result(state, errorCode));
  }
}

class _Result {
  final String state;
  final String? errorCode;

  const _Result(this.state, this.errorCode);
}

class _Transport implements PrintTransport {
  List<int> bytes = [];
  int copies = 0;

  @override
  bool supports(PrinterTransportKind kind) =>
      kind == PrinterTransportKind.embedded;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    this.bytes = bytes;
    this.copies = copies;
    return PrintTransportObservation(
      transport: 'embedded',
      acceptedAt: DateTime(2026),
      details: const {'accepted': true},
    );
  }
}
