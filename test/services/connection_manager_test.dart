import 'dart:async';
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/realtime/realtime_status.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/infrastructure/realtime/connection_manager.dart';
import 'package:serenutos/infrastructure/realtime/reconnect_manager.dart';
import 'package:serenutos/infrastructure/realtime/websocket_manager.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/realtime/event_dispatcher.dart';

class MockWebSocketManager implements WebSocketManager {
  final _msgController = StreamController<String>.broadcast();
  final _stateController = StreamController<bool>.broadcast();
  bool _isConnected = false;
  String? connectedUrl;

  @override
  Stream<String> get messages => _msgController.stream;

  @override
  Stream<bool> get connectionState => _stateController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  void connect(String url) {
    _isConnected = true;
    connectedUrl = url;
    _stateController.add(true);
  }

  @override
  void disconnect() {
    if (_isConnected) {
      _isConnected = false;
      _stateController.add(false);
    }
  }

  @override
  void send(String data) {}

  @override
  void dispose() {
    _msgController.close();
    _stateController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthService implements AuthService {
  bool failWithNetworkError = false;
  bool failWithAuthError = false;
  bool refreshCalled = false;
  bool sessionExpiredTriggered = false;

  @override
  Future<AuthUser?> getCurrentUser() async {
    return AuthUser(
      id: 'user-1',
      name: 'Cashier 1',
      email: 'cashier1@serenut.com',
      role: UserRole.cashier,
      permissions: [],
      createdAt: DateTime.now(),
    );
  }

  @override
  String? getJwtToken() => 'jwt_token';

  @override
  Future<bool> refreshToken() async {
    refreshCalled = true;
    if (failWithNetworkError) {
      throw const ApiException('Network timeout or host lookup failed');
    }
    if (failWithAuthError) {
      return false; // Permanent auth failure
    }
    return true;
  }

  @override
  void triggerSessionExpired() {
    sessionExpiredTriggered = true;
  }

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockEventDispatcher implements EventDispatcher {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ConnectionManager Reconnect Loop & Error Distinction Tests (Kritik D)', () {
    late MockWebSocketManager wsManager;
    late MockAuthService authService;
    late MockEventDispatcher eventDispatcher;
    late ReconnectManager reconnectManager;
    late ConnectionManager connectionManager;

    setUp(() {
      wsManager = MockWebSocketManager();
      authService = MockAuthService();
      eventDispatcher = MockEventDispatcher();
      
      // Use slightly longer delays for Windows timer resolution safety
      reconnectManager = ReconnectManager(
        minDelay: const Duration(milliseconds: 100),
        maxDelay: const Duration(milliseconds: 150),
        jitter: 0,
      );

      connectionManager = ConnectionManager(
        wsManager: wsManager,
        reconnectManager: reconnectManager,
        eventDispatcher: eventDispatcher,
        authService: authService,
        wsBaseUrl: 'ws://localhost:4000/api/v1/realtime/live',
        onStatusChanged: (_) {},
      );
    });

    tearDown(() {
      connectionManager.dispose();
      wsManager.dispose();
    });

    test('Normal Connect flow succeeds', () async {
      await connectionManager.connect();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(wsManager.isConnected, true);
      expect(connectionManager.status, RealtimeStatus.connected);
      connectionManager.dispose();
    });

    test('Temporary network error during reconnect -> schedules retry, loop continues', () async {
      await connectionManager.connect();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(wsManager.isConnected, true);

      authService.failWithNetworkError = true;
      
      // Trigger a disconnect to schedule a reconnect
      wsManager.disconnect();
      
      // Reconnect is scheduled (attempt 1: delay = 100ms). Wait 150ms for it to run.
      await Future.delayed(const Duration(milliseconds: 150));
      
      expect(authService.refreshCalled, true);
      expect(authService.sessionExpiredTriggered, false);
      expect(reconnectManager.attempts, greaterThan(0));
      
      // Reset flag and stop network error to verify next loop succeeds
      authService.failWithNetworkError = false;
      authService.refreshCalled = false;
      
      // Reconnect is scheduled (attempt 2: delay = 150ms). Wait 200ms for it to run.
      await Future.delayed(const Duration(milliseconds: 200));
      expect(authService.refreshCalled, true);
      expect(wsManager.isConnected, true);
      expect(connectionManager.status, RealtimeStatus.connected);
      connectionManager.dispose();
    });

    test('Permanent auth failure during reconnect -> stops loop and triggers session expiry redirect', () async {
      await connectionManager.connect();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(wsManager.isConnected, true);

      authService.failWithAuthError = true;
      
      // Trigger a disconnect
      wsManager.disconnect();
      
      // Reconnect is scheduled (attempt 1: delay = 100ms). Wait 150ms for it to run.
      await Future.delayed(const Duration(milliseconds: 150));
      
      expect(authService.refreshCalled, true);
      expect(authService.sessionExpiredTriggered, true);
      expect(wsManager.isConnected, false);
      expect(connectionManager.status, RealtimeStatus.disconnected);
      connectionManager.dispose();
    });

    test('connect() called while reconnecting is ignored and does not double schedule', () async {
      await connectionManager.connect();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(wsManager.isConnected, true);

      // Trigger disconnect to schedule reconnect timer (attempt 1: delay = 100ms)
      authService.failWithNetworkError = true;
      authService.refreshCalled = false;
      wsManager.disconnect();

      // Wait for the Stream connectionState event to propagate
      // 30ms is enough for propagation but well below the 100ms delay.
      await Future.delayed(const Duration(milliseconds: 30));

      expect(connectionManager.status, RealtimeStatus.reconnecting);

      // Call connect() manually while in reconnecting state
      await connectionManager.connect();

      // Ensure connect() did not reset attempts or trigger connect immediately
      expect(connectionManager.status, RealtimeStatus.reconnecting);
      expect(authService.refreshCalled, false);

      // Wait for the reconnect timer to trigger (100ms scheduled, 30ms waited).
      // Wait 120ms to be absolutely sure the timer has fired.
      await Future.delayed(const Duration(milliseconds: 120));
      expect(authService.refreshCalled, true);
      connectionManager.dispose();
    });
  });
}
