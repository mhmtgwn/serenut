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

    return CompanyLicense(
      companyId: info.merchantId,
      tier: info.tier,
      activeDeviceIds: info.allowedDevices,
      isActive: true,
    );
  }

  /// Validates if the given device ID is registered and within the license tier limit.
  bool isDeviceAllowed(String deviceId) {
    final license = getLicense();
    if (license == null || !license.isActive) return false;

    // If device wildcard or direct match, allow it
    if (license.activeDeviceIds.contains('*') || license.activeDeviceIds.contains(deviceId)) {
      return true;
    }

    // Check if package quota limit has room for a new registration
    return license.activeDeviceIds.length < license.tier.deviceLimit;
  }

  /// Clears stored license data.
  Future<void> clearLicense() async {
    await _licenseService.clearLicense();
  }
}
