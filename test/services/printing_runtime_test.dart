import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_printing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Renderer implements PrintRenderer {
  @override
  Future<RenderedPrintDocument> render(PrintJobRecord job) async =>
      RenderedPrintDocument(
        bytes: Uint8List.fromList(utf8.encode(job.id)),
        mimeType: 'application/vnd.escpos',
      );

  @override
  bool supports(PrintDocumentKind kind, String rendererVersion) => true;
}

class _ParallelTransport implements PrintTransport {
  int active = 0;
  int maxActive = 0;
  final List<String> hosts = [];

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    active++;
    if (active > maxActive) maxActive = active;
    hosts.add(configuration['host']! as String);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    active--;
    return PrintTransportObservation(
      transport: 'tcp',
      acceptedAt: DateTime.now(),
      details: const {},
    );
  }

  @override
  bool supports(PrinterTransportKind kind) => kind == PrinterTransportKind.tcp;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('runtime recovers at startup and drains different devices concurrently',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseSchema.createTables(db);
    final repository = SqlitePrintingRepository(DbGatewayImpl.raw(db));
    final now = DateTime.utc(2026);
    await repository.saveDesignProfile(PrintDesignProfile(
      id: 'design',
      name: 'Fiş',
      kind: PrintDocumentKind.receipt,
      schemaVersion: 1,
      rendererVersion: 'test-v1',
      definition: const {},
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    ));
    for (final entry in const {'a': '10.0.0.1', 'b': '10.0.0.2'}.entries) {
      await repository.saveDevice(PrinterDeviceProfile(
        id: entry.key,
        name: entry.key,
        language: PrinterLanguage.escPos,
        transport: PrinterTransportKind.tcp,
        transportConfig: {'host': entry.value, 'port': 9100},
        capabilities: const {'paperWidthMm': 58},
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ));
      await repository.saveRoute(PrinterRoute(
        kind: PrintDocumentKind.receipt,
        deviceId: entry.key,
        designProfileId: 'design',
        updatedAt: now,
      ));
      await repository.enqueue(
        kind: PrintDocumentKind.receipt,
        payloadJson: '{}',
      );
    }
    // Simulate a crash before rendering one job. Startup recovery must safely
    // return it to queued before workers begin.
    await db.update(
      'print_jobs',
      {'state': PrintJobState.rendering.name},
      where: 'device_id = ?',
      whereArgs: ['a'],
    );

    final transport = _ParallelTransport();
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: [_Renderer()],
      transports: [transport],
    );
    final runtime = PrintingRuntime(
      repository: repository,
      coordinator: coordinator,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(runtime.dispose);
    addTearDown(coordinator.dispose);

    final recovery = await runtime.start();
    expect(recovery.safelyRequeued, 1);
    expect(recovery.awaitingUserCheck, 0);
    expect(
        (await db.query('print_jobs', where: 'state = ?', whereArgs: [
          PrintJobState.delivered.name,
        ])),
        hasLength(2));
    expect(transport.hosts, containsAll(['10.0.0.1', '10.0.0.2']));
    expect(transport.maxActive, 2);
  });

  test('runtime rejects an active route with no registered renderer', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseSchema.createTables(db);
    final repository = SqlitePrintingRepository(DbGatewayImpl.raw(db));
    final now = DateTime.utc(2026);
    await repository.saveDesignProfile(PrintDesignProfile(
      id: 'unsupported-design',
      name: 'Desteklenmeyen',
      kind: PrintDocumentKind.receipt,
      schemaVersion: 1,
      rendererVersion: 'missing-v1',
      definition: const {},
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    ));
    await repository.saveDevice(PrinterDeviceProfile(
      id: 'receipt',
      name: 'receipt',
      language: PrinterLanguage.escPos,
      transport: PrinterTransportKind.tcp,
      transportConfig: const {'host': '127.0.0.1', 'port': 9100},
      capabilities: const {'paperWidthMm': 58},
      enabled: true,
      createdAt: now,
      updatedAt: now,
    ));
    await repository.saveRoute(PrinterRoute(
      kind: PrintDocumentKind.receipt,
      deviceId: 'receipt',
      designProfileId: 'unsupported-design',
      updatedAt: now,
    ));
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: const [],
      transports: const [],
    );
    final runtime = PrintingRuntime(
      repository: repository,
      coordinator: coordinator,
    );
    addTearDown(runtime.dispose);
    addTearDown(coordinator.dispose);

    final surfacedError = runtime.snapshots
        .firstWhere((snapshot) => snapshot.error != null)
        .then((snapshot) => snapshot.error);
    await expectLater(runtime.start(), throwsA(isA<StateError>()));
    expect(runtime.isRunning, isFalse);
    expect(await surfacedError, contains('renderer kayıtlı değil'));
  });
}
