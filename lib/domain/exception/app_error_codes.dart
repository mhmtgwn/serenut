// ignore_for_file: constant_identifier_names
// lib/domain/exception/app_error_codes.dart
// PHASE 0 - Error Model (Day 2)
// Centralized error codes for all business domains
// Generated: 21 Jun 2026

/// Global error codes for consistent error handling
/// 
/// Prefix pattern:
/// - AUTH_* (authentication failures)
/// - VAL_* (validation failures)
/// - NET_* (network failures)
/// - TXN_* (transaction failures)
/// - DB_* (database failures)
/// - UNK_* (unknown errors)
/// 
class AppErrorCode {
  // ════════════════════════════════════════════════════════════
  // Authentication Errors (AUTH_)
  // ════════════════════════════════════════════════════════════
  
  static const String AUTH_INVALID_CREDENTIALS = 'AUTH_INVALID_CREDENTIALS';
  static const String AUTH_USER_NOT_FOUND = 'AUTH_USER_NOT_FOUND';
  static const String AUTH_PERMISSION_DENIED = 'AUTH_PERMISSION_DENIED';
  static const String AUTH_SESSION_EXPIRED = 'AUTH_SESSION_EXPIRED';
  static const String AUTH_TOKEN_INVALID = 'AUTH_TOKEN_INVALID';
  static const String AUTH_TOKEN_EXPIRED = 'AUTH_TOKEN_EXPIRED';

  // ════════════════════════════════════════════════════════════
  // Validation Errors (VAL_)
  // ════════════════════════════════════════════════════════════
  
  static const String VAL_REQUIRED_FIELD_MISSING = 'VAL_REQUIRED_FIELD_MISSING';
  static const String VAL_INVALID_FORMAT = 'VAL_INVALID_FORMAT';
  static const String VAL_INVALID_EMAIL = 'VAL_INVALID_EMAIL';
  static const String VAL_INVALID_PHONE = 'VAL_INVALID_PHONE';
  static const String VAL_INVALID_AMOUNT = 'VAL_INVALID_AMOUNT';
  static const String VAL_NEGATIVE_AMOUNT = 'VAL_NEGATIVE_AMOUNT';
  static const String VAL_ZERO_AMOUNT = 'VAL_ZERO_AMOUNT';
  static const String VAL_INVALID_DATE = 'VAL_INVALID_DATE';
  static const String VAL_DUPLICATE_ENTRY = 'VAL_DUPLICATE_ENTRY';
  static const String VAL_NOT_FOUND = 'VAL_NOT_FOUND';

  // ════════════════════════════════════════════════════════════
  // Network Errors (NET_)
  // ════════════════════════════════════════════════════════════
  
  static const String NET_NO_CONNECTION = 'NET_NO_CONNECTION';
  static const String NET_CONNECTION_TIMEOUT = 'NET_CONNECTION_TIMEOUT';
  static const String NET_REQUEST_TIMEOUT = 'NET_REQUEST_TIMEOUT';
  static const String NET_SERVER_ERROR = 'NET_SERVER_ERROR';
  static const String NET_NOT_FOUND = 'NET_NOT_FOUND';
  static const String NET_FORBIDDEN = 'NET_FORBIDDEN';

  // ════════════════════════════════════════════════════════════
  // Transaction Errors (TXN_)
  // ════════════════════════════════════════════════════════════
  
  static const String TXN_INSUFFICIENT_FUNDS = 'TXN_INSUFFICIENT_FUNDS';
  static const String TXN_INSUFFICIENT_STOCK = 'TXN_INSUFFICIENT_STOCK';
  static const String TXN_FAILED = 'TXN_FAILED';
  static const String TXN_ROLLBACK = 'TXN_ROLLBACK';
  static const String TXN_ATOMIC_VIOLATION = 'TXN_ATOMIC_VIOLATION';
  static const String TXN_CONSTRAINT_VIOLATION = 'TXN_CONSTRAINT_VIOLATION';
  static const String TXN_LOCK_CONFLICT = 'TXN_LOCK_CONFLICT';
  static const String TXN_CONCURRENT_MODIFICATION = 'TXN_CONCURRENT_MODIFICATION';

  // ════════════════════════════════════════════════════════════
  // Database Errors (DB_)
  // ════════════════════════════════════════════════════════════
  
