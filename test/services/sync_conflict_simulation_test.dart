// test/services/sync_conflict_simulation_test.dart
// Sync Conflict Simulation Framework — Deterministic edge-case coverage
//
// Tests:
//   1. SyncStateMachine: legal transitions persisted to SQLite
//   2. SyncStateMachine: illegal transition throws immediately
//   3. SyncStateMachine: crash recovery restores last known state
//   4. SyncChaosInjector: NetworkCutFault triggers at beforePush hook
//   5. SyncChaosInjector: DelayFault adds measured latency
//   6. SyncChaosInjector: ClockSkewFault advances injector.now()
//   7. SyncChaosInjector: PartialWriteFault fires at afterPushBeforeCommit
//   8. SyncChaosInjector: multiple faults at same hook apply in order
//   9. SyncTraceService: getTrace returns events for correlationId
//  10. SyncTraceService: getRecentCriticals groups by correlationId

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/sync_chaos_injector.dart';
import 'package:serenutos/domain/services/sync_trace_service.dart';

// ── In-memory DB schema ───────────────────────────────────────────────────────

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

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SyncStateMachine — Deterministic Transition Tests', () {
    late Database db;

    setUp(() async => db = await _openTestDb());
    tearDown(() async => db.close());

    // ── 1. Legal transition chain persisted ───────────────────────────────────
    test('Legal transitions: idle → syncing → synced, all written to DB', () async {
      final machine = SyncStateMachine(db: db, deviceId: 'device-A');

      expect(machine.currentState, SyncState.idle);

      await machine.transition(SyncTrigger.startSync);
      expect(machine.currentState, SyncState.syncing);

      await machine.transition(SyncTrigger.noSalesFound);
      expect(machine.currentState, SyncState.synced);

      final rows = await machine.getSessionTransitions();
      expect(rows.length, equals(2));
      expect(rows[0]['from_state'], 'idle');
      expect(rows[0]['to_state'], 'syncing');
      expect(rows[1]['from_state'], 'syncing');
      expect(rows[1]['to_state'], 'synced');
    });

    // ── 2. Conflict resolution path ───────────────────────────────────────────
    test('Conflict path: syncing → conflictDetected → resolving → syncing', () async {
      final machine = SyncStateMachine(db: db);
      await machine.transition(SyncTrigger.startSync);
      await machine.transition(SyncTrigger.pushConflict,
          saleId: 'sale-conflict-1',
          metadata: {'http_status': 409});

      expect(machine.currentState, SyncState.conflictDetected);

      await machine.transition(SyncTrigger.startSync); // apply merge
      expect(machine.currentState, SyncState.resolving);

      await machine.transition(SyncTrigger.mergeComplete);
      expect(machine.currentState, SyncState.syncing);

      final rows = await machine.getSessionTransitions();
      expect(rows.length, equals(4));
      expect(rows[1]['to_state'], 'conflictDetected');
      expect(rows[1]['sale_id'], 'sale-conflict-1');
    });

    // ── 3. Illegal transition throws immediately ───────────────────────────────
    test('Illegal transition throws InvalidSyncTransitionError', () async {
      final machine = SyncStateMachine(db: db);
      // idle → pushSuccess is not in the transition table
      expect(
        () => machine.transition(SyncTrigger.pushSuccess),
        throwsA(isA<InvalidSyncTransitionError>()),
      );
      // State must remain idle after illegal attempt
      expect(machine.currentState, SyncState.idle);
    });

    // ── 4. Crash recovery restores last state ─────────────────────────────────
    test('Crash recovery: restoreFromCrash() loads last persisted state', () async {
      const session = 'test-session-crash-recovery';
      final machine1 = SyncStateMachine(db: db, sessionId: session);
      await machine1.transition(SyncTrigger.startSync);
      await machine1.transition(SyncTrigger.pushNetworkError);
      // "Crash" here — machine1 goes out of scope

      // New machine with same sessionId simulates app restart
      final machine2 = SyncStateMachine(db: db, sessionId: session);
      expect(machine2.currentState, SyncState.idle); // starts fresh
      await machine2.restoreFromCrash();
      // Last persisted state was 'syncing' (after pushNetworkError loops back)
      expect(machine2.currentState, SyncState.syncing);
    });

    // ── 5. Max retries → failed ───────────────────────────────────────────────
    test('maxRetriesExceeded from syncing → failed', () async {
      final machine = SyncStateMachine(db: db);
      await machine.transition(SyncTrigger.startSync);
      await machine.transition(SyncTrigger.maxRetriesExceeded);
      expect(machine.currentState, SyncState.failed);

      // Manual retry restarts from failed
      await machine.transition(SyncTrigger.startSync);
      expect(machine.currentState, SyncState.syncing);
    });

    // ── 6. Retention purge ────────────────────────────────────────────────────
    test('purgeOldTransitions removes only entries older than retentionDays', () async {
      // Insert a row with a very old timestamp
      await db.insert('sync_state_log', {
        'session_id': 'old-session',
        'from_state': 'idle',
        'to_state': 'syncing',
        'trigger_event': 'startSync',
        'occurred_at': DateTime.now()
            .subtract(const Duration(days: 60))
            .toIso8601String(),
      });

      final machine = SyncStateMachine(db: db);
      await machine.transition(SyncTrigger.startSync); // recent row

      final deleted = await SyncStateMachine.purgeOldTransitions(db,
          retentionDays: 30);
      expect(deleted, equals(1)); // only the old-session row deleted

      final remaining = await db.query('sync_state_log');
      expect(remaining.length, equals(1));
      expect(remaining.first['session_id'], machine.sessionId);
    });
  });

  // ── SyncChaosInjector Tests ───────────────────────────────────────────────

  group('SyncChaosInjector — Fault Injection Tests', () {
    test('NetworkCutFault at beforePush throws SocketException', () async {
      final injector = SyncChaosInjector()
        ..addFault(const NetworkCutFault());

      expect(
        () => injector.trigger(FaultHook.beforePush),
        throwsA(isA<SocketException>()),
      );
    });

    test('DelayFault at beforePush adds measurable latency', () async {
      final injector = SyncChaosInjector()
        ..addFault(const DelayFault(milliseconds: 100));

      final sw = Stopwatch()..start();
      await injector.trigger(FaultHook.beforePush);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(90));
    });

    test('ClockSkewFault: injector.now() is ahead by skew amount', () async {
      final injector = SyncChaosInjector()
        ..addFault(const ClockSkewFault(minutes: 10));

      final before = DateTime.now();
      final injectedNow = injector.now;
      final after = DateTime.now();

      // injectedNow should be ~10 minutes ahead of real now
      expect(injectedNow.isAfter(before.add(const Duration(minutes: 9))), isTrue);
      expect(injectedNow.isBefore(after.add(const Duration(minutes: 11))), isTrue);
    });

    test('PartialWriteFault at afterPushBeforeCommit throws StateError', () async {
      final injector = SyncChaosInjector()
        ..addFault(const PartialWriteFault());

      expect(
        () => injector.trigger(FaultHook.afterPushBeforeCommit, saleId: 'sale-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('DuplicatePushFault sets statusCodeOverride to 409', () {
      final injector = SyncChaosInjector()
        ..addFault(const DuplicatePushFault());

      expect(injector.statusCodeOverride, equals(409));
    });

    test('No fault at hook: trigger() is a no-op', () async {
      final injector = SyncChaosInjector()
        ..addFault(const DelayFault(milliseconds: 200));

      // beforePull has no fault — should complete instantly
      final sw = Stopwatch()..start();
      await injector.trigger(FaultHook.beforePull);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('Multiple faults at same hook apply in registration order', () async {
      final log = <String>[];
      final injector = SyncChaosInjector();

      // We test ordering via DelayFault side effect on elapsed time
      // First: 50ms delay, then: NetworkCut
      injector.addFault(const DelayFault(milliseconds: 50));
      injector.addFault(const NetworkCutFault());

      final sw = Stopwatch()..start();
      try {
        await injector.trigger(FaultHook.beforePush);
      } on SocketException {
        log.add('SocketException');
      }
      sw.stop();

      expect(log, contains('SocketException'));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(40),
          reason: 'DelayFault must fire before NetworkCutFault');
    });

    test('reset() clears all faults and overrides', () async {
      final injector = SyncChaosInjector()
        ..addFault(const ClockSkewFault(minutes: 30))
        ..addFault(const DuplicatePushFault());

      injector.reset();

      expect(injector.statusCodeOverride, isNull);
      expect(injector.hasFaultAt(FaultHook.beforePush), isFalse);
      // Clock should be back to real time (no skew)
      final diff = injector.now.difference(DateTime.now()).inSeconds.abs();
      expect(diff, lessThan(2));
    });
  });

  // ── SyncTraceService Tests ───────────────────────────────────────────────

  group('SyncTraceService — Incident Trace Tests', () {
    late Database db;

    setUp(() async => db = await _openTestDb());
    tearDown(() async => db.close());

    test('getSessionTransitions returns ordered rows for sessionId', () async {
      final machine = SyncStateMachine(db: db, sessionId: 'trace-session');
      await machine.transition(SyncTrigger.startSync);
      await machine.transition(SyncTrigger.noSalesFound);

      final tracer = SyncTraceService(db: db);
      final rows = await tracer.getSessionTransitions('trace-session');

      expect(rows.length, equals(2));
      expect(rows[0]['to_state'], 'syncing');
      expect(rows[1]['to_state'], 'synced');
    });

    test('getRecentSessions returns most recent sessionIds', () async {
      for (var i = 0; i < 3; i++) {
        final m = SyncStateMachine(db: db, sessionId: 'session-$i');
        await m.transition(SyncTrigger.startSync);
      }

      final tracer = SyncTraceService(db: db);
      final sessions = await tracer.getRecentSessions(count: 10);

      expect(sessions.length, equals(3));
    });

    test('formatSessionTrace produces human-readable output', () async {
      final machine =
          SyncStateMachine(db: db, sessionId: 'format-session', deviceId: 'dev-1');
      await machine.transition(SyncTrigger.startSync);
      await machine.transition(SyncTrigger.pushConflict, saleId: 'sale-xyz');

      final tracer = SyncTraceService(db: db);
      final output = await tracer.formatSessionTrace('format-session');

      expect(output, contains('format-session'));
      expect(output, contains('conflictDetected'));
      expect(output, contains('sale-xyz'));
    });
  });
}
