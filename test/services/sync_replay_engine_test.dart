// test/services/sync_replay_engine_test.dart
// Unit tests for the Incident Replay Engine & Heuristic Diagnosis classifier.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/sync_replay_engine.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/domain/services/sync_trace_service.dart';

Future<Database> _openTestDb() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE sync_state_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      from_state TEXT NOT NULL,
      to_state TEXT NOT NULL,
      trigger_event TEXT NOT NULL,
      sale_id TEXT,
      device_id TEXT,
      metadata TEXT,
      occurred_at TEXT NOT NULL
    )
  ''');
  return db;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SyncReplayEngine — Diagnostic Classification Tests', () {
    late Database db;
    late TelemetryService telemetry;
    late SyncTraceService tracer;
    late SyncReplayEngine engine;

    setUp(() async {
      db = await _openTestDb();
      telemetry = TelemetryService();
      await telemetry.clearLogs();
      tracer = SyncTraceService(db: db, telemetry: telemetry);
      engine = SyncReplayEngine(db: db, tracer: tracer);
    });

    tearDown(() async {
      await db.close();
    });

    test('Should merge telemetry logs and state transitions chronologically',
        () async {
      const corrId = 'session-replay-1';

      // 1. Simulate transition at t=0
      final machine = SyncStateMachine(db: db, sessionId: corrId);
      await machine.transition(SyncTrigger.startSync); // t0

      // 2. Simulate telemetry log at t=1 (slightly later)
      await Future.delayed(const Duration(milliseconds: 10));
      await telemetry.logStructured(
        event: 'http_post_sale',
        level: LogLevel.info,
        correlationId: corrId,
        metadata: {'saleId': 'sale-123'},
      );

      // 3. Simulate conflict transition at t=2
      await Future.delayed(const Duration(milliseconds: 10));
      await machine.transition(
        SyncTrigger.pushConflict,
        saleId: 'sale-123',
        metadata: {'http_status': 409},
      );

      final report = await engine.generateReport(corrId);

      expect(report.correlationId, equals(corrId));
      expect(report.steps.length, equals(3));

      // Verify chronological sorting (t0 < t1 < t2)
      expect(report.steps[0].type, equals('transition')); // startSync
      expect(report.steps[0].title, contains('State Transition'));

      expect(report.steps[1].type, equals('log')); // http_post_sale
      expect(report.steps[1].title, contains('http_post_sale'));

      expect(report.steps[2].type, equals('transition')); // pushConflict
      expect(report.steps[2].description, contains('conflictDetected'));
    });

    test('Heuristic: Classifies NetworkTimeout correctly', () async {
      const corrId = 'session-replay-network';
      final machine = SyncStateMachine(db: db, sessionId: corrId);
      await machine.transition(SyncTrigger.startSync);

      await telemetry.logError(
        const SocketException(
            'Connection timed out (NetworkCutFault simulated)'),
        StackTrace.current,
        context: 'OfflineSyncService._syncSaleWithRetry',
        correlationId: corrId,
      );

      final report = await engine.generateReport(corrId);
      expect(report.rootCause, equals(RootCauseCategory.networkTimeout));
      expect(report.diagnosis, contains('Connection was lost or timed out'));
    });

    test('Heuristic: Classifies DuplicatePush correctly', () async {
      const corrId = 'session-replay-conflict';
      final machine = SyncStateMachine(db: db, sessionId: corrId);
      await machine.transition(SyncTrigger.startSync);

      await machine.transition(
        SyncTrigger.pushConflict,
        saleId: 'sale-1',
        metadata: {'http_status': 409},
      );

      final report = await engine.generateReport(corrId);
      expect(report.rootCause, equals(RootCauseCategory.duplicatePush));
      expect(report.diagnosis, contains('409 Conflict'));
    });

    test('Heuristic: Classifies DataCorruption correctly', () async {
      const corrId = 'session-replay-drift';

      await telemetry.logStructured(
        event: 'silent_data_corruption_alarm',
        level: LogLevel.critical,
        correlationId: corrId,
        metadata: {'drift': 12.50, 'customerId': 'cust-1'},
      );

      final report = await engine.generateReport(corrId);
      expect(report.rootCause, equals(RootCauseCategory.dataCorruption));
      expect(report.diagnosis, contains('balance drift check failed'));
    });

    test('Heuristic: Classifies LicenseFailure correctly', () async {
      const corrId = 'session-replay-license';

      await telemetry.logStructured(
        event: 'sync_license_invalid',
        level: LogLevel.error,
        correlationId: corrId,
        metadata: {'reason': 'Invalid or missing license token'},
      );

      final report = await engine.generateReport(corrId);
      expect(report.rootCause, equals(RootCauseCategory.licenseFailure));
      expect(report.diagnosis, contains('Licensing verification failed'));
    });
  });
}
