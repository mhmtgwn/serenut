// lib/domain/services/access_manager.dart
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/license_manager.dart';
import 'package:serenutos/domain/services/device_manager.dart';

enum AccessStatus {
  trialActive,
  licensed,
  paywall,
  restrictedOperation;
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
  AccessStatus checkAccess({required AuthUser? currentUser}) {
    if (currentUser == null)
      return AccessStatus.trialActive; // Handled by auth guard

    final state = _trialManager.getEntitlementState();

    if (state == EntitlementState.active ||
        state == EntitlementState.graceActive) {
      return AccessStatus.trialActive; // Or licensed
    }

    // state is graceExpired, revoked, or unknown
    final role = currentUser.role;
    if (role == UserRole.owner ||
        role == UserRole.admin ||
        role == UserRole.sysadmin) {
      return AccessStatus.paywall;
    } else {
      return AccessStatus.restrictedOperation;
    }
  }
}
