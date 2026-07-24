// test/services/licensing_system_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/license_manager.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/access_manager.dart';
import '../helpers/rsa_test_keys.dart';

final testLicensingKeys = RsaTestKeys.generate();

String generateLicenseTokenHelper({
  required String merchantId,
  required List<String> allowedDevices,
  required DateTime expiryDate,
  LicenseTier tier = LicenseTier.basic,
  List<String> features = const [],
}) {
  final payloadMap = {
    'allowed_devices': allowedDevices,
    'expiry_date': expiryDate.toIso8601String(),
    'features': features,
    'merchant_id': merchantId,
    'tier': tier == LicenseTier.proPlus ? 'pro_plus' : tier.name.toLowerCase(),
  };
  final payload = json.encode(payloadMap);
  final payloadBytes = utf8.encode(payload);

  final signatureBase64 = base64.encode(testLicensingKeys.sign(payloadBytes));

  final info = LicenseInfo(
    merchantId: merchantId,
    allowedDevices: allowedDevices,
    expiryDate: expiryDate,
    tier: tier,
    features: features,
    signature: signatureBase64,
  );

  return base64.encode(utf8.encode(json.encode(info.toJson())));
}

void main() {
  group('TrialManager Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('New installation fails closed until backend entitlement arrives',
        () async {
      final manager = TrialManager(prefs);

      expect(manager.getEntitlementState(), EntitlementState.unknown);
      expect(manager.isTrialActive(), isFalse);
      expect(manager.getRemainingDays(), equals(0));
    });

    test('Missing entitlement remains closed across repeated checks', () async {
      final manager = TrialManager(prefs);

      expect(manager.getEntitlementState(), EntitlementState.unknown);
      expect(manager.getEntitlementState(), EntitlementState.unknown);
    });

    test('Unsigned local subscription cache cannot grant access', () async {
      await prefs.setString(
        'serenut_subscription_cache',
        '{"status":"active","current_period_end":"2099-01-01T00:00:00Z"}',
      );
      final manager = TrialManager(prefs);

      expect(manager.isCommercialActive(), isFalse);
      expect(manager.isEntitlementActive(), isFalse);
    });

    test('Trial expires after 30 days', () async {
      final manager = TrialManager(prefs);
      final pastDate =
          DateTime.now().toUtc().subtract(const Duration(days: 31));
      await manager.cacheSubscription({
        'status': 'trialing',
        'trial_started_at':
            pastDate.subtract(const Duration(days: 30)).toIso8601String(),
        'trial_ends_at': pastDate.toIso8601String(),
        'grace_hours_override': 72,
      });

      expect(manager.isTrialActive(), isFalse);
      expect(manager.getRemainingDays(), equals(0));
    });
  });

  group('LicenseManager & Quota Tests', () {
    test('Validates device capacity limits according to package tier',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final licenseService =
          LicenseService(prefs, rsaModulus: testLicensingKeys.modulus);
      final manager = LicenseManager(licenseService);

      final uuid = licenseService.getDeviceUuid();

      // BASIC License with max 3 devices
      final token = generateLicenseTokenHelper(
        merchantId: 'COMP_1',
        tier: LicenseTier.basic,
        allowedDevices: [uuid, 'device_1'],
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );
      await licenseService.saveLicenseToken(token);

      // Device already in allowed list
      expect(manager.isDeviceAllowed('device_1'), isTrue);

      // Unregistered devices must be activated atomically by the backend,
      // even when the package still has capacity.
      expect(manager.isDeviceAllowed('device_3'), isFalse);

      // Save license containing 3 active devices
      final fullToken = generateLicenseTokenHelper(
        merchantId: 'COMP_1',
        tier: LicenseTier.basic,
        allowedDevices: [uuid, 'device_1', 'device_2'],
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );
      await licenseService.saveLicenseToken(fullToken);

      // 4th device exceeds quota limit of BASIC
      expect(manager.isDeviceAllowed('device_4'), isFalse);
    });
  });

  group('AccessManager Orchestration Flow', () {
    test('Unsigned local first-launch marker cannot grant trial access',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('nutopiano_first_launch_timestamp',
          DateTime.now().millisecondsSinceEpoch);
      final trial = TrialManager(prefs);
      final licenseService =
          LicenseService(prefs, rsaModulus: testLicensingKeys.modulus);
      final license = LicenseManager(licenseService);
      final orchestrator = AccessManager(
        trialManager: trial,
        licenseManager: license,
      );

      final dummyUser = AuthUser(
        id: '1',
        name: 'Test',
        email: 'test@serenut.com',
        companyId: 'C',
        role: UserRole.owner,
        permissions: [],
        createdAt: DateTime.now(),
      );
      expect(orchestrator.checkAccess(currentUser: dummyUser),
          equals(AccessStatus.paywall));
    });

    test(
        'Redirects to paywall when trial is expired and no valid license is set',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final trial = TrialManager(prefs);
      final licenseService =
          LicenseService(prefs, rsaModulus: testLicensingKeys.modulus);
      final license = LicenseManager(licenseService);
      final orchestrator = AccessManager(
        trialManager: trial,
        licenseManager: license,
      );

      // Expire trial
      await prefs.setString(
          'serenut_subscription_cache', '{"status":"canceled"}');

      final dummyUser = AuthUser(
        id: '1',
        name: 'Test',
        email: 'test@serenut.com',
        companyId: 'C',
        role: UserRole.owner,
        permissions: [],
        createdAt: DateTime.now(),
      );

      expect(orchestrator.checkAccess(currentUser: dummyUser),
          equals(AccessStatus.paywall));
    });

    test('Allows access with an active commercial subscription', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final trial = TrialManager(prefs);
      final licenseService =
          LicenseService(prefs, rsaModulus: testLicensingKeys.modulus);
      final license = LicenseManager(licenseService);
      final orchestrator = AccessManager(
        trialManager: trial,
        licenseManager: license,
      );

      // Active commercial subscription
      await trial.cacheSubscription({
        'status': 'active',
        'current_period_end':
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      });
      final token = generateLicenseTokenHelper(
        merchantId: 'C',
        allowedDevices: [licenseService.getDeviceUuid()],
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );
      await licenseService.saveLicenseToken(token);

      final dummyUser = AuthUser(
        id: '1',
        name: 'Test',
        email: 'test@serenut.com',
        companyId: 'C',
        role: UserRole.owner,
        permissions: [],
        createdAt: DateTime.now(),
      );

      expect(orchestrator.checkAccess(currentUser: dummyUser),
          equals(AccessStatus.licensed));
    });

    test('Restricts operational users when entitlement is expired', () async {
      SharedPreferences.setMockInitialValues({
        'serenut_subscription_cache': '{"status":"canceled"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final orchestrator = AccessManager(
        trialManager: TrialManager(prefs),
        licenseManager: LicenseManager(
          LicenseService(prefs, rsaModulus: testLicensingKeys.modulus),
        ),
      );

      final staffUser = AuthUser(
        id: 'staff-1',
        name: 'Staff',
        email: 'staff@serenut.com',
        companyId: 'C',
        role: UserRole.staff,
        permissions: const [],
        createdAt: DateTime.now(),
      );

      expect(orchestrator.checkAccess(currentUser: staffUser),
          equals(AccessStatus.restrictedOperation));
    });
  });
}
