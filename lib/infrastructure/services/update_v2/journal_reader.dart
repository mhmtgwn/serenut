// lib/infrastructure/services/update_v2/journal_reader.dart
// Serenut Platform — Client NDJSON Journal Reader

import 'dart:convert';
import 'dart:io';
import 'package:serenutos/domain/models/update_v2/journal_record.dart';

abstract class JournalReader {
  /// Reads all journal records from log file. Returns valid records.
  Future<List<JournalRecord>> read();

  /// Tails only the last N lines from the log file.
  Future<List<JournalRecord>> tail(int n);

  /// Exports the log file content as an NDJSON string.
  Future<String> export();
}

class DiskJournalReader implements JournalReader {
  final File _logFile;

  DiskJournalReader(this._logFile);

  @override
  Future<List<JournalRecord>> read() async {
    if (!await _logFile.exists()) {
      return [];
    }

    final records = <JournalRecord>[];
    try {
      final lines = await _logFile.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final map = jsonDecode(trimmed) as Map<String, dynamic>;
          records.add(JournalRecord.fromJson(map));
        } catch (_) {
          // Skip corrupted line
        }
      }
    } catch (_) {
      // Return whatever we could read
    }
    return records;
  }

  @override
  Future<List<JournalRecord>> tail(int n) async {
    if (!await _logFile.exists()) {
      return [];
    }

    final records = <JournalRecord>[];
    try {
      final lines = await _logFile.readAsLines();
      final tailLines =
          lines.length <= n ? lines : lines.sublist(lines.length - n);
      for (final line in tailLines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final map = jsonDecode(trimmed) as Map<String, dynamic>;
          records.add(JournalRecord.fromJson(map));
        } catch (_) {
          // Skip corrupted line
        }
      }
    } catch (_) {
      // Fail-soft
    }
    return records;
  }

  @override
  Future<String> export() async {
    if (!await _logFile.exists()) {
      return '';
    }
    return await _logFile.readAsString();
  }
}
