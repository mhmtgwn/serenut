// lib/domain/services/access_manager.dart
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/license_manager.dart';
import 'package:serenutos/domain/services/device_manager.dart';

enum AccessStatus {
  trialActive,
  licensed,
  paywall;
}

class AccessManager {
  final TrialManager _trialManager;
  final LicenseManager _licenseManager;
  final DeviceManager _deviceManager;

  AccessManager({
    required TrialManager trialManager,
    required LicenseManager licenseManager,
    required DeviceManager deviceManager,
  })  : _trialManager = trialManager,
        _licenseManager = licenseManager,
        _deviceManager = deviceManager;

  /// Evaluates whether the app should grant entry or display the paywall.
  /// 1. If 30-day trial is active -> AccessStatus.trialActive
  /// 2. If trial expired but valid license exists and device limit is satisfied -> AccessStatus.licensed
  /// 3. Otherwise -> AccessStatus.paywall
  AccessStatus checkAccess() {
    _trialManager.initTrialIfNeeded();

    if (_trialManager.isTrialActive()) {
      return AccessStatus.trialActive;
    }

    final deviceId = _deviceManager.getDeviceId();
    if (_licenseManager.isDeviceAllowed(deviceId)) {
      return AccessStatus.licensed;
    }

    return AccessStatus.paywall;
  }
}
