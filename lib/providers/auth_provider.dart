// lib/providers/auth_provider.dart
// Serenut Platform — Auth Provider Compatibility Shim
// Provides `authProvider` for UI widgets that need auth state + token access.
// Created: Sprint Build Fix

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';

// ════════════════════════════════════════════════════════════
// Auth State with Token Access
// ════════════════════════════════════════════════════════════

/// Lightweight auth state wrapper that exposes [token] and [user].
///
/// Used by widgets that need both the JWT token (for API/WS calls)
/// and the current user object.
///
/// Usage:
/// ```dart
/// final authState = ref.read(authProvider);
/// final token = authState.token;       // String? — JWT access token
/// final user = authState.user;         // AuthUser? — current user
/// ```
class AuthState {
  final String? token;
  final AuthUser? user;

  const AuthState({this.token, this.user});

  bool get isAuthenticated => user != null && token != null;
}

/// Provider that exposes [AuthState] (user + JWT token) to the UI.
///
/// The JWT token is stored in [ApiClient] after login.
/// This provider reads both the current user from [authNotifierProvider]
/// and the JWT token from [apiClientProvider].
final authProvider = Provider<AuthState>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  final apiClient = ref.watch(apiClientProvider);
  // ApiClient stores the JWT internally; expose it via getter
  return AuthState(
    token: apiClient.jwtToken,
    user: currentUser,
  );
});
