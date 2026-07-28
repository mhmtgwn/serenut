// lib/infrastructure/services/update_v2/journal_writer.dart
// Serenut Platform — Client NDJSON Journal Writer

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:serenutos/domain/models/update_v2/journal_record.dart';

abstract class JournalWriter {
  /// Appends a new event and returns the newly written sequence number.
  Future<int> append({
    required String correlationId,
    required String eventType,
    required String state,
    required Map<String, dynamic> payload,
  });

  /// Ensures all buffered bytes are flushed to physical disk storage.
  Future<void> flush();
}

class DiskJournalWriter implements JournalWriter {
  final File _logFile;
  int _nextSequenceNumber = 1;
  Future<void> _writeQueue = Future.value();

  DiskJournalWriter(this._logFile);

  /// Initializes next sequence number by reading last line of log if it exists.
  Future<void> initialize() async {
    if (!await _logFile.exists()) {
      _nextSequenceNumber = 1;
      return;
    }

    try {
      final lines = await _logFile.readAsLines();
      if (lines.isNotEmpty) {
        final lastLine = lines.last.trim();
        if (lastLine.isNotEmpty) {
          final decoded = jsonDecode(lastLine);
          final lastSeq = decoded['sequenceNumber'] as int? ?? 0;
          _nextSequenceNumber = lastSeq + 1;
        }
      }
    } catch (_) {
      // Soft fail fallback if file is corrupted
      _nextSequenceNumber = 1;
    }
  }

  @override
  Future<int> append({
    required String correlationId,
    required String eventType,
    required String state,
    required Map<String, dynamic> payload,
  }) async {
    final completer = Completer<int>();

    // Serialize all disk writes sequentially to prevent concurrent file locks/overwrites
    _writeQueue = _writeQueue.then((_) async {
      try {
        final record = JournalRecord.create(
          correlationId: correlationId,
          sequenceNumber: _nextSequenceNumber,
          eventType: eventType,
          state: state,
          payload: payload,
        );

        final line = jsonEncode(record.toJson()) + '\n';
        
        // Ensure parent directory exists
        final parent = _logFile.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }

        await _logFile.writeAsString(line, mode: FileMode.append, flush: true);
        
        final currentSeq = _nextSequenceNumber;
        _nextSequenceNumber++;
        completer.complete(currentSeq);
      } catch (err) {
        completer.completeError(err);
      }
    });

    return completer.future;
  }

  @override
  Future<void> flush() async {
    // Await any pending writes in queue to finish flushing
    await _writeQueue;
  }
}
