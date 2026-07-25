// lib/domain/services/access_manager.dart
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/license_manager.dart';

enum AccessStatus {
  trialActive,
  licensed,
  paywall,
  restrictedOperation;
}

class AccessManager {
  final TrialManager _trialManager;
  final LicenseManager _licenseManager;

  AccessManager({
    required TrialManager trialManager,
    required LicenseManager licenseManager,
  })  : _trialManager = trialManager,
        _licenseManager = licenseManager;

  /// Evaluates whether the app should grant entry or display the paywall.
  /// 1. If 30-day trial is active -> AccessStatus.trialActive
  /// 2. If trial expired but valid license exists and device limit is satisfied -> AccessStatus.licensed
  /// 3. Otherwise -> AccessStatus.paywall
  AccessStatus checkAccess({required AuthUser? currentUser}) {
    if (currentUser == null) {
      return AccessStatus.trialActive; // Handled by auth guard
    }

    // 1. If trial or commercial subscription entitlement is active or remaining days > 0, grant access
    if (_trialManager.isEntitlementActive() ||
        _trialManager.isTrialActive() ||
        _trialManager.getRemainingDays() > 0) {
      return AccessStatus.trialActive;
    }

    // 2. If trial expired, verify local RSA signed license & device allowance
    if (_licenseManager.getLicense() != null &&
        _licenseManager.isCurrentDeviceAllowed()) {
      return AccessStatus.licensed;
    }

    // 3. Otherwise (trial/subscription expired & no valid offline license), show paywall
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
