// lib/domain/services/sync_trace_service.dart
// Incident Debugging System — correlationId trace viewer + CRITICAL log query.
//
// Provides two complementary views of system incidents:
//   1. Telemetry-based: correlationId → full structured log chain
//   2. State-based:    sessionId → full SyncStateMachine transition chain

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

// ── Fingerprint helper ────────────────────────────────────────────────────────

/// Generates a stable 8-char incident fingerprint from the combination of
/// [errorType], [entityId], and [transitionType].
///
/// Identical incidents (same error on same entity in the same state) produce
/// the same fingerprint, allowing deduplication in the incident dashboard.
/// Prevents "1 bug → 1000 log entries" flooding.
String incidentFingerprint({
  required String errorType,
  String? entityId,
  String? transitionType,
}) {
  final raw = '$errorType|${entityId ?? ''}|${transitionType ?? ''}';
  // Stable djb2-style hash — deterministic across runs (no randomness)
  var hash = 5381;
  for (final codeUnit in raw.codeUnits) {
    hash = ((hash << 5) + hash) ^ codeUnit;
    hash &= 0x7FFFFFFF; // keep positive 31-bit
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// ── Data models ───────────────────────────────────────────────────────────────

/// One step in a reconstructed sync trace.
class SyncTraceEntry {
  final DateTime timestamp;
  final String event;
  final LogLevel level;
  final String correlationId;
  final Map<String, dynamic> metadata;

  const SyncTraceEntry({
    required this.timestamp,
    required this.event,
    required this.level,
    required this.correlationId,
    required this.metadata,
  });

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] ${level.label} $event (corr:$correlationId)';
}

/// Summary of a sync incident — all CRITICAL/ERROR events in a time window.
class SyncIncident {
  final String correlationId;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<SyncTraceEntry> events;
  final bool hasCritical;

  /// Stable 8-char fingerprint: hash(errorType + entityId + transitionType).
  /// Identical incidents share a fingerprint — use for deduplication/grouping.
  final String fingerprint;

  SyncIncident({
    required this.correlationId,
    required this.events,
  })  : firstSeen = events.first.timestamp,
        lastSeen = events.last.timestamp,
        hasCritical = events.any((e) => e.level == LogLevel.critical),
        fingerprint = incidentFingerprint(
          errorType: events
                  .where((e) => e.level.index >= LogLevel.error.index)
                  .map((e) => e.event)
                  .firstOrNull ??
              'unknown',
          entityId: events
              .expand((e) => [
                    e.metadata['customerId'],
                    e.metadata['sale_id'],
                    e.metadata['saleId'],
                  ])
              .whereType<String>()
              .firstOrNull,
          transitionType: events
              .map((e) => e.metadata['trigger_event'] as String?)
              .whereType<String>()
              .firstOrNull,
        );

  Duration get duration => lastSeen.difference(firstSeen);
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Reconstructs incident traces from telemetry logs and sync state history.
class SyncTraceService {
  final TelemetryService _telemetry;
  final Database? _db;

  SyncTraceService({
    TelemetryService? telemetry,
    Database? db,
  })  : _telemetry = telemetry ?? TelemetryService(),
        _db = db;

  // ── Telemetry-based trace ──────────────────────────────────────────────────

  /// Raw access to all telemetry events (used by IncidentRepository).
  Future<List<TelemetryEvent>> getAllTelemetryEvents() =>
      _telemetry.getEvents();

  /// Returns all telemetry events that share the given [correlationId],
  /// in chronological order. Use this to reconstruct a full request trace.
  ///
  /// Example:
  /// ```dart
  /// final trace = await tracer.getTrace('S741Pc5m7dLod1Dy');
  /// for (final entry in trace) {
  ///   print(entry);
  /// }
  /// ```
  Future<List<SyncTraceEntry>> getTrace(String correlationId) async {
    final all = await _telemetry.getEvents();
    return all
        .where((e) => e.correlationId == correlationId)
        .map((e) => SyncTraceEntry(
              timestamp: e.timestamp,
              event: e.event,
              level: e.level,
              correlationId: e.correlationId,
              metadata: e.metadata,
            ))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Returns all CRITICAL and ERROR events from the last [hours] hours,
  /// grouped by correlationId as [SyncIncident] objects.
  ///
  /// Use this for a "recent incidents" dashboard view.
  Future<List<SyncIncident>> getRecentCriticals({int hours = 24}) async {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final all = await _telemetry.getEventsByLevel(LogLevel.error);

    final recent = all.where((e) => e.timestamp.isAfter(cutoff)).toList();

    // Group by correlationId
    final grouped = <String, List<TelemetryEvent>>{};
    for (final e in recent) {
      grouped.putIfAbsent(e.correlationId, () => []).add(e);
    }

    return grouped.entries
        .map((entry) => SyncIncident(
              correlationId: entry.key,
              events: entry.value
                  .map((e) => SyncTraceEntry(
                        timestamp: e.timestamp,
                        event: e.event,
                        level: e.level,
                        correlationId: e.correlationId,
                        metadata: e.metadata,
                      ))
                  .toList()
                ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
            ))
        .toList()
      ..sort((a, b) => b.firstSeen.compareTo(a.firstSeen)); // newest first
  }

  // ── State machine trace ────────────────────────────────────────────────────

  /// Returns all state transitions for a given [sessionId] from the DB.
  /// Useful for replaying exactly what the sync engine did during an incident.
  ///
  /// Returns `[]` if the DB is not available (e.g. in web environments).
  Future<List<Map<String, dynamic>>> getSessionTransitions(
      String sessionId) async {
    if (_db == null) return [];
    return _db!.query(
      'sync_state_log',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'occurred_at ASC',
    );
  }

  /// Returns the [count] most recent sync sessions from the state log.
  Future<List<String>> getRecentSessions({int count = 20}) async {
    if (_db == null) return [];
    final rows = await _db!.rawQuery('''
      SELECT DISTINCT session_id, MIN(occurred_at) AS first_at
      FROM sync_state_log
      GROUP BY session_id
      ORDER BY first_at DESC
      LIMIT ?
    ''', [count]);
    return rows.map((r) => r['session_id'] as String).toList();
  }

  /// Formats a session trace as a human-readable string for debugging.
  Future<String> formatSessionTrace(String sessionId) async {
    final transitions = await getSessionTransitions(sessionId);
    if (transitions.isEmpty) return 'No transitions found for $sessionId';

    final buf = StringBuffer('── Sync Session: $sessionId ──\n');
    for (final row in transitions) {
      final meta = row['metadata'] != null
          ? jsonDecode(row['metadata'] as String)
          : null;
      buf.writeln(
        '  ${row['occurred_at']}  '
        '${row['from_state']} → ${row['to_state']}'
        '  [${row['trigger_event']}]'
        '${row['sale_id'] != null ? "  sale:${row['sale_id']}" : ""}'
        '${meta != null ? "  $meta" : ""}',
      );
    }
    return buf.toString();
  }
}
