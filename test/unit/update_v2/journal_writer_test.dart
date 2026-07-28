// test/unit/update_v2/journal_writer_test.dart
// Serenut Platform — Journal Writer & Reader Unit Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_writer.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_reader.dart';

void main() {
  group('JournalWriter and JournalReader Tests', () {
    late File tempFile;
    late DiskJournalWriter writer;
    late DiskJournalReader reader;

    setUp(() async {
      tempFile = File(path('test_update_journal.log'));
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      writer = DiskJournalWriter(tempFile);
      await writer.initialize();
      reader = DiskJournalReader(tempFile);
    });

    tearDown(() async {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });

    test('Appends and reads NDJSON logs with correct sequence numbers and checksums', () async {
      final seq1 = await writer.append(
        correlationId: 'corr-1',
        eventType: 'DOWNLOAD_STARTED',
        state: 'DOWNLOADING',
        payload: {'progress': 50},
      );
      expect(seq1, equals(1));

      final seq2 = await writer.append(
        correlationId: 'corr-1',
        eventType: 'DOWNLOAD_COMPLETED',
        state: 'DOWNLOADING',
        payload: {'progress': 100},
      );
      expect(seq2, equals(2));

      await writer.flush();

      // Read back all logs
      final records = await reader.read();
      expect(records.length, equals(2));
      expect(records[0].sequenceNumber, equals(1));
      expect(records[0].correlationId, equals('corr-1'));
      expect(records[0].verify(), isTrue);

      expect(records[1].sequenceNumber, equals(2));
      expect(records[1].verify(), isTrue);
    });

    test('Tails last N lines successfully', () async {
      for (int i = 1; i <= 5; i++) {
        await writer.append(
          correlationId: 'corr-i',
          eventType: 'CHECK_STARTED',
          state: 'CHECKING',
          payload: {'i': i},
        );
      }
      await writer.flush();

      final tailRecords = await reader.tail(2);
      expect(tailRecords.length, equals(2));
      expect(tailRecords[0].sequenceNumber, equals(4));
      expect(tailRecords[1].sequenceNumber, equals(5));
    });
  });
}

String path(String name) {
  return Directory.systemTemp.path + Platform.pathSeparator + name;
}
