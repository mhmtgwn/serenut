// lib/domain/services/license_guard.dart
// Serenut OS — License Guard Service
// Enforces 72-hour offline grace period, clock integrity, and standard error catalog codes.
// Blueprint: v1_acceptance_criteria.md — Section 5.3 & DEVICE503

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/services/license_client.dart';

class LicenseException implements Exception {
  final String message;
  final String code;

  LicenseException(this.message, this.code);

  @override
  String toString() => '[$code] LicenseException: $message';
}

class LicenseGuard {
  static const String _lastVerifiedAtKey = 'license_last_verified_at';

  final LicenseService _licenseService;
  final LicenseClient _licenseClient;
  final TrialManager _trialManager;
  final SharedPreferences _prefs;

  LicenseGuard({
    required LicenseService licenseService,
    required LicenseClient licenseClient,
    required TrialManager trialManager,
    required SharedPreferences prefs,
  })  : _licenseService = licenseService,
        _licenseClient = licenseClient,
        _trialManager = trialManager,
        _prefs = prefs;

  /// Verifies license access according to 72-hour offline grace rules & clock integrity.
  /// Throws [LicenseException] on failure.
  Future<void> verifyAccess() async {
    // 1. If trial is active, allow bypass
    if (await _trialManager.isTrialActiveAsync()) {
      return;
    }

    // 2. Strong clock integrity check (DEVICE503)
    if (!_licenseService.checkClockIntegrity()) {
      throw LicenseException(
        'Cihaz saati geçersiz. Sistem saatini doğrulayın.',
        'DEVICE503',
      );
    }

    final info = _licenseService.getLicenseInfo();
    final token = _licenseService.getLicenseToken();

    // 3. Check if unlicensed
    if (info == null || token == null || !_licenseService.verifyLicenseToken(token)) {
      throw LicenseException(
        'Bu cihaz lisansınıza bağlı değil. Portaldan ekleyin.',
        'DEVICE501',
      );
    }

    // 4. Check if license has expired cryptographically
    final now = DateTime.now();
    if (now.isAfter(info.expiryDate)) {
      final graceEnd = info.expiryDate.add(const Duration(days: 7));
      if (now.isAfter(graceEnd)) {
        throw LicenseException(
          'Lisansınızın süresi dolmuştur. Lütfen yenileyin.',
          'LICENSE102',
        );
      }
    }

    // 5. Enforce 72-hour offline verification check
    final lastVerifiedStr = _prefs.getString(_lastVerifiedAtKey);
    DateTime? lastVerified;
    if (lastVerifiedStr != null) {
      lastVerified = DateTime.tryParse(lastVerifiedStr);
    }

    try {
      // Attempt online validation
      final isValid = await _licenseClient.validate(info.merchantId);
      if (isValid) {
        // Validation succeeded online, save timestamp
        await _prefs.setString(_lastVerifiedAtKey, DateTime.now().toIso8601String());
        return;
      } else {
        // Server explicitly returned invalid/blocked license
        throw LicenseException(
          'Lisans doğrulaması sunucu tarafından reddedildi.',
          'LICENSE101',
        );
      }
    } on SocketException {
      // Offline fallback: check 72-hour grace period (AC 5.3)
      if (lastVerified == null) {
        throw LicenseException(
          'Lütfen internete bağlanın. (İlk doğrulama gerekli)',
          'DEVICE501',
        );
      }

      final diff = DateTime.now().difference(lastVerified);
      if (diff.inHours > 72) {
        throw LicenseException(
          '72 saatlik çevrimdışı çalışma süresi aşıldı. Lütfen internete bağlanın.',
          'DEVICE501',
        );
      }
      
      // Offline grace is active and within 72 hours — allow execution
      return;
    } catch (e) {
      if (e is LicenseException) rethrow;
      
      // Other network timeouts / errors — treat as offline grace check
      if (lastVerified == null) {
        throw LicenseException(
          'Lütfen internete bağlanın. (İlk doğrulama gerekli)',
          'DEVICE501',
        );
      }
      final diff = DateTime.now().difference(lastVerified);
      if (diff.inHours > 72) {
        throw LicenseException(
          '72 saatlik çevrimdışı çalışma süresi aşıldı. Lütfen internete bağlanın.',
          'DEVICE501',
        );
      }
    }
  }

  /// Sets the last verified timestamp to simulate successful verification in tests
  Future<void> setLastVerifiedNow() async {
    await _prefs.setString(_lastVerifiedAtKey, DateTime.now().toIso8601String());
  }
}
