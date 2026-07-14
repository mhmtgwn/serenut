// test/services/license_guard_test.dart
// Serenut POS — License Guard Unit & Integration Tests
// Verifies 72-hour offline grace, clock integrity checks, and DEVICE503 handling.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/license_guard.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/license_client.dart';

class FakeLicenseClient implements LicenseClient {
  bool validationResult = true;
  bool shouldThrowSocket = false;

  @override
  Future<bool> validate(String licenseId) async {
    if (shouldThrowSocket) {
      throw const SocketException('Network unreachable');
    }
    return validationResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLicenseService extends LicenseService {
  bool clockIntegrityResult = true;
  bool verifyTokenResult = true;

  FakeLicenseService(super.prefs);

  @override
  bool checkClockIntegrity() {
    return clockIntegrityResult;
  }

  @override
  bool verifyLicenseToken(String tokenStr) {
    return verifyTokenResult;
  }
}

void main() {
  group('LicenseGuard Tests', () {
    late SharedPreferences prefs;
    late FakeLicenseService licenseService;
    late FakeLicenseClient licenseClient;
    late TrialManager trialManager;
    late LicenseGuard licenseGuard;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      licenseService = FakeLicenseService(prefs);
      licenseClient = FakeLicenseClient();
      trialManager = TrialManager(prefs);
      licenseGuard = LicenseGuard(
        licenseService: licenseService,
        licenseClient: licenseClient,
        trialManager: trialManager,
        prefs: prefs,
      );
    });

    test('Bypasses validation if trial is active', () async {
      // Set trial active (first launch timestamp within 30 days)
      await prefs.setInt('nutopiano_first_launch_timestamp',
          DateTime.now().millisecondsSinceEpoch);
      await prefs.setString('serenut_trial_checksum',
          'invalid_but_ignored_due_to_initialization');

      // Initialize trial manager checksum correctly
      await trialManager.initTrialIfNeeded();

      expect(trialManager.isTrialActive(), isTrue);

      // Verify no exceptions are thrown
      await expectLater(licenseGuard.verifyAccess(), completes);
    });

    test('Throws DEVICE503 if clock manipulation is detected', () async {
      // Expire trial first
      await prefs.setInt(
          'nutopiano_first_launch_timestamp',
          DateTime.now()
              .subtract(const Duration(days: 40))
              .millisecondsSinceEpoch);
      await trialManager.initTrialIfNeeded();

      // Configure a valid license token and trigger clock integrity failure
      await prefs.setString('license_token',
          'eyJtZXJjaGFudElkIjoiMSIsImFsbG93ZWREZXZpY2VzIjpbIioiXSwiZXhwaXJ5RGF0ZSI6IjIwMzAtMDEtMDFUMDA6MDA6MDAuMDAwWiIsInRpZXIiOiJQUk8iLCJmZWF0dXJlcyI6W10sInNpZ25hdHVyZSI6IiJ9');
      licenseService.clockIntegrityResult = false;

      // Verify DEVICE503 error code is thrown
      try {
        await licenseGuard.verifyAccess();
        fail('Should have thrown LicenseException');
      } on LicenseException catch (e) {
        expect(e.code, equals('DEVICE503'));
      }
    });

    test('Enforces 72-hour offline grace check', () async {
      // Expire trial
      await prefs.setInt(
          'nutopiano_first_launch_timestamp',
          DateTime.now()
              .subtract(const Duration(days: 40))
              .millisecondsSinceEpoch);
      await trialManager.initTrialIfNeeded();

      // Add valid license token
      await prefs.setString('license_token',
          'eyJtZXJjaGFudElkIjoiMSIsImFsbG93ZWREZXZpY2VzIjpbIioiXSwiZXhwaXJ5RGF0ZSI6IjIwMzAtMDEtMDFUMDA6MDA6MDAuMDAwWiIsInRpZXIiOiJQUk8iLCJmZWF0dXJlcyI6W10sInNpZ25hdHVyZSI6IiJ9');

      // Simulate network unreachable (offline)
      licenseClient.shouldThrowSocket = true;

      // Scenario A: Never verified online before
      try {
        await licenseGuard.verifyAccess();
        fail('Should have failed because never verified online');
      } on LicenseException catch (e) {
        expect(e.code, equals('DEVICE501'));
      }

      // Scenario B: Verified online 2 hours ago (within 72 hours)
      await prefs.setString('license_last_verified_at',
          DateTime.now().subtract(const Duration(hours: 2)).toIso8601String());
      await expectLater(licenseGuard.verifyAccess(), completes);

      // Scenario C: Verified online 75 hours ago (exceeded 72 hours)
      await prefs.setString('license_last_verified_at',
          DateTime.now().subtract(const Duration(hours: 75)).toIso8601String());
      try {
        await licenseGuard.verifyAccess();
        fail('Should have failed because offline grace exceeded 72 hours');
      } on LicenseException catch (e) {
        expect(e.code, equals('DEVICE501'));
      }
    });
  });
}
