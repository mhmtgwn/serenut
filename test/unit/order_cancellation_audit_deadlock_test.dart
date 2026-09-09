// test/unit/order_cancellation_audit_deadlock_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/services/audit_log_service.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_audit_repository.dart';
import 'package:serenutos/infrastructure/services/financial_integrity_service.dart';

class _FakeAuthService implements AuthService {
  @override
  Future<AuthUser?> getCurrentUser() async {
    return AuthUser(
      id: 'test-user-id',
      name: 'Test User',
      email: 'test@example.com',
      role: UserRole.admin,
      permissions: const [],
      createdAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Nested Transaction Deadlock Prevention Tests', () {
    late DatabaseManager databaseManager;
    late DbGatewayImpl gateway;
    late AuditLogService auditLogService;
    late SqliteAuditRepository auditRepo;
    late AuditLogger auditLogger;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      await databaseManager.getDatabase();
      gateway = DbGatewayImpl(databaseManager);
      auditLogService = AuditLogService(
        gateway: gateway,
        authService: _FakeAuthService(),
      );
      auditRepo = SqliteAuditRepository(gateway);
      auditLogger = AuditLogger(gateway);
    });

    tearDown(() {
      databaseManager.reset();
    });

    test('AuditLogService, SqliteAuditRepository, and AuditLogger execute within active transaction without deadlock', () async {
      // Simulate OrderCancellationService or SalesService running an outer transaction
      await gateway.transaction(() async {
        // 1. AuditLogService.log called inside active transaction
        await auditLogService.log(
          action: 'sale_cancelled',
          details: '{"saleId": "test-sale-1", "customerId": "test-cust-1"}',
        ).timeout(const Duration(seconds: 3));

        // 2. SqliteAuditRepository.logEvent called inside active transaction
        await auditRepo.logEvent(
          AuditEvent(
            id: 'evt-cancel-1',
            eventType: 'order_cancelled',
            timestamp: DateTime.now(),
            entityId: 'ord-123',
            entityType: 'order',
            userId: 'test-user-id',
            userName: 'Test User',
          ),
        ).timeout(const Duration(seconds: 3));

        // 3. AuditLogger.logAction called inside active transaction
        await auditLogger.logAction(
          action: 'reconcile',
          beforeState: 'pending',
          afterState: 'cancelled',
        ).timeout(const Duration(seconds: 3));
      }).timeout(const Duration(seconds: 5));

      // Verify records are saved
      final logs = await auditLogService.getRecentLogs();
      expect(logs.any((l) => l.action == 'sale_cancelled'), isTrue);

      final events = await auditRepo.getEvents();
      expect(events.any((e) => e.eventType == 'order_cancelled'), isTrue);

      final loggerLogs = await auditLogger.getLogs();
      expect(loggerLogs.any((l) => l['action'] == 'reconcile'), isTrue);
    });
  });
}
