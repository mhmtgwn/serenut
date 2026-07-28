import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/license_manager.dart';
import 'package:serenutos/domain/services/trial_manager.dart';

enum AccessStatus { trialActive, licensed, paywall, restrictedOperation }

/// Resolves the entry state from the verified local entitlement cache.
/// It never invents a company, trial, or commercial entitlement.
class AccessManager {
  AccessManager({
    required TrialManager trialManager,
    required LicenseManager licenseManager,
  })  : _trialManager = trialManager,
        _licenseManager = licenseManager;

  final TrialManager _trialManager;
  final LicenseManager _licenseManager;

  AccessStatus checkAccess({required AuthUser? currentUser}) {
    if (currentUser == null) return AccessStatus.paywall;

    if (_trialManager.isCommercialActive()) return AccessStatus.licensed;
    if (_trialManager.isTrialActive() || _trialManager.getRemainingDays() > 0) {
      return AccessStatus.trialActive;
    }
    if (_licenseManager.getLicense() != null &&
        _licenseManager.isCurrentDeviceAllowed()) {
      return AccessStatus.licensed;
    }

    return switch (currentUser.role) {
      UserRole.owner ||
      UserRole.admin ||
      UserRole.sysadmin =>
        AccessStatus.paywall,
      _ => AccessStatus.restrictedOperation,
    };
  }
}
