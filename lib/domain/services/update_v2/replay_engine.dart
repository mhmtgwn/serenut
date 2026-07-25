// lib/domain/services/update_v2/replay_engine.dart
// Serenut Platform — FSM Crash Recovery Replay Engine

import 'package:serenutos/domain/models/update_v2/journal_record.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_reader.dart';

class ReplayResult {
  final String? lastState;
  final String? lastSuccessfulState;
  final String? lastCorrelationId;
  final String? lastTimestamp;
  final bool isComplete;
  final bool isCorrupted;

  ReplayResult({
    this.lastState,
    this.lastSuccessfulState,
    this.lastCorrelationId,
    this.lastTimestamp,
    required this.isComplete,
    required this.isCorrupted,
  });
}

class ReplayEngine {
  final JournalReader _reader;

  ReplayEngine(this._reader);

  /// Performs full analysis on the update log file to identify crash states and check integrity.
  Future<ReplayResult> replay() async {
    final records = await _reader.read();
    if (records.isEmpty) {
      return ReplayResult(isComplete: true, isCorrupted: false);
    }

    String? lastState;
    String? lastSuccessfulState;
    String? lastCorrelationId;
    String? lastTimestamp;
    bool isCorrupted = false;

    // Check integrity of every line in log
    for (final record in records) {
      if (!record.verify()) {
        isCorrupted = true;
      }
      lastState = record.state;
      lastCorrelationId = record.correlationId;
      lastTimestamp = record.timestamp;

      if (record.state == 'COMPLETED' || record.state == 'FAILED') {
        lastSuccessfulState = record.state;
      }
    }

    // A session is incomplete/crashed if it did not end in COMPLETED or FAILED state
    final bool isComplete = lastState == 'COMPLETED' || lastState == 'FAILED';

    return ReplayResult(
      lastState: lastState,
      lastSuccessfulState: lastSuccessfulState,
      lastCorrelationId: lastCorrelationId,
      lastTimestamp: lastTimestamp,
      isComplete: isComplete,
      isCorrupted: isCorrupted,
    );
  }
}
