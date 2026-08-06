import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_printing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqlitePrintingRepository repository;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseSchema.createTables(db);
    repository = SqlitePrintingRepository(DbGatewayImpl.raw(db));
  });

  tearDown(() => db.close());

  PrintDesignProfile profile(PrintDocumentKind kind, String id,
          {bool isDefault = true}) =>
      PrintDesignProfile(
        id: id,
        name: id,
        kind: kind,
        schemaVersion: 1,
        rendererVersion: switch (kind) {
          PrintDocumentKind.receipt => 'escpos-v1',
          PrintDocumentKind.productLabel => 'tspl-product-v1',
          PrintDocumentKind.orderLabel => 'tspl-order-v1',
        },
        definition: const {'showLogo': true},
        isDefault: isDefault,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  PrinterDeviceProfile device(String id, PrinterLanguage language) =>
      PrinterDeviceProfile(
        id: id,
        name: id,
        language: language,
        transport: PrinterTransportKind.tcp,
        transportConfig: const {'host': '192.168.1.20', 'port': 9100},
        capabilities: const {'dpi': 203, 'printableWidthDots': 384},
        enabled: true,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  test('only one default design profile remains per document kind', () async {
    await repository.saveDesignProfile(profile(PrintDocumentKind.receipt, 'a'));
    await repository.saveDesignProfile(profile(PrintDocumentKind.receipt, 'b'));

    final profiles =
        await repository.getDesignProfiles(PrintDocumentKind.receipt);
    expect(profiles.where((value) => value.isDefault).single.id, 'b');
  });

  test('route rejects incompatible printer language', () async {
    await repository
        .saveDesignProfile(profile(PrintDocumentKind.productLabel, 'product'));
    await repository.saveDevice(device('receipt', PrinterLanguage.escPos));

    expect(
      () => repository.saveRoute(PrinterRoute(
        kind: PrintDocumentKind.productLabel,
        deviceId: 'receipt',
        designProfileId: 'product',
        updatedAt: DateTime.utc(2026),
      )),
      throwsA(isA<PrintingConfigurationException>()),
    );
  });

  test('route is explicit and prevents deleting its active device', () async {
    await repository
        .saveDesignProfile(profile(PrintDocumentKind.orderLabel, 'order'));
    await repository.saveDevice(device('label', PrinterLanguage.tspl));
    await repository.saveRoute(PrinterRoute(
      kind: PrintDocumentKind.orderLabel,
      deviceId: 'label',
      designProfileId: 'order',
      updatedAt: DateTime.utc(2026),
    ));

    expect((await repository.getRoute(PrintDocumentKind.orderLabel))!.deviceId,
        'label');
    expect(() => repository.deleteDevice('label'),
        throwsA(isA<PrintingConfigurationException>()));
  });

  test('recoverable jobs retain immutable device and design snapshots',
      () async {
    final now = DateTime.now();
    final job = PrintJobRecord(
      id: 'job-1',
      kind: PrintDocumentKind.productLabel,
      payloadJson: jsonEncode({'name': 'Ürün'}),
      copies: 1,
      designProfileId: 'product',
      designSnapshotJson: jsonEncode({'showPrice': true}),
      deviceId: 'label-a',
      transportSnapshotJson: '{}',
      capabilitySnapshotJson: jsonEncode({'mediaWidthMm': 50}),
      rendererVersion: 'tspl-v1',
      state: PrintJobState.queued,
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    await repository.createJob(job);

    final recovered = (await repository.getRecoverableJobs()).single;
    expect(recovered.deviceId, 'label-a');
    expect(recovered.designSnapshotJson, job.designSnapshotJson);
    expect(recovered.capabilitySnapshotJson, job.capabilitySnapshotJson);
  });

  test('enqueue resolves route once and atomically snapshots configuration',
      () async {
    await repository.saveDesignProfile(
        profile(PrintDocumentKind.receipt, 'receipt-design'));
    await repository.saveDevice(device('receipt-a', PrinterLanguage.escPos));
    await repository.saveRoute(PrinterRoute(
      kind: PrintDocumentKind.receipt,
      deviceId: 'receipt-a',
      designProfileId: 'receipt-design',
      updatedAt: DateTime.utc(2026),
    ));

    final job = await repository.enqueue(
      kind: PrintDocumentKind.receipt,
      payloadJson: jsonEncode({'saleId': 'sale-1'}),
      copies: 2,
    );
    expect(job.deviceId, 'receipt-a');
    expect(job.designProfileId, 'receipt-design');
    expect(job.state, PrintJobState.queued);
    expect(job.copies, 2);
  });

  test('claim is device-scoped and creates one attempt record', () async {
    final now = DateTime.now();
    await repository.createJob(PrintJobRecord(
      id: 'job-a',
      kind: PrintDocumentKind.receipt,
      payloadJson: '{}',
      copies: 1,
      designProfileId: 'design',
      designSnapshotJson: '{}',
      deviceId: 'receipt-a',
      transportSnapshotJson: '{}',
      capabilitySnapshotJson: '{}',
      rendererVersion: 'escpos-v1',
      state: PrintJobState.queued,
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    ));

    expect(await repository.claimNext('receipt-b'), isNull);
    final claimed = await repository.claimNext('receipt-a');
    expect(claimed!.state, PrintJobState.rendering);
    expect(claimed.attemptCount, 1);
    expect(await repository.claimNext('receipt-a'), isNull);
    expect(await db.query('print_job_attempts'), hasLength(1));
  });

  test('startup recovery requeues rendering but quarantines sending', () async {
    final now = DateTime.now();
    Future<void> insert(String id, PrintJobState state) =>
        db.insert('print_jobs', {
          'id': id,
          'kind': 'receipt',
          'payload_json': '{}',
          'copies': 1,
          'design_profile_id': 'design',
          'design_snapshot_json': '{}',
          'device_id': 'receipt-a',
          'transport_snapshot_json': '{}',
          'capability_snapshot_json': '{}',
          'renderer_version': 'escpos-v1',
          'state': state.name,
          'attempt_count': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
    await insert('safe', PrintJobState.rendering);
    await insert('ambiguous', PrintJobState.sending);

    final summary = await repository.recoverInterruptedJobs();
    expect(summary.safelyRequeued, 1);
    expect(summary.awaitingUserCheck, 1);
    final rows = await db.query('print_jobs', orderBy: 'id');
    expect(rows.first['state'], PrintJobState.awaitingUserCheck.name);
    expect(rows.last['state'], PrintJobState.queued.name);
  });
}
