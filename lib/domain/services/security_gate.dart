// lib/domain/services/security_gate.dart
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/trial_manager.dart';

class LicenseException implements Exception {
  final String message;
  LicenseException(this.message);
  @override
  String toString() => 'LicenseException: $message';
}

class UpdateRequiredException implements Exception {
  final String message;
  UpdateRequiredException(this.message);
  @override
  String toString() => 'UpdateRequiredException: $message';
}

class SecurityGate {
  final LicenseService _licenseService;
  final TrialManager _trialManager;

  SecurityGate(this._licenseService, this._trialManager);

  /// Central access validation at the domain layer.
  /// Throws LicenseException if license is not valid.
  void ensureAccess() {
    if (_trialManager.isEntitlementActive()) {
      return; // Grant access during trial version
    }

    final status = _licenseService.checkLicenseStatus();
    if (status != 'valid') {
      throw LicenseException(
          'Ticari lisans doğrulaması başarısız oldu (Durum: $status).');
    }
  }

  /// Validates if device registration limits are exceeded for a license
  void validateDeviceLimit(String deviceId, int activeCount, int maxLimit) {
    if (activeCount > maxLimit) {
      throw LicenseException(
          'Lisans sınırları aşıldı. Cihaz: $deviceId (Aktif: $activeCount, Limit: $maxLimit).');
    }
  }

  /// Verifies force update requirements
  void checkForceUpdate(int currentVersionCode, int minRequiredVersionCode) {
    if (currentVersionCode < minRequiredVersionCode) {
      throw UpdateRequiredException(
          'Uygulama sürümü çok eski. Lütfen devam etmek için güncelleyin.');
    }
  }

  /// Central database integrity check.
  void ensureDbIntegrity() {
    // SQLCipher check removed - database uses plain sqlite now.
  }
}
