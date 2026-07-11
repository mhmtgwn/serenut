import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/services/financial_integrity_service.dart';

void main() {
  group('Financial Integrity Service Tests', () {
    late SharedPreferences prefs;
    late AuditLogger auditLogger;
    late OperationQueueService operationQueue;
    late PaymentReconciliationService reconciliationService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      auditLogger = AuditLogger(prefs);
      operationQueue = OperationQueueService(prefs);
      reconciliationService = PaymentReconciliationService(auditLogger);
    });

    test('AuditLogger - logs transactions and transitions correctly', () async {
      await auditLogger.logAction(
        action: 'test_action',
        beforeState: 'idle',
        afterState: 'paymentPending',
        metadata: {'test_key': 'test_val'},
      );

      final logs = auditLogger.getLogs();
      expect(logs, hasLength(1));
      expect(logs.first['action'], 'test_action');
      expect(logs.first['beforeState'], 'idle');
      expect(logs.first['afterState'], 'paymentPending');
      expect(logs.first['metadata']['test_key'], 'test_val');
    });

    test('OperationQueueService - queues, increments retry, and removes operations', () async {
      final key = IdempotencyKeyGenerator.generateKey();
      await operationQueue.queueOperation(
        type: 'create_sale',
        payload: {'amount': 100.0},
        idempotencyKey: key,
      );

      var queue = operationQueue.getQueue();
      expect(queue, hasLength(1));
      expect(queue.first.type, 'create_sale');
      expect(queue.first.idempotencyKey, key);
      expect(queue.first.retryCount, 0);

      // Increment retry
      await operationQueue.incrementRetry(queue.first.id);
      queue = operationQueue.getQueue();
      expect(queue.first.retryCount, 1);

      // Remove operation
      await operationQueue.removeOperation(queue.first.id);
      queue = operationQueue.getQueue();
      expect(queue, isEmpty);
    });

    test('PaymentReconciliationService - detects matching states and reviews discrepancies', () async {
      final key = IdempotencyKeyGenerator.generateKey();

      // Case 1: Match
      final statusMatch = await reconciliationService.reconcileTransaction(
        idempotencyKey: key,
        localAmount: 50.0,
        gatewayAmount: 50.0,
        localStatus: 'completed',
        gatewayStatus: 'completed',
      );
      expect(statusMatch, ReconciliationStatus.matched);

      // Case 2: Mismatch
      final statusMismatch = await reconciliationService.reconcileTransaction(
        idempotencyKey: key,
        localAmount: 50.0,
        gatewayAmount: 40.0,
        localStatus: 'completed',
        gatewayStatus: 'failed',
      );
      expect(statusMismatch, ReconciliationStatus.needsReview);

      // Verify that mismatch was logged to audit log
      final logs = auditLogger.getLogs();
      expect(logs.any((log) => log['action'] == 'reconcile_mismatch_detected'), isTrue);
    });
  });
}
