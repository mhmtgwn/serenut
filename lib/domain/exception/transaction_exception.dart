/// Exception thrown when transaction operations fail
class TransactionException implements Exception {
  final String message;
  final String? code;
  final Object? originalError;
  final StackTrace? stackTrace;

  TransactionException({
    required this.message,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'TransactionException: $message${code != null ? ' ($code)' : ''}';
}

/// Thrown when transaction rollback is attempted but fails
class TransactionRollbackException extends TransactionException {
  TransactionRollbackException({
    required super.message,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: 'ROLLBACK_FAILED',
  );
}

/// Thrown when commit fails (data integrity issue)
class TransactionCommitException extends TransactionException {
  TransactionCommitException({
    required super.message,
    super.originalError,
    super.stackTrace,
  }) : super(
    code: 'COMMIT_FAILED',
  );
}

/// Thrown when transaction timeout occurs
class TransactionTimeoutException extends TransactionException {
  final Duration timeout;

  TransactionTimeoutException({
    required this.timeout,
    super.originalError,
  }) : super(
    message: 'Transaction timed out after ${timeout.inSeconds}s',
    code: 'TIMEOUT',
  );
}

/// Thrown when operation is attempted outside transaction context
class NotInTransactionException extends TransactionException {
  NotInTransactionException({
    required super.message,
  }) : super(
    code: 'NOT_IN_TRANSACTION',
  );
}
