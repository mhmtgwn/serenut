import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/terminal_payment_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await DatabaseManager().close();
    DatabaseManager.overrideDatabasePath = null;
  });

  test('pending POS intent is durable and idempotent until ledger commits',
      () async {
    final journal = TerminalPaymentJournal();
    final firstId = await journal.recordPending(
      idempotencyKey: 'sale-42-card',
      terminalTransactionId: 'pos-42',
      amount: 42,
      currency: 'TRY',
      contextType: 'sale',
      contextId: 'sale-42',
    );
    final duplicateId = await journal.recordPending(
      idempotencyKey: 'sale-42-card',
      terminalTransactionId: 'pos-42',
      amount: 42,
      currency: 'TRY',
      contextType: 'sale',
    );

    expect(duplicateId, firstId);
    expect((await journal.findOpenIntents()).single['state'], 'pending');

    await journal.markAuthorized(firstId, 'AUTH-42');
    expect((await journal.findOpenIntents()).single['state'], 'authorized');

    await journal.markCommitted(firstId, contextId: 'sale-42');
    expect(await journal.findOpenIntents(), isEmpty);
  });
}
