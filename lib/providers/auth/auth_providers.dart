// lib/providers/auth/auth_providers.dart
// PHASE 0 - Riverpod Providers (Day 1)
// Auth-related providers for Riverpod dependency injection
// Generated: 20 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/presentation/state/app_state.dart';
import 'package:serenutos/providers/auth/auth_notifier.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';

// ════════════════════════════════════════════════════════════
// Core Providers  
// ════════════════════════════════════════════════════════════

/// AuthService singleton
/// 
/// Initialize on app startup:
/// ```dart
/// final authService = ref.read(authServiceProvider);
/// await authService.initialize();
/// ```
final authServiceProvider = Provider<AuthService>((ref) {
  final userRepo = ref.watch(userRepositoryProvider);
  final hashService = ref.watch(hashServiceProvider);
  final apiClient = ref.watch(apiClientProvider);
  final deviceManager = ref.watch(deviceManagerProvider);
  return AuthService(
    userRepository: userRepo,
    hashService: hashService,
    deviceManager: deviceManager,
    apiClient: apiClient,
  );
});

/// AppAuthNotifier StateNotifier
/// 
/// Wraps AuthService with Riverpod management
/// Usage: ref.read(authNotifierProvider.notifier).login(user, pass)
final authNotifierProvider = StateNotifierProvider<
  AppAuthNotifier,
  AppState<AuthUser>
>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AppAuthNotifier(authService);
});

// ════════════════════════════════════════════════════════════
// Derived Providers (computed from authNotifierProvider)
// ════════════════════════════════════════════════════════════

/// Current authenticated user
/// 
/// Usage in UI:
/// ```dart
/// final currentUser = ref.watch(currentUserProvider);
/// currentUser.when(
///   success: (user) => Text(user.name),
///   loading: () => LoadingWidget(),
///   error: (error) => ErrorWidget(error.userMessage),
/// );
/// ```
final currentUserProvider = Provider<AuthUser?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.getOrNull();
});

/// Is user authenticated
/// 
/// Usage: if (ref.watch(isAuthenticatedProvider)) { /* show app */ }
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

/// Current user role
/// 
/// Usage: 
/// ```dart
/// final role = ref.watch(userRoleProvider);
/// if (role == UserRole.admin) { /* show admin panel */ }
/// ```
final userRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(currentUserProvider)?.role;
});

/// Current user permissions
/// 
/// Usage:
/// ```dart
/// final perms = ref.watch(permissionsProvider);
/// if (perms.contains('reports:view')) { /* show reports */ }
/// ```
final permissionsProvider = Provider<List<String>>((ref) {
  return ref.watch(currentUserProvider)?.getAllPermissions() ?? [];
});

/// Check if user has a specific permission
/// 
/// Usage:
/// ```dart
/// final canDelete = ref.watch(hasPermissionProvider('sales:delete'));
/// if (canDelete) { /* show delete button */ }
/// ```
final hasPermissionProvider = Provider.family<bool, String>((ref, permission) {
  final user = ref.watch(currentUserProvider);
  return user?.hasPermission(permission) ?? false;
});

// ════════════════════════════════════════════════════════════
// Auth Errors
// ════════════════════════════════════════════════════════════

/// Current auth error (if any)
/// 
/// Usage:
/// ```dart
/// final error = ref.watch(authErrorProvider);
/// if (error != null) { 
///   ScaffoldMessenger.of(context).showSnackBar(
///     SnackBar(content: Text(error.userMessage))
///   );
/// }
/// ```
final authErrorProvider = Provider<AppException?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.getErrorOrNull();
});

/// Is auth loading
final isAuthLoadingProvider = Provider<bool>((ref) {
  return ref.watch(authNotifierProvider).isLoading;
});

// ════════════════════════════════════════════════════════════
// Mock Data Helper (Development Only)
// ════════════════════════════════════════════════════════════


