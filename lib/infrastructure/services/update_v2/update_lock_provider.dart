// lib/infrastructure/services/update_v2/update_lock_provider.dart
// Serenut Platform — Global Update Mutex Concurrency Lock

import 'dart:async';
import 'package:flutter/foundation.dart';

abstract class UpdateLockProvider {
  /// Attempts to acquire the global update lock. Returns true if acquired successfully.
  Future<bool> acquire(String correlationId);

  /// Releases the global update lock if held by the given correlationId.
  void release(String correlationId);

  /// Returns true if the lock is currently held.
  bool get isLocked;
}

class InMemoryUpdateLockProvider implements UpdateLockProvider {
  String? _holderCorrelationId;

  @override
  Future<bool> acquire(String correlationId) async {
    // Since Dart runs in a single-threaded event loop, synchronous checking
    // and setting of the variable is fully atomic and thread-safe.
    if (_holderCorrelationId != null) {
      debugPrint('[UpdateLock] Lock acquire failed. Already locked by: $_holderCorrelationId (Request: $correlationId)');
      return false;
    }
    _holderCorrelationId = correlationId;
    debugPrint('[UpdateLock] Lock acquired by: $correlationId');
    return true;
  }

  @override
  void release(String correlationId) {
    if (_holderCorrelationId == correlationId) {
      _holderCorrelationId = null;
      debugPrint('[UpdateLock] Lock released by: $correlationId');
    } else {
      debugPrint('[UpdateLock] Lock release rejected: owner mismatch (Held by: $_holderCorrelationId, Request: $correlationId)');
    }
  }

  @override
  bool get isLocked => _holderCorrelationId != null;
}
