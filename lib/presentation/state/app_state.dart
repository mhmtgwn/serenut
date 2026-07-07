// lib/presentation/state/app_state.dart
// PHASE 0 - State Pattern (Day 1)
// Generic AppState<T> wrapper for AsyncValue + error handling
// Generated: 20 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Generic application state wrapper combining AsyncValue + AppException
/// 
/// Purpose: Unified state management across all screens
/// Pattern: Let UI handle AsyncValue.when() with 4 branches
/// Integration: Works with Riverpod AsyncNotifier + FutureProvider
/// 
/// Example:
/// ```dart
/// final productListProvider = FutureProvider<AppState<List<Product>>>((ref) async {
///   try {
///     final products = await productRepository.getAll();
///     return AppState.success(products);
///   } catch (e) {
///     return AppState.error(AppException.from(e));
///   }
/// });
/// 
/// // In UI:
/// productListProvider.when(
///   data: (state) {
///     return state.when(
///       success: (products) => ProductList(products),
///       loading: () => LoadingWidget(),
///       error: (error) => ErrorWidget(error.message),
///     );
///   },
///   loading: () => LoadingWidget(),
///   error: (error, stack) => ErrorWidget(error.toString()),
/// );
/// ```
sealed class AppState<T> {
  /// Success state with data payload
  const AppState();

  /// Create success state
  factory AppState.success(T data) => _Success(data);

  /// Create loading state  
  factory AppState.loading() => const _Loading();

  /// Create error state
  factory AppState.error(AppException exception) => _Error(exception);

  /// Pattern match over state
  /// Caller provides handler for each state variant
  R when<R>({
    required R Function(T data) success,
    required R Function() loading,
    required R Function(AppException error) error,
  }) => switch (this) {
    _Success(data: var data) => success(data),
    _Loading() => loading(),
    _Error(exception: var ex) => error(ex),
  };

  /// Get data if success, otherwise null
  T? getOrNull() => this is _Success ? (this as _Success<T>).data : null;

  /// Get error if error state, otherwise null  
  AppException? getErrorOrNull() => this is _Error ? (this as _Error<T>).exception : null;

  /// Check if success
  bool get isSuccess => this is _Success;

  /// Check if loading
  bool get isLoading => this is _Loading;

  /// Check if error
  bool get isError => this is _Error;
}

/// Success state variant
final class _Success<T> extends AppState<T> {
  final T data;
  const _Success(this.data);
}

/// Loading state variant (no data)
final class _Loading<T> extends AppState<T> {
  const _Loading();
}

/// Error state variant with exception info
final class _Error<T> extends AppState<T> {
  final AppException exception;
  const _Error(this.exception);
}

// ════════════════════════════════════════════════════════════
// Exception Model (Type-Safe Error Handling)
// ════════════════════════════════════════════════════════════

/// Domain exception hierarchy
/// Replaces string error messages with type-safe error codes
/// 
/// Categories:
/// - Authentication: Login, token, permission failures
/// - Validation: Input validation, constraint violations
/// - Network: Connection, timeout, server errors
/// - Transaction: Business logic failures (rollback, atomic violations)
/// - Database: SQLite constraints, corrupted state
/// - Unknown: Catch-all for unhandled exceptions
sealed class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  AppException({
    required this.message,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  /// Factory to convert any exception to AppException
  factory AppException.from(dynamic error) {
    if (error is AppException) return error;

    if (error.runtimeType.toString() == 'AuthException') {
      return AuthException(
        message: error.toString(),
        code: 'AUTH_ERROR',
        originalError: error,
      );
    }

    if (error is FormatException) {
      return ValidationException(
        message: error.message,
        code: 'INVALID_FORMAT',
        originalError: error,
      );
    }

    // Extend with other exception types as needed
    return UnknownException(
      message: error.toString(),
      originalError: error,
    );
  }

  /// Get user-friendly message (no technical details)
  String get userMessage;

  /// Get error code for logging/telemetry
  String get errorCode => code ?? 'UNKNOWN_ERROR';

  @override
  String toString() => message;
}

/// Authentication failures (login, permissions, token)
final class AuthException extends AppException {
  AuthException({
    required super.message,
    String? code,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: code ?? 'AUTH_ERROR',
  );

  @override
  String get userMessage => message;
}

/// Input validation failures
final class ValidationException extends AppException {
  final String? fieldName;

  ValidationException({
    required super.message,
    String? code,
    this.fieldName,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: code ?? 'VALIDATION_ERROR',
  );

  @override
  String get userMessage => fieldName != null 
    ? '$fieldName is invalid: $message'
    : 'Invalid input: $message';
}

/// Network/connectivity failures
final class NetworkException extends AppException {
  NetworkException({
    required super.message,
    String? code,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: code ?? 'NETWORK_ERROR',
  );

  @override
  String get userMessage => 'Network error: Please check your connection';
}

/// Business logic failures (transaction, rollback, constraints)
final class TransactionException extends AppException {
  final String? affectedId;
  final Map<String, dynamic>? context;

  TransactionException({
    required super.message,
    String? code,
    this.affectedId,
    this.context,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: code ?? 'TRANSACTION_ERROR',
  );

  @override
  String get userMessage => 'Transaction failed: $message';
}

/// Database/SQLite failures
final class DatabaseException extends AppException {
  DatabaseException({
    required super.message,
    String? code,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: code ?? 'DATABASE_ERROR',
  );

  @override
  String get userMessage => 'Database error: Operation failed';
}

/// Catch-all for unhandled exceptions
final class UnknownException extends AppException {
  UnknownException({
    required super.message,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: 'UNKNOWN_ERROR',
  );

  @override
  String get userMessage => 'An unexpected error occurred';
}

// ════════════════════════════════════════════════════════════
// Riverpod Integration Helpers
// ════════════════════════════════════════════════════════════

/// Extension for Riverpod AsyncValue to AppState conversion
extension AsyncValueToAppState<T> on AsyncValue<T> {
  /// Convert AsyncValue to AppState
  AppState<T> toAppState() => when(
    data: (data) => AppState.success(data),
    loading: () => AppState.loading(),
    error: (error, stack) => AppState.error(AppException.from(error)),
  );
}

/// Extension for AppState to humanize errors in UI
extension AppStateErrorDisplay on AppException {
  /// Get icon for error display
  String get icon {
    return switch (this) {
      AuthException() => '🔒',
      ValidationException() => '⚠️',
      NetworkException() => '📡',
      TransactionException() => '❌',
      DatabaseException() => '💾',
      UnknownException() => '❓',
    };
  }

  /// Get color for error display (hex format for Flutter)
  String get colorHex {
    return switch (this) {
      AuthException() => 'FF6B6B',      // Red
      ValidationException() => 'FFA500',  // Orange
      NetworkException() => 'FFD700',     // Yellow
      TransactionException() => 'FF6B6B', // Red
      DatabaseException() => 'FF6B6B',    // Red
      UnknownException() => '808080',     // Gray
    };
  }
}
