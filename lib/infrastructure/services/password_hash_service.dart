// lib/infrastructure/services/password_hash_service.dart
// Serenut POS — Password Security Layer
// PBKDF2-HMAC-SHA256 with salt — production-grade implementation
// Created: 24 Jun 2026

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:serenutos/domain/services/i_hash_service.dart';

/// Production-grade password hashing using PBKDF2-HMAC-SHA256.
///
/// Stored format: `pbkdf2$<iterations>$<base64url_salt>$<base64url_hash>`
/// Example: `pbkdf2$10000$aGVsbG8...=$c2FsdA...=`
///
/// Security properties:
/// - 10.000 PBKDF2 iterations (NIST SP 800-132 compliant)
/// - 128-bit cryptographically random salt (per password)
/// - 256-bit derived key output
/// - Constant-time comparison (prevents timing attacks)
/// - Backward-compatible migration from legacy `hashed_password_*` format
class PasswordHashService {
  static const int _iterations = 10000;
  static const int _keyLength = 32; // 256 bits
  static const int _saltLength = 16; // 128 bits
  static const String _algorithm = 'pbkdf2';
  static const String _sep = r'$';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Hash a plaintext password. Returns a storable hash string.
  ///
  /// Format: `pbkdf2$10000$<base64_salt>$<base64_hash>`
  static String hashPassword(String password) {
    final salt = _generateSalt();
    final hash = _pbkdf2(utf8.encode(password), salt, _iterations, _keyLength);
    return '$_algorithm$_sep$_iterations$_sep${base64.encode(salt)}$_sep${base64.encode(hash)}';
  }

  /// Verify a plaintext password against a stored hash string.
  ///
  /// Supports both the new PBKDF2 format and the legacy `hashed_password_*`
  /// format so existing accounts work after upgrade without forcing a
  /// password reset.
  static bool verifyPassword(String password, String storedHash) {
    if (storedHash.isEmpty) return false;

    // ── Legacy format migration path ──────────────────────────────────────
    // Old system stored: `hashed_password_<plaintext>`
    // This is insecure but we check it on first login so the user can log in
    // and the code path that saves the hash will rehash properly next time.
    if (_isLegacyHash(storedHash)) {
      final legacyPlain = storedHash.replaceFirst('hashed_password_', '');
      return _constantTimeStringCompare(password, legacyPlain);
    }

    // ── PBKDF2 format ─────────────────────────────────────────────────────
    try {
      final parts = storedHash.split(_sep);
      if (parts.length != 4 || parts[0] != _algorithm) return false;

      final iterations = int.parse(parts[1]);
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);

      final actual =
          _pbkdf2(utf8.encode(password), salt, iterations, expected.length);
      return _constantTimeCompare(actual, expected);
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the stored hash uses the legacy insecure format.
  /// Use this to trigger a rehash on successful login.
  static bool isLegacyHash(String storedHash) => _isLegacyHash(storedHash);

  /// Derive a cryptographic key using PBKDF2-HMAC-SHA256.
  static Uint8List deriveKey({
    required String password,
    required Uint8List salt,
    required int iterations,
    required int keyLength,
  }) {
    return _pbkdf2(utf8.encode(password), salt, iterations, keyLength);
  }

  // ── PBKDF2 Core ────────────────────────────────────────────────────────────

  /// PBKDF2 with HMAC-SHA256 (RFC 2898 / NIST SP 800-132)
  static Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    final blocks = (keyLength / 32).ceil(); // SHA-256 block = 32 bytes
    final output = <int>[];

    for (var i = 1; i <= blocks; i++) {
      output.addAll(_f(hmac, salt, iterations, i));
    }

    return Uint8List.fromList(output.take(keyLength).toList());
  }

  /// PRF block function F(password, salt, c, i)
  static List<int> _f(
      Hmac hmac, List<int> salt, int iterations, int blockIndex) {
    // U1 = HMAC(password, salt || INT(blockIndex))
    final saltBlock = Uint8List(salt.length + 4);
    for (var i = 0; i < salt.length; i++) {
      saltBlock[i] = salt[i];
    }
    saltBlock[salt.length] = (blockIndex >> 24) & 0xFF;
    saltBlock[salt.length + 1] = (blockIndex >> 16) & 0xFF;
    saltBlock[salt.length + 2] = (blockIndex >> 8) & 0xFF;
    saltBlock[salt.length + 3] = blockIndex & 0xFF;

    var u = hmac.convert(saltBlock).bytes;
    final result = List<int>.from(u);

    for (var c = 1; c < iterations; c++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static Uint8List _generateSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(_saltLength, (_) => rng.nextInt(256)),
    );
  }

  /// Constant-time byte comparison — prevents timing oracle attacks.
  static bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Constant-time string comparison.
  static bool _constantTimeStringCompare(String a, String b) {
    return _constantTimeCompare(utf8.encode(a), utf8.encode(b));
  }

  static bool _isLegacyHash(String storedHash) =>
      storedHash.startsWith('hashed_password_');
}

class PasswordHashServiceImpl implements IHashService {
  @override
  String hashPassword(String password) =>
      PasswordHashService.hashPassword(password);

  @override
  bool verifyPassword(String password, String storedHash) =>
      PasswordHashService.verifyPassword(password, storedHash);

  @override
  bool isLegacyHash(String storedHash) =>
      PasswordHashService.isLegacyHash(storedHash);

  @override
  Uint8List deriveKey({
    required String password,
    required Uint8List salt,
    required int iterations,
    required int keyLength,
  }) {
    return PasswordHashService.deriveKey(
      password: password,
      salt: salt,
      iterations: iterations,
      keyLength: keyLength,
    );
  }
}
