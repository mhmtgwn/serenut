// test/unit/update_v2/update_lock_test.dart
// Serenut Platform — Concurrency Lock Unit Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_lock_provider.dart';

void main() {
  group('InMemoryUpdateLockProvider Tests', () {
    late UpdateLockProvider lockProvider;

    setUp(() {
      lockProvider = InMemoryUpdateLockProvider();
    });

    test('Acquires and releases lock successfully', () async {
      expect(lockProvider.isLocked, isFalse);

      final acquired = await lockProvider.acquire('corr-1');
      expect(acquired, isTrue);
      expect(lockProvider.isLocked, isTrue);

      lockProvider.release('corr-1');
      expect(lockProvider.isLocked, isFalse);
    });

    test('Rejects concurrent lock acquisition attempts', () async {
      final first = await lockProvider.acquire('corr-1');
      expect(first, isTrue);

      final second = await lockProvider.acquire('corr-2');
      expect(second, isFalse);
      expect(lockProvider.isLocked, isTrue);

      // Verify release mismatch does not unlock
      lockProvider.release('corr-2');
      expect(lockProvider.isLocked, isTrue);

      // Verify correct release unlocks
      lockProvider.release('corr-1');
      expect(lockProvider.isLocked, isFalse);
    });
  });
}
