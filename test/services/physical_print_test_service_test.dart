import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/printing/physical_print_test_service.dart';
import 'package:serenutos/infrastructure/printing/printing_renderers.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_printing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CaptureTransport implements PrintTransport {
  Uint8List? bytes;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    this.bytes = bytes;
    return PrintTransportObservation(
      transport: 'tcp',
      acceptedAt: DateTime.now(),
      details: {'bytesAccepted': bytes.length},
    );
  }

  @override
  bool supports(PrinterTransportKind kind) => kind == PrinterTransportKind.tcp;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('physical receipt test stays pending until user confirms paper output',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseSchema.createTables(db);
    final repository = SqlitePrintingRepository(DbGatewayImpl.raw(db));
    final now = DateTime.utc(2026);
    await repository.saveDevice(PrinterDeviceProfile(
      id: 'receipt-a',
      name: '58 mm',
      language: PrinterLanguage.escPos,
      transport: PrinterTransportKind.tcp,
      transportConfig: const {'host': '192.168.1.10', 'port': 9100},
      capabilities: const {
        'paperWidthMm': 58,
        'printableWidthDots': 384,
      },
      enabled: true,
      createdAt: now,
      updatedAt: now,
    ));
    final transport = _CaptureTransport();
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: [EscPosReceiptRenderer()],
      transports: [transport],
    );
    final runtime = PrintingRuntime(
      repository: repository,
      coordinator: coordinator,
      pollInterval: const Duration(days: 1),
    );
    final service = PhysicalPrintTestService(
      repository: repository,
      runtime: runtime,
    );
    addTearDown(runtime.dispose);
    addTearDown(coordinator.dispose);

    final dispatch = await service.dispatch(
      deviceId: 'receipt-a',
      kind: PrintDocumentKind.receipt,
    );
    expect((await repository.getJob(dispatch.jobId))!.state,
        PrintJobState.awaitingUserCheck);
    expect(transport.bytes, isNotNull);
    expect(
        _containsSequence(
          transport.bytes!,
          const [0x1D, 0x6B, 0x49],
        ),
        isTrue,
        reason: 'barcode command');

    await service.confirm(dispatch, passed: true);
    expect((await repository.getJob(dispatch.jobId))!.state,
        PrintJobState.confirmed);
    final device = await repository.getDevice('receipt-a');
    expect(device!.lastTestSucceeded, isTrue);
  });

  test('physical order-label test exercises the order renderer separately',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseSchema.createTables(db);
    final repository = SqlitePrintingRepository(DbGatewayImpl.raw(db));
    final now = DateTime.utc(2026);
    await repository.saveDevice(PrinterDeviceProfile(
      id: 'label-a',
      name: '58x30 Etiket',
      language: PrinterLanguage.tspl,
      transport: PrinterTransportKind.tcp,
      transportConfig: const {'host': '192.168.1.20', 'port': 9100},
      capabilities: const {
        'mediaWidthMm': 58,
        'mediaHeightMm': 30,
        'gapMm': 2,
        'dpi': 300,
      },
      enabled: true,
      createdAt: now,
      updatedAt: now,
    ));
    final transport = _CaptureTransport();
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: [TsplOrderLabelRenderer()],
      transports: [transport],
    );
    final runtime = PrintingRuntime(
      repository: repository,
      coordinator: coordinator,
      pollInterval: const Duration(days: 1),
    );
    final service = PhysicalPrintTestService(
      repository: repository,
      runtime: runtime,
    );
    addTearDown(runtime.dispose);
    addTearDown(coordinator.dispose);

    final dispatch = await service.dispatch(
      deviceId: 'label-a',
      kind: PrintDocumentKind.orderLabel,
    );

    expect(dispatch.kind, PrintDocumentKind.orderLabel);
    expect((await repository.getJob(dispatch.jobId))!.state,
        PrintJobState.awaitingUserCheck);
    final command = String.fromCharCodes(transport.bytes!);
    expect(command, contains('DIRECTION 0'));
    expect(command, contains('12345678'));
    expect(command, contains('QRCODE '));
    expect(command, isNot(contains('BARCODE ')));
  });
}

bool _containsSequence(Uint8List bytes, List<int> sequence) {
  for (var offset = 0; offset <= bytes.length - sequence.length; offset++) {
    var matches = true;
    for (var index = 0; index < sequence.length; index++) {
      if (bytes[offset + index] != sequence[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
