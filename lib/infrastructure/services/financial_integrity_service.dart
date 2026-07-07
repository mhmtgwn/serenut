// lib/infrastructure/services/financial_integrity_service.dart
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Event Model for Audit Logging ──
class AuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String action;
  final String beforeState;
  final String afterState;
  final Map<String, dynamic> metadata;

  AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.beforeState,
    required this.afterState,
    required this.metadata,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'action': action,
    'beforeState': beforeState,
    'afterState': afterState,
    'metadata': metadata,
  };
}

// ── Queue Operation Model ──
class SyncOperation {
  final String id;
  final String type; // 'create_sale', 'refund', etc.
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final int retryCount;

  SyncOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.idempotencyKey,
    this.retryCount = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'payload': payload,
    'idempotencyKey': idempotencyKey,
    'retryCount': retryCount,
  };

  factory SyncOperation.fromMap(Map<String, dynamic> map) => SyncOperation(
    id: map['id'] as String,
    type: map['type'] as String,
    payload: map['payload'] as Map<String, dynamic>,
    idempotencyKey: map['idempotencyKey'] as String,
    retryCount: map['retryCount'] as int? ?? 0,
  );
}

// ── Audit Logger Service ──
class AuditLogger {
  final SharedPreferences _prefs;
  static const String _kAuditLogKey = 'serenut_audit_logs';

  AuditLogger(this._prefs);

  Future<void> logAction({
    required String action,
    required String beforeState,
    required String afterState,
    Map<String, dynamic> metadata = const {},
  }) async {
    final entry = AuditLogEntry(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      action: action,
      beforeState: beforeState,
      afterState: afterState,
      metadata: metadata,
    );

    final logsRaw = _prefs.getStringList(_kAuditLogKey) ?? [];
    logsRaw.add(jsonEncode(entry.toMap()));
    await _prefs.setStringList(_kAuditLogKey, logsRaw);
  }

  List<Map<String, dynamic>> getLogs() {
    final logsRaw = _prefs.getStringList(_kAuditLogKey) ?? [];
    return logsRaw.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }
}

// ── Idempotency Key Generator ──
class IdempotencyKeyGenerator {
  static String generateKey() {
    return const Uuid().v4();
  }
}

// ── Persistent Operation Sync Queue ──
class OperationQueueService {
  final SharedPreferences _prefs;
  static const String _kQueueKey = 'serenut_sync_queue';

  OperationQueueService(this._prefs);

  Future<void> queueOperation({
    required String type,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  }) async {
    final op = SyncOperation(
      id: const Uuid().v4(),
      type: type,
      payload: payload,
      idempotencyKey: idempotencyKey,
    );

    final queueRaw = _prefs.getStringList(_kQueueKey) ?? [];
    queueRaw.add(jsonEncode(op.toMap()));
    await _prefs.setStringList(_kQueueKey, queueRaw);
  }

  List<SyncOperation> getQueue() {
    final queueRaw = _prefs.getStringList(_kQueueKey) ?? [];
    return queueRaw.map((e) => SyncOperation.fromMap(jsonDecode(e))).toList();
  }

  Future<void> removeOperation(String opId) async {
    final queue = getQueue();
    queue.removeWhere((op) => op.id == opId);
    final queueRaw = queue.map((op) => jsonEncode(op.toMap())).toList();
    await _prefs.setStringList(_kQueueKey, queueRaw);
  }

  Future<void> incrementRetry(String opId) async {
    final queue = getQueue();
    final idx = queue.indexWhere((op) => op.id == opId);
    if (idx != -1) {
      final oldOp = queue[idx];
      queue[idx] = SyncOperation(
        id: oldOp.id,
        type: oldOp.type,
        payload: oldOp.payload,
        idempotencyKey: oldOp.idempotencyKey,
        retryCount: oldOp.retryCount + 1,
      );
      final queueRaw = queue.map((op) => jsonEncode(op.toMap())).toList();
      await _prefs.setStringList(_kQueueKey, queueRaw);
    }
  }
}

// ── Payment Reconciliation Engine ──
enum ReconciliationStatus { matched, mismatchLocalMissing, mismatchRemoteMissing, needsReview }

class PaymentReconciliationService {
  final AuditLogger _logger;

  PaymentReconciliationService(this._logger);

  Future<ReconciliationStatus> reconcileTransaction({
    required String idempotencyKey,
    required double localAmount,
    required double gatewayAmount,
    required String localStatus,
    required String gatewayStatus,
  }) async {
    if (localStatus == gatewayStatus && localAmount == gatewayAmount) {
      await _logger.logAction(
        action: 'reconcile_match',
        beforeState: 'unreconciled',
        afterState: 'reconciled',
        metadata: {
          'idempotencyKey': idempotencyKey,
          'status': ReconciliationStatus.matched.name,
        },
      );
      return ReconciliationStatus.matched;
    }

    await _logger.logAction(
      action: 'reconcile_mismatch_detected',
      beforeState: 'unreconciled',
      afterState: 'needs_review',
      metadata: {
        'idempotencyKey': idempotencyKey,
        'localAmount': localAmount,
        'gatewayAmount': gatewayAmount,
        'localStatus': localStatus,
        'gatewayStatus': gatewayStatus,
      },
    );

    return ReconciliationStatus.needsReview;
  }
}
