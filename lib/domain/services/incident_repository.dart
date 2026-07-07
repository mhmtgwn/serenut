// lib/domain/services/incident_repository.dart
// Incident Repository — deduplicated incident access layer on top of SyncTraceService.

import 'package:serenutos/domain/services/sync_trace_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

/// Provides high-level access to incident data with deduplication via fingerprinting.
class IncidentRepository {
  final SyncTraceService _tracer;

  IncidentRepository({SyncTraceService? tracer})
      : _tracer = tracer ?? SyncTraceService();

  /// Returns all incidents from the last [hours] hours, deduplicated by fingerprint.
  ///
  /// Incidents with the same fingerprint (same error type + entity + transition)
  /// are merged into a single [DedupedIncident] with an occurrence count.
  Future<List<DedupedIncident>> getDeduplicatedIncidents({int hours = 48}) async {
    final incidents = await _tracer.getRecentCriticals(hours: hours);
    final byFingerprint = <String, List<SyncIncident>>{};

    for (final incident in incidents) {
      byFingerprint
          .putIfAbsent(incident.fingerprint, () => [])
          .add(incident);
    }

    return byFingerprint.entries.map((e) {
      final group = e.value..sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
      return DedupedIncident(
        fingerprint: e.key,
        occurrences: group.length,
        mostRecent: group.first,
        firstSeen: group.last.firstSeen,
        hasCritical: group.any((i) => i.hasCritical),
        representativeEvent: group.first.events
            .where((ev) => ev.level.index >= LogLevel.error.index)
            .map((ev) => ev.event)
            .firstOrNull ?? 'unknown',
      );
    }).toList()
      ..sort((a, b) => b.mostRecent.firstSeen.compareTo(a.mostRecent.firstSeen));
  }

  /// Returns all correlationIds associated with a specific [saleId].
  Future<List<String>> getCorrelationIdsForSale(String saleId) async {
    final all = await _tracer.getAllTelemetryEvents();
    return all
        .where((e) =>
            e.metadata['sale_id'] == saleId ||
            e.metadata['saleId'] == saleId)
        .map((e) => e.correlationId)
        .toSet()
        .toList();
  }

  /// Exports a complete session report as a structured JSON map.
  /// Useful for attaching to support tickets or crash reports.
  Future<Map<String, dynamic>> exportSessionReport(String sessionId) async {
    final transitions = await _tracer.getSessionTransitions(sessionId);
    final formatted = await _tracer.formatSessionTrace(sessionId);

    return {
      'sessionId': sessionId,
      'exportedAt': DateTime.now().toIso8601String(),
      'transitions': transitions,
      'humanReadable': formatted,
      'transitionCount': transitions.length,
    };
  }
}

/// A group of identical incidents (same fingerprint) with an occurrence count.
class DedupedIncident {
  final String fingerprint;
  final int occurrences;
  final SyncIncident mostRecent;
  final DateTime firstSeen;
  final bool hasCritical;
  final String representativeEvent;

  const DedupedIncident({
    required this.fingerprint,
    required this.occurrences,
    required this.mostRecent,
    required this.firstSeen,
    required this.hasCritical,
    required this.representativeEvent,
  });

  Duration get totalDuration => mostRecent.firstSeen.difference(firstSeen);
}
