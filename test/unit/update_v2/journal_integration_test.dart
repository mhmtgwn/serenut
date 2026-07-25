// test/unit/update_v2/journal_integration_test.dart
// Serenut Platform — Event Bus -> Journal Writer Observer Integration Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/update_v2/update_context.dart';
import 'package:serenutos/domain/services/update_v2/update_state_machine.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_event_bus.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_writer.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_reader.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_event_listener.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_trigger_manager.dart';

void main() {
  group('Journal Event Bus Integration Tests', () {
    late File tempFile;
    late UpdateEventBus eventBus;
    late DiskJournalWriter journalWriter;
    late DiskJournalReader journalReader;
    late JournalEventListener eventListener;
    late UpdateStateMachine fsm;
    late UpdateContext context;

    setUp(() async {
      tempFile = File(path('test_integration_journal.log'));
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      
      eventBus = UpdateEventBus();
      journalWriter = DiskJournalWriter(tempFile);
      await journalWriter.initialize();
      journalReader = DiskJournalReader(tempFile);
      
      eventListener = JournalEventListener(
        eventBus: eventBus,
        journalWriter: journalWriter,
      );
      eventListener.startListening();

      fsm = UpdateStateMachine(eventBus: eventBus, deviceId: 'dev-100');
      context = UpdateContext(
        correlationId: 'upd-integration-99',
        triggerSource: TriggerSource.startup,
      );
    });

    tearDown(() async {
      eventListener.stopListening();
      eventBus.dispose();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });

    test('FSM transitions automatically trigger append-only log writes', () async {
      // Transition FSM: Idle -> Checking
      await fsm.transitionTo(context, UpdateState.checking);
      
      // Wait briefly for async event bus delivery and serialized file write
      await Future.delayed(const Duration(milliseconds: 200));
      await journalWriter.flush();

      // Verify record exists in log file
      final records = await journalReader.read();
      expect(records.length, equals(1));
      expect(records[0].correlationId, equals('upd-integration-99'));
      expect(records[0].state, equals('CHECKING'));
      expect(records[0].verify(), isTrue);
    });
  });
}

String path(String name) {
  return Directory.systemTemp.path + Platform.pathSeparator + name;
}
