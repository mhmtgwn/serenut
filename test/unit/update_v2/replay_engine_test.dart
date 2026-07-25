// test/unit/update_v2/replay_engine_test.dart
// Serenut Platform — FSM Crash Recovery Replay Engine Unit Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/update_v2/replay_engine.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_writer.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_reader.dart';

void main() {
  group('ReplayEngine Recovery & Integrity Tests', () {
    late File tempFile;
    late DiskJournalWriter writer;
    late DiskJournalReader reader;
    late ReplayEngine replayEngine;

    setUp(() async {
      tempFile = File(path('test_replay_journal.log'));
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      writer = DiskJournalWriter(tempFile);
      await writer.initialize();
      reader = DiskJournalReader(tempFile);
      replayEngine = ReplayEngine(reader);
    });

    tearDown(() async {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });

    test('Reports isComplete as true when session ends with COMPLETED', () async {
      await writer.append(
        correlationId: 'corr-c1',
        eventType: 'DOWNLOAD_STARTED',
        state: 'DOWNLOADING',
        payload: {},
      );
      await writer.append(
        correlationId: 'corr-c1',
        eventType: 'INSTALL_SUCCESS',
        state: 'COMPLETED',
        payload: {},
      );
      await writer.flush();

      final result = await replayEngine.replay();
      expect(result.isComplete, isTrue);
      expect(result.lastState, equals('COMPLETED'));
      expect(result.lastSuccessfulState, equals('COMPLETED'));
      expect(result.isCorrupted, isFalse);
    });

    test('Reports isComplete as false (crash) when session hangs mid-update', () async {
      await writer.append(
        correlationId: 'corr-c2',
        eventType: 'DOWNLOAD_STARTED',
        state: 'DOWNLOADING',
        payload: {},
      );
      await writer.flush();

      final result = await replayEngine.replay();
      expect(result.isComplete, isFalse);
      expect(result.lastState, equals('DOWNLOADING'));
      expect(result.isCorrupted, isFalse);
    });

    test('Identifies corrupted entries when checksum does not match', () async {
      await writer.append(
        correlationId: 'corr-c3',
        eventType: 'DOWNLOAD_STARTED',
        state: 'DOWNLOADING',
        payload: {},
      );
      await writer.flush();

      // Tamper with file directly on disk (replace payload or checksum)
      final content = await tempFile.readAsString();
      final tampered = content.replaceAll('"checksum":"', '"checksum":"tampered_checksum_');
      await tempFile.writeAsString(tampered);

      final result = await replayEngine.replay();
      expect(result.isCorrupted, isTrue);
    });
  });
}

String path(String name) {
  return Directory.systemTemp.path + Platform.pathSeparator + name;
}
