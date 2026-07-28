import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Durable evidence for card transactions that have reached a physical POS.
/// `authorized` is deliberately not treated as completed until the local
/// business/ledger transaction has committed.
class TerminalPaymentJournal {
  TerminalPaymentJournal({DatabaseManager? databaseManager})
      : _databaseManager = databaseManager ?? DatabaseManager();

  final DatabaseManager _databaseManager;

  /// Persists intent *before* the terminal request. A timeout after the
  /// terminal has charged the card must be reconciled, never retried blindly.
  Future<String> recordPending({
    required String idempotencyKey,
    required String terminalTransactionId,
    required double amount,
    required String currency,
    required String contextType,
    String? contextId,
  }) async {
    final db = await _databaseManager.getDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query(
      'terminal_payment_intents',
      columns: ['id'],
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as String;

    final id = const Uuid().v4();
    await db.insert(
      'terminal_payment_intents',
      {
        'id': id,
        'idempotency_key': idempotencyKey,
        'terminal_transaction_id': terminalTransactionId,
        'amount': amount,
        'currency': currency,
        'state': 'pending',
        'context_type': contextType,
        'context_id': contextId,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return id;
  }

  Future<void> markAuthorized(String id, String authorizationCode) => _mark(
        id,
        state: 'authorized',
        authorizationCode: authorizationCode,
      );

  Future<void> markCommitted(String id, {String? contextId}) => _mark(
        id,
        state: 'committed',
        contextId: contextId,
      );

  Future<void> markUnreconciled(String id, Object error) => _mark(
        id,
        state: 'unreconciled',
        errorMessage: error.toString(),
      );

  Future<List<Map<String, Object?>>> findOpenIntents() async {
    final db = await _databaseManager.getDatabase();
    return db.query(
      'terminal_payment_intents',
      where: 'state IN (?, ?)',
      whereArgs: const ['pending', 'authorized'],
      orderBy: 'updated_at ASC',
    );
  }

  Future<void> _mark(
    String id, {
    required String state,
    String? contextId,
    String? errorMessage,
    String? authorizationCode,
  }) async {
    final db = await _databaseManager.getDatabase();
    await db.update(
      'terminal_payment_intents',
      {
        'state': state,
        if (contextId != null) 'context_id': contextId,
        if (errorMessage != null) 'error_message': errorMessage,
        if (authorizationCode != null) 'authorization_code': authorizationCode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
