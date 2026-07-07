import 'dart:math';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

class ObservabilityService {
  final IFinancialTransactionRepository _transactionRepository;

  ObservabilityService({
    required IFinancialTransactionRepository transactionRepository,
  }) : _transactionRepository = transactionRepository;

  /// Calculates the logical clock inversion rate (drift rate).
  /// Measures the discrepancy between physical date ordering and Lamport clock ordering.
  double calculateDriftRate(List<FinancialTransactionEntity> transactions) {
    if (transactions.length < 2) return 0.0;

    // Sort chronologically by physical timestamp
    final chrono = List<FinancialTransactionEntity>.from(transactions);
    chrono.sort((a, b) => a.date.compareTo(b.date));

    int inversions = 0;
    int totalPairs = 0;

    for (int i = 0; i < chrono.length; i++) {
      for (int j = i + 1; j < chrono.length; j++) {
        totalPairs++;
        // If chronological first has a higher logical clock, it's an inversion
        if (chrono[i].logicalClock > chrono[j].logicalClock) {
          inversions++;
        }
      }
    }

    return inversions / max(1, totalPairs);
  }

  /// Calculates and returns comprehensive system health metrics by auditing local transactions and telemetry logs.
  Future<Map<String, dynamic>> getSystemHealthMetrics() async {
    final allTxs = await _transactionRepository.findAll();
    final driftRate = calculateDriftRate(allTxs);

    // Read telemetry logs to count sync failures and anomalies
    int syncSuccessCount = 0;
    int syncFailureCount = 0;
    int anomalyCount = 0;

    try {
      final events = await TelemetryService().getEvents();
      for (final event in events) {
        if (event.event == 'sync_remote_post_failed' || 
            event.event == 'sync_run_unhandled_exception' ||
            event.event.contains('failed')) {
          syncFailureCount++;
        } else if (event.event == 'sync_success' || event.event == 'push_success' || event.event.contains('success')) {
          syncSuccessCount++;
        } else if (event.event == 'sync_security_anomaly_detected') {
          anomalyCount++;
        }
      }
    } catch (_) {
      // Fallback silently if logs aren't accessible
    }

    final totalSyncAttempts = syncSuccessCount + syncFailureCount;
    final failureRate = totalSyncAttempts > 0 
        ? syncFailureCount / totalSyncAttempts 
        : 0.0;

    return {
      'drift_rate': driftRate,
      'sync_failure_rate': failureRate,
      'anomaly_count': anomalyCount,
      'total_transactions': allTxs.length,
      'sync_success_count': syncSuccessCount,
      'sync_failure_count': syncFailureCount,
    };
  }
}
