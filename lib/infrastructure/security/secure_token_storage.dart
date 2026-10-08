// lib/infrastructure/security/secure_token_storage.dart
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/device_manager.dart';

/// Hardware & installation bound secure token storage.
///
/// Encrypts sensitive session tokens (JWT access token and refresh token) using
/// AES-256 with a unique key derived from the installation device identity.
/// Provides seamless transparent migration from legacy unencrypted SharedPreferences keys.
class SecureTokenStorage {
  static const String keyJwtToken = 'auth_jwt_token';
  static const String keyRefreshToken = 'auth_refresh_token';
  static const String _securePrefix = 'sec_';
  static const String _saltPrefix = 'serenut_auth_sec_salt_v1_';

  final SharedPreferences _prefs;
  final enc.Encrypter _encrypter;
  final enc.IV _iv;

  // In-memory cache for fast synchronous access
  final Map<String, String?> _memoryCache = {};

  SecureTokenStorage._(this._prefs, this._encrypter, this._iv);

  /// Factory constructor initializing AES-256 encrypter with device-derived key.
  factory SecureTokenStorage(SharedPreferences prefs) {
    final deviceId = DeviceManager.resolveDeviceId(prefs);
    final keyBytes = crypto.sha256.convert(utf8.encode('$_saltPrefix$deviceId')).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(Uint8List.fromList(keyBytes.sublist(0, 16)));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return SecureTokenStorage._(prefs, encrypter, iv);
  }

  /// Initializes memory cache and performs transparent one-time migration
  /// from legacy plain-text storage without disrupting active user sessions.
  Future<void> initialize() async {
    for (final key in [keyJwtToken, keyRefreshToken]) {
      final token = await _loadAndMigrate(key);
      _memoryCache[key] = token;
    }
  }

  /// Synchronously gets the cached JWT access token.
  String? getJwtToken() => _memoryCache[keyJwtToken];

  /// Synchronously gets the cached Refresh token.
  String? getRefreshToken() => _memoryCache[keyRefreshToken];

  /// Saves token securely and updates memory cache.
  Future<void> saveToken(String key, String token) async {
    _memoryCache[key] = token;
    try {
      final encrypted = _encrypter.encrypt(token, iv: _iv);
      await _prefs.setString('$_securePrefix$key', encrypted.base64);
      // Remove legacy plain-text key if it still exists
      await _prefs.remove(key);
    } catch (e) {
      debugPrint('[SecureTokenStorage] ⚠️ Failed to encrypt token for key $key: $e');
    }
  }

  /// Deletes token from both secure and legacy storage and updates memory cache.
  Future<void> deleteToken(String key) async {
    _memoryCache[key] = null;
    await _prefs.remove('$_securePrefix$key');
    await _prefs.remove(key);
  }

  /// Clears all session tokens from memory and disk.
  Future<void> clearAll() async {
    await deleteToken(keyJwtToken);
    await deleteToken(keyRefreshToken);
  }

  Future<String?> _loadAndMigrate(String key) async {
    final secureCipher = _prefs.getString('$_securePrefix$key');
    if (secureCipher != null && secureCipher.isNotEmpty) {
      try {
        final decrypted = _encrypter.decrypt64(secureCipher, iv: _iv);
        // Ensure legacy plain-text key is purged
        if (_prefs.containsKey(key)) {
          await _prefs.remove(key);
        }
        return decrypted;
      } catch (e) {
        debugPrint('[SecureTokenStorage] ⚠️ Decryption failed for key $key: $e');
      }
    }

    // Check legacy unencrypted storage for migration
    final legacyToken = _prefs.getString(key);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      debugPrint('[SecureTokenStorage] 🔒 Migrating legacy token for key $key to secure encrypted storage...');
      await saveToken(key, legacyToken);
      return legacyToken;
    }

    return null;
  }
}
