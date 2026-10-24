// lib/presentation/controllers/about_controller.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:serenutos/presentation/widgets/update_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';

final aboutControllerProvider = Provider<AboutController>((ref) {
  return AboutController(ref);
});

class AboutController {
  final Ref _ref;

  AboutController(this._ref);

  LicenseInfo? getLicenseInfo() {
    return _ref.read(licenseServiceProvider).getLicenseInfo();
  }

  Future<void> sendDiagnosticReport() async {
    final lic = getLicenseInfo();
    await Sentry.captureMessage(
      'Kullanıcı Manuel Sistem Teşhis Raporu Gönderdi',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('report_type', 'manual_user_feedback');
        if (lic != null) {
          scope.setTag('merchant_id', lic.merchantId);
          scope.setTag('license_tier', lic.tier.name);
        }
      },
    );
  }

  Future<UpdateInfo> checkForUpdate() async {
    final releaseManager = _ref.read(releaseManagerServiceProvider);
    final lic = getLicenseInfo();
    final deviceId =
        lic?.activationId ?? _ref.read(deviceManagerProvider).getDeviceId();
    final companyId = lic?.merchantId;
    final jwtToken = _ref.read(authServiceProvider).getJwtToken();
    final currentVer = await VersionChecker.getAppVersion();

    return releaseManager.checkForUpdates(
      currentVersion: currentVer,
      platform: Platform.isAndroid ? 'android' : 'windows',
      deviceId: deviceId,
      companyId: companyId,
      jwtToken: jwtToken,
    );
  }

  Future<bool> presentReleaseUpdateDialog(
    BuildContext context,
    UpdateInfo info,
  ) async {
    final releaseManager = _ref.read(releaseManagerServiceProvider);
    final jwtToken = _ref.read(authServiceProvider).getJwtToken();
    final deviceId = getLicenseInfo()?.activationId;

    return showUpdateDialog(
      context: context,
      updateInfo: info,
      releaseManager: releaseManager,
      platform: Platform.isAndroid ? 'android' : 'windows',
      jwtToken: jwtToken,
      deviceId: deviceId,
    );
  }

  Future<bool> presentUpdateDialog(
    BuildContext context,
    VersionCheckResult info,
  ) async {
    final releaseManager = _ref.read(releaseManagerServiceProvider);
    final jwtToken = _ref.read(authServiceProvider).getJwtToken();
    final deviceId = getLicenseInfo()?.activationId;

    return showUpdateDialog(
      context: context,
      updateInfo: UpdateInfo(
        hasUpdate: true,
        isForceUpdate: info.isForceUpdate,
        latestVersion: info.latestVersion,
        minRequiredVersion: info.minRequiredVersion,
        downloadUrl: info.downloadUrl,
        sha256Hash: info.sha256Hash,
        signature: info.signature,
        fileSizeBytes: info.fileSizeBytes,
        releaseNotes: info.releaseNotes,
        channel: 'stable',
      ),
      releaseManager: releaseManager,
      platform: Platform.isAndroid ? 'android' : 'windows',
      jwtToken: jwtToken,
      deviceId: deviceId,
    );
  }
}
