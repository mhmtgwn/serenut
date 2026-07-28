// lib/providers/auth/auth_notifier.dart
// PHASE 0 - Riverpod Integration (Day 1)
// StateNotifier wrapper for AuthService
// Generated: 20 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/auth_service.dart' hide AuthException;
import 'package:serenutos/presentation/state/app_state.dart';

/// Riverpod StateNotifier wrapping AuthService
///
/// Responsibilities:
/// - Manage current user state (success/loading/error)
/// - Orchestrate AuthService calls with state updates
/// - Provide Riverpod-compatible API for UI consumption
///
/// Usage (in UI):
/// ```dart
/// // Get current user
/// final userAsyncValue = ref.watch(currentUserProvider);
///
/// // Login
/// await ref.read(authNotifierProvider.notifier).login(username, password);
///
/// // Logout
/// await ref.read(authNotifierProvider.notifier).logout();
/// ```
class AppAuthNotifier extends StateNotifier<AppState<AuthUser>> {
  final AuthService _authService;

  AppAuthNotifier(this._authService) : super(AppState.loading()) {
    // Bind session expiration to trigger state updates & routing redirects
    _authService.onSessionExpiredCallback = () {
      state = AppState.error(
        AuthException(
            message: 'Oturum süresi doldu. Lütfen tekrar giriş yapın.',
            code: 'AUTH_003'),
      );
    };
    _authService.onUserUpdatedCallback = (updatedUser) {
      state = AppState.success(updatedUser);
    };
    // Initialize: load stored user on startup
    _initializeUser();
  }

  /// Load stored user from SharedPreferences on startup
  Future<void> _initializeUser() async {
    try {
      state = AppState.loading();
      final user = await _authService.getCurrentUser();
      if (user != null) {
        state = AppState.success(user);
        // Refresh the server-owned entitlement and publish a fresh auth state
        // afterwards. License/access providers read the verified cache; without
        // this second state emission an expired banner could remain visible
        // until the next full application restart even after a successful
        // bootstrap activated the trial.
        try {
          final refreshed = await _authService.refreshEntitlement();
          if (refreshed) state = AppState.success(user);
        } catch (_) {
          // Keep the already restored offline session and its normal lease.
        }
      } else {
        state = AppState.error(
          AuthException(message: 'No stored user found', code: 'AUTH_001'),
        );
      }
    } catch (e) {
      state = AppState.error(AppException.from(e));
    }
  }

  /// Perform login with username/password
  ///
  /// Flow:
  /// 1. Set state to loading
  /// 2. Call AuthService.login() — backend-first, local SQLite fallback
  /// 3. Trial sync: AuthService.login() backend'den trial_started_at okur (tek yer)
  /// 4. On success: set state to success(user)
  /// 5. On error: set state to error(exception)
  ///
  /// Throws: Never (errors go to state.error)
  Future<void> login(String username, String password) async {
    try {
      state = AppState.loading();
      final user = await _authService.login(username, password);
      // Trial sync: AuthService.login() içinde backend'den halloluyor
      // Burada çift tetiklemeye gerek yok
      state = AppState.success(user);
    } catch (e) {
      state = AppState.error(AppException.from(e));
    }
  }

  /// Perform logout
  ///
  /// Flow:
  /// 1. Call AuthService.logout() (clears storage)
  /// 2. Set state to error (no user)
  ///
  /// Throws: Never
  Future<void> logout() async {
    try {
      await _authService.logout();
      state = AppState.error(
        AuthException(message: 'User logged out', code: 'AUTH_002'),
      );
    } catch (e) {
      state = AppState.error(AppException.from(e));
    }
  }

  /// Check if user has a specific permission
  ///
  /// Returns: true if user is authenticated AND has permission
  bool hasPermission(String permission) {
    return state.getOrNull()?.hasPermission(permission) ?? false;
  }

  /// Check if user has all required permissions
  bool hasAllPermissions(List<String> permissions) {
    return state.getOrNull()?.hasAllPermissions(permissions) ?? false;
  }

  /// Get current user role
  UserRole? getUserRole() {
    return state.getOrNull()?.role;
  }

  /// Directly set authenticated user state (used after setup/activation on Web)
  Future<void> loginWithUser(AuthUser user) async {
    await _authService.setCurrentUser(user);
    state = AppState.success(user);
  }

  /// Re-check and refresh current auth state (e.g. after license refresh)
  Future<void> checkAuth() async {
    await _initializeUser();
  }
}
