// lib/providers/license_provider.dart
// Serenut OS — License Status Provider

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';

class LicenseStatus {
  final String status;
  final int daysLeft;
  final String tierName;
  final DateTime? expiryDate;
  final String deviceUuid;

  const LicenseStatus({
    required this.status,
    required this.daysLeft,
    required this.tierName,
    this.expiryDate,
    required this.deviceUuid,
  });
}

final licenseStatusProvider = Provider<LicenseStatus>((ref) {
  // Entitlement/license objects are backed by SharedPreferences and keep a
  // stable service identity. Recompute this derived snapshot whenever auth
  // publishes a post-bootstrap refresh; otherwise Riverpod retains the old
  // pre-activation "unlicensed" value for the lifetime of the process.
  ref.watch(authNotifierProvider);
  final service = ref.watch(licenseServiceProvider);
  final trialManager = ref.watch(trialManagerProvider);

  final isTrialActive = trialManager.isTrialActive();
  final isCommercialActive = trialManager.isCommercialActive();
  final remainingDays = trialManager.getRemainingDays();

  if (isTrialActive) {
    return LicenseStatus(
      status: 'trial',
      daysLeft: remainingDays,
      tierName: 'DENEME',
      expiryDate: trialManager.getExpiryDateSync(),
      deviceUuid: service.getDeviceUuid(),
    );
  }

  if (isCommercialActive) {
    return LicenseStatus(
      status: 'active',
      daysLeft: remainingDays,
      tierName: 'TİCARİ LİSANS',
      expiryDate: trialManager.getExpiryDateSync(),
      deviceUuid: service.getDeviceUuid(),
    );
  }

  final status = service.checkLicenseStatus();
  final info = service.getLicenseInfo();
  final daysLeft = service.getRemainingDays();
  final deviceUuid = service.getDeviceUuid();

  return LicenseStatus(
    status: status,
    daysLeft: daysLeft,
    tierName: info?.tier.name ?? 'UNLICENSED',
    expiryDate: info?.expiryDate,
    deviceUuid: deviceUuid,
  );
});

