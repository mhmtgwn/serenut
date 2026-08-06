import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_printing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Renderer implements PrintRenderer {
  @override
  Future<RenderedPrintDocument> render(PrintJobRecord job) async =>
      RenderedPrintDocument(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/vnd.escpos',
      );

  @override
  bool supports(PrintDocumentKind kind, String rendererVersion) => true;
}

class _Transport implements PrintTransport {
  final bool uncertain;
  int sends = 0;

  _Transport({this.uncertain = false});

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    sends++;
    if (uncertain) {
      throw const PrintTransportException(
        code: 'connection_lost',
        message: 'Gönderim sırasında bağlantı koptu.',
        retryable: true,
        deliveryUncertain: true,
      );
    }
    return PrintTransportObservation(
      transport: 'tcp',
      acceptedAt: DateTime.utc(2026),
      details: const {'bytesAccepted': 3},
    );
  }

  @override
  bool supports(PrinterTransportKind kind) => kind == PrinterTransportKind.tcp;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqlitePrintingRepository repository;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseSchema.createTables(db);
    repository = SqlitePrintingRepository(DbGatewayImpl.raw(db));
    final now = DateTime.utc(2026);
    await repository.saveDesignProfile(PrintDesignProfile(
      id: 'receipt-design',
      name: 'Fiş',
      kind: PrintDocumentKind.receipt,
      schemaVersion: 1,
      rendererVersion: 'escpos-v1',
      definition: const {'paperWidthMm': 58},
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    ));
    await repository.saveDevice(PrinterDeviceProfile(
      id: 'receipt-a',
      name: '58 mm',
      language: PrinterLanguage.escPos,
      transport: PrinterTransportKind.tcp,
      transportConfig: const {'host': '192.168.1.20', 'port': 9100},
      capabilities: const {'paperWidthMm': 58, 'printableWidthDots': 384},
      enabled: true,
      createdAt: now,
      updatedAt: now,
    ));
    await repository.saveRoute(PrinterRoute(
      kind: PrintDocumentKind.receipt,
      deviceId: 'receipt-a',
      designProfileId: 'receipt-design',
      updatedAt: now,
    ));
  });

  tearDown(() => db.close());

  test('coordinator renders, hashes and delivers one claimed job', () async {
    await repository.enqueue(
      kind: PrintDocumentKind.receipt,
      payloadJson: jsonEncode({'saleId': 'sale-1'}),
    );
    final transport = _Transport();
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: [_Renderer()],
      transports: [transport],
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.processNext('receipt-a'), isTrue);
    final job = (await db.query('print_jobs')).single;
    expect(job['state'], PrintJobState.delivered.name);
    expect(job['rendered_checksum'], isNotEmpty);
    expect(transport.sends, 1);
    expect(
        (await db.query('print_job_attempts')).single['outcome'], 'delivered');
  });

  test('uncertain delivery is quarantined and never automatically retried',
      () async {
    await repository.enqueue(
      kind: PrintDocumentKind.receipt,
      payloadJson: '{}',
    );
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: [_Renderer()],
      transports: [_Transport(uncertain: true)],
    );
    addTearDown(coordinator.dispose);

    await coordinator.processNext('receipt-a');
    final job = (await db.query('print_jobs')).single;
    expect(job['state'], PrintJobState.awaitingUserCheck.name);
    expect(await repository.claimNext('receipt-a'), isNull);
  });
}
