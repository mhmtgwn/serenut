import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/printer_service.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockSocket implements Socket {
  final List<int> writtenBytes = [];
  bool isClosed = false;
  bool isFlushed = false;

  @override
  void add(List<int> data) {
    writtenBytes.addAll(data);
  }

  @override
  Future<void> flush() async {
    isFlushed = true;
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
  });

  group('Persistent Print Queue Retry Integration Tests', () {
    late PersistentPrintQueue printQueue;
    late PrinterService printerService;
    late Settings testSettings;
    late MockSocket mockSocket;
    bool shouldFail = true;

    setUp(() async {
      printQueue = PersistentPrintQueue(testKey: 'retry_test_queue');
      await printQueue.clearAll();
      mockSocket = MockSocket();
      shouldFail = true;

      // Inject custom socket connector that fails dynamically
      printerService = PrinterService((ip, port, {timeout}) async {
        if (shouldFail) {
          throw const SocketException('Yazici baglantisi koptu');
        }
        return mockSocket;
      }, printQueue);

      testSettings = Settings(
        businessName: 'Deneme POS',
        businessPhone: '555-555-5555',
        businessAddress: 'Istanbul, TR',
        printerIp: '192.168.1.100',
        printerPort: 9100,
        paperWidth: 80,
        printQRCode: true,
        currency: 'TL',
      );
    });

    test('Failed print enqueues job, then successful retry clears it from queue', () async {
      // 1. Trigger print when shouldFail is true -> Should throw exception and write to print_queue table
      shouldFail = true;
      
      await expectLater(
        printerService.printDiagnosticsTest(testSettings, 80),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('kuyruga alindi'))),
      );

      // Verify that print_queue table has 1 pending job
      var pending = await printQueue.loadPending();
      expect(pending.length, 1);
      expect(pending.first.status, PrintJobStatus.pending);

      // 2. Set shouldFail to false (printer fixed) and run processPendingQueue
      shouldFail = false;
      await printerService.processPendingQueue(testSettings);

      // Verify that job is marked success and no longer pending
      pending = await printQueue.loadPending();
      expect(pending.length, 0);

      final all = await printQueue.loadAll();
      expect(all.length, 1);
      expect(all.first.status, PrintJobStatus.success);

      // Verify mock socket received the diagnostics page bytes
      expect(mockSocket.writtenBytes, isNotEmpty);
      expect(mockSocket.isClosed, isTrue);
    });
  });
}
