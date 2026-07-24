// lib/domain/services/license_manager.dart
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/license_service.dart';

class LicenseManager {
  final LicenseService _licenseService;

  LicenseManager(this._licenseService);

  /// Saves the active license locally (noop/deprecated in RSA mode).
  Future<void> saveLicense(CompanyLicense license) async {
    // Stored via LicenseService.saveLicenseToken in RSA mode
  }

  /// Retrieves the active license.
  CompanyLicense? getLicense() {
    final info = _licenseService.getLicenseInfo();
    final token = _licenseService.getLicenseToken();
    if (info == null || token == null) return null;

    final isValid = _licenseService.verifyLicenseToken(token);
    if (!isValid) return null;

    // Check expiration or revoked status if available in info
    if (info.expiryDate.isBefore(DateTime.now())) {
      // License expired
      return null;
    }

    return CompanyLicense(
      companyId: info.merchantId,
      tier: info.tier,
      activeDeviceIds: info.allowedDevices ?? [],
      isActive: true,
    );
  }

  /// Validates if the given device ID is registered and within the license tier limit.
  bool isDeviceAllowed(String deviceId) {
    final license = getLicense();
    if (license == null || !license.isActive) return false;

    // If device wildcard or direct match, allow it
    if (license.activeDeviceIds.contains('*') ||
        license.activeDeviceIds.contains(deviceId)) {
      return true;
    }

    // Yeni cihaz kaydı yalnızca sunucudaki atomik aktivasyon endpoint'i
    // tarafından yapılabilir. İstemci tarafında kota boşluğu varsayılmaz.
    return false;
  }

  bool isCurrentDeviceAllowed() {
    return isDeviceAllowed(_licenseService.getDeviceUuid());
  }

  /// Clears stored license data.
  Future<void> clearLicense() async {
    await _licenseService.clearLicense();
  }

  /// Lockout mechanism
  bool get isLockedDown {
    final license = getLicense();
    return license == null || !license.isActive;
  }

  void enforceWriteAccess({bool isInternalSync = false}) {
    if (isLockedDown && !isInternalSync) {
      throw Exception(
          'LICENSE_LOCKDOWN: Access denied. System is locked due to invalid, expired, or revoked license.');
    }
  }

  /// License Recovery: Apply a new license token without wiping local DB.
  Future<bool> recoverLicense(String newToken) async {
    // Save new token to license service
    await _licenseService.saveLicenseToken(newToken);
    return !isLockedDown;
  }
}
