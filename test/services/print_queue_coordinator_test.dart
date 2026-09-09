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

  test('coordinator schedules retry on socket or network error instead of failing permanently',
      () async {
    await repository.enqueue(
      kind: PrintDocumentKind.receipt,
      payloadJson: '{}',
    );
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: [_Renderer()],
      transports: [_FailingSocketTransport()],
    );
    addTearDown(coordinator.dispose);

    final eventFuture = coordinator.events
        .firstWhere((e) => e.type == PrintCoordinatorEventType.retryScheduled);

    await coordinator.processNext('receipt-a');
    final event = await eventFuture;
    expect(event.type, PrintCoordinatorEventType.retryScheduled);

    final job = (await db.query('print_jobs')).single;
    expect(job['state'], PrintJobState.retryWait.name);
    expect(job['next_attempt_at'], isNotNull);
  });

  test('enqueue auto-heals when route is missing but compatible device is enabled',
      () async {
    // Delete existing route
    await db.delete('printer_routes');
    expect(await db.query('printer_routes'), isEmpty);

    // Enqueue should auto-heal by finding receipt-a and saving the route
    final job = await repository.enqueue(
      kind: PrintDocumentKind.receipt,
      payloadJson: '{"test": true}',
    );

    expect(job.deviceId, 'receipt-a');
    final routes = await db.query('printer_routes');
    expect(routes, hasLength(1));
    expect(routes.first['device_id'], 'receipt-a');
  });

  test('enqueue auto-heals when routed device is disabled but another compatible device exists',
      () async {
    // Disable receipt-a
    await db.update('printer_devices', {'enabled': 0}, where: 'id = ?', whereArgs: ['receipt-a']);

    // Add a second enabled device
    final now = DateTime.utc(2026);
    await repository.saveDevice(PrinterDeviceProfile(
      id: 'receipt-backup',
      name: 'Backup Printer',
      language: PrinterLanguage.escPos,
      transport: PrinterTransportKind.tcp,
      transportConfig: const {'host': '192.168.1.30', 'port': 9100},
      capabilities: const {'paperWidthMm': 58},
      enabled: true,
      createdAt: now,
      updatedAt: now,
    ));

    // Enqueue should auto-heal to use receipt-backup
    final job = await repository.enqueue(
      kind: PrintDocumentKind.receipt,
      payloadJson: '{"test": true}',
    );

    expect(job.deviceId, 'receipt-backup');
    final routes = await db.query('printer_routes');
    expect(routes.first['device_id'], 'receipt-backup');
  });
}

class _FailingSocketTransport implements PrintTransport {
  @override
  bool supports(PrinterTransportKind kind) => kind == PrinterTransportKind.tcp;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    throw Exception('SocketException: OS Error: Connection timed out, errno = 110');
  }
}