  static const String DB_CONSTRAINT_FAILED = 'DB_CONSTRAINT_FAILED';
  static const String DB_RECORD_NOT_FOUND = 'DB_RECORD_NOT_FOUND';
  static const String DB_RECORD_ALREADY_EXISTS = 'DB_RECORD_ALREADY_EXISTS';
  static const String DB_CORRUPTED = 'DB_CORRUPTED';
  static const String DB_MIGRATION_FAILED = 'DB_MIGRATION_FAILED';
  static const String DB_CONNECTION_FAILED = 'DB_CONNECTION_FAILED';
  static const String DB_QUERY_FAILED = 'DB_QUERY_FAILED';

  // ════════════════════════════════════════════════════════════
  // Unknown Errors (UNK_)
  // ════════════════════════════════════════════════════════════
  
  static const String UNK_ERROR = 'UNK_ERROR';
  static const String UNK_UNHANDLED_EXCEPTION = 'UNK_UNHANDLED_EXCEPTION';

  // ════════════════════════════════════════════════════════════
  // Error Code to User Message Mapping
  // ════════════════════════════════════════════════════════════

  static const Map<String, String> messages = {
    // Authentication
    AUTH_INVALID_CREDENTIALS: 'Invalid username or password',
    AUTH_USER_NOT_FOUND: 'User not found',
    AUTH_PERMISSION_DENIED: 'You do not have permission to perform this action',
    AUTH_SESSION_EXPIRED: 'Your session has expired. Please login again',
    AUTH_TOKEN_INVALID: 'Invalid authentication token',
    AUTH_TOKEN_EXPIRED: 'Your authentication token has expired',

    // Validation
    VAL_REQUIRED_FIELD_MISSING: 'Required field is missing',
    VAL_INVALID_FORMAT: 'Invalid format',
    VAL_INVALID_EMAIL: 'Invalid email address',
    VAL_INVALID_PHONE: 'Invalid phone number',
    VAL_INVALID_AMOUNT: 'Invalid amount',
    VAL_NEGATIVE_AMOUNT: 'Amount cannot be negative',
    VAL_ZERO_AMOUNT: 'Amount must be greater than zero',
    VAL_INVALID_DATE: 'Invalid date',
    VAL_DUPLICATE_ENTRY: 'This entry already exists',
    VAL_NOT_FOUND: 'Item not found',

    // Network
    NET_NO_CONNECTION: 'No internet connection. Please check your network',
    NET_CONNECTION_TIMEOUT: 'Connection timeout. Please try again',
    NET_REQUEST_TIMEOUT: 'Request timeout. Please try again',
    NET_SERVER_ERROR: 'Server error. Please try again later',
    NET_NOT_FOUND: 'Resource not found',
    NET_FORBIDDEN: 'Access denied',

    // Transaction
    TXN_INSUFFICIENT_FUNDS: 'Insufficient funds for this transaction',
    TXN_INSUFFICIENT_STOCK: 'Insufficient stock available',
    TXN_FAILED: 'Transaction failed',
    TXN_ROLLBACK: 'Transaction was reversed',
    TXN_ATOMIC_VIOLATION: 'Transaction integrity violation',
    TXN_CONSTRAINT_VIOLATION: 'Transaction constraint violation',
    TXN_LOCK_CONFLICT: 'Data is locked by another transaction',
    TXN_CONCURRENT_MODIFICATION: 'Data was modified by another user',

    // Database
    DB_CONSTRAINT_FAILED: 'Database constraint violation',
    DB_RECORD_NOT_FOUND: 'Record not found in database',
    DB_RECORD_ALREADY_EXISTS: 'Record already exists in database',
    DB_CORRUPTED: 'Database is corrupted',
    DB_MIGRATION_FAILED: 'Database migration failed',
    DB_CONNECTION_FAILED: 'Failed to connect to database',
    DB_QUERY_FAILED: 'Database query failed',

    // Unknown
    UNK_ERROR: 'An unexpected error occurred',
    UNK_UNHANDLED_EXCEPTION: 'An unhandled exception occurred',
  };

  /// Get user-friendly message for error code
  static String messageFor(String code) {
    return messages[code] ?? 'An unexpected error occurred';
  }
}
