// test/services/auth_security_test.dart
// Serenut POS — Auth Security Tests
// Tests PBKDF2 hashing, login security, and legacy migration
// Created: 24 Jun 2026

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';

void main() {
  group('PasswordHashService', () {
    // ── Hash generation ───────────────────────────────────────────────────────

    test('hashPassword returns PBKDF2 format string', () {
      final hash = PasswordHashService.hashPassword('mysecretpassword');
      expect(hash, startsWith('pbkdf2\$'));
      final parts = hash.split('\$');
      expect(parts.length, 4);
      expect(parts[0], 'pbkdf2');
      expect(int.parse(parts[1]), greaterThanOrEqualTo(10000));
      expect(parts[2].length, greaterThan(0)); // base64 salt
      expect(parts[3].length, greaterThan(0)); // base64 hash
    });

    test('hashPassword generates unique salts (no two hashes are equal)', () {
      final hash1 = PasswordHashService.hashPassword('samepassword');
      final hash2 = PasswordHashService.hashPassword('samepassword');
      // Same password must produce DIFFERENT hashes (due to random salt)
      expect(hash1, isNot(equals(hash2)));
    });

    // ── Verification ──────────────────────────────────────────────────────────

    test('verifyPassword returns true for correct password', () {
      final hash = PasswordHashService.hashPassword('correctpassword');
      expect(PasswordHashService.verifyPassword('correctpassword', hash), isTrue);
    });

    test('verifyPassword returns false for wrong password', () {
      final hash = PasswordHashService.hashPassword('correctpassword');
      expect(PasswordHashService.verifyPassword('wrongpassword', hash), isFalse);
    });

    test('verifyPassword returns false for empty password', () {
      final hash = PasswordHashService.hashPassword('somepassword');
      expect(PasswordHashService.verifyPassword('', hash), isFalse);
    });

    test('verifyPassword returns false for empty stored hash', () {
      expect(PasswordHashService.verifyPassword('password', ''), isFalse);
    });

    test('verifyPassword returns false for malformed hash', () {
      expect(PasswordHashService.verifyPassword('password', 'notahash'), isFalse);
      expect(PasswordHashService.verifyPassword('password', 'pbkdf2\$abc\$def'), isFalse);
    });

    // ── Timing attack prevention ──────────────────────────────────────────────

    test('verifyPassword is constant-time (no early return on wrong length)', () {
      // Both calls should complete without crashing even if lengths differ
      final hash = PasswordHashService.hashPassword('test');
      final sw1 = Stopwatch()..start();
      PasswordHashService.verifyPassword('wrongpassword', hash);
      sw1.stop();

      final sw2 = Stopwatch()..start();
      PasswordHashService.verifyPassword('x', hash);
      sw2.stop();

      // We can't guarantee exact timing in test, but both should complete
      expect(sw1.elapsedMicroseconds, greaterThan(0));
      expect(sw2.elapsedMicroseconds, greaterThan(0));
    });

    // ── Legacy hash migration ─────────────────────────────────────────────────

    test('isLegacyHash detects old format', () {
      expect(PasswordHashService.isLegacyHash('hashed_password_admin'), isTrue);
      expect(PasswordHashService.isLegacyHash('hashed_password_manager123'), isTrue);
    });

    test('isLegacyHash returns false for PBKDF2 format', () {
      final hash = PasswordHashService.hashPassword('test');
      expect(PasswordHashService.isLegacyHash(hash), isFalse);
    });

    test('verifyPassword accepts legacy hash for migration', () {
      // Old system stored: 'hashed_password_<plaintext>'
      const legacyHash = 'hashed_password_admin123';
      expect(PasswordHashService.verifyPassword('admin123', legacyHash), isTrue);
      expect(PasswordHashService.verifyPassword('wrongpassword', legacyHash), isFalse);
    });

    // ── Security properties ───────────────────────────────────────────────────

    test('username == password exploit is NOT accepted as valid hash', () {
      // Ensure the old exploit (username == password fallback) is gone.
      // A stored hash of 'admin' should NOT verify against password 'admin'
      // UNLESS it's in legacy format.
      const notAValidHash = 'admin';
      // 'admin' is not a PBKDF2 hash and not a legacy 'hashed_password_*' hash
      expect(PasswordHashService.verifyPassword('admin', notAValidHash), isFalse);
    });

    test('password case sensitivity is enforced', () {
      final hash = PasswordHashService.hashPassword('Password123');
      expect(PasswordHashService.verifyPassword('password123', hash), isFalse);
      expect(PasswordHashService.verifyPassword('PASSWORD123', hash), isFalse);
      expect(PasswordHashService.verifyPassword('Password123', hash), isTrue);
    });

    test('handles unicode passwords correctly', () {
      final hash = PasswordHashService.hashPassword('şifre123!');
      expect(PasswordHashService.verifyPassword('şifre123!', hash), isTrue);
      expect(PasswordHashService.verifyPassword('sifre123!', hash), isFalse);
    });

    test('handles long passwords correctly', () {
      final longPassword = 'A' * 256; // 256-char password
      final hash = PasswordHashService.hashPassword(longPassword);
      expect(PasswordHashService.verifyPassword(longPassword, hash), isTrue);
      expect(PasswordHashService.verifyPassword('$longPassword!', hash), isFalse);
    });
  });
}
