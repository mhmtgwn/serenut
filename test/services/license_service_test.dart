import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import '../helpers/rsa_test_keys.dart';

final testLicenseKeys = RsaTestKeys.generate();

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

  final signatureBase64 = base64.encode(testLicenseKeys.sign(payloadBytes));

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
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
  });

  tearDownAll(() {
    DatabaseManager.overrideDatabasePath = null;
  });

  group('LicenseService Tests', () {
    late SharedPreferences prefs;
    late LicenseService licenseService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      licenseService =
          LicenseService(prefs, rsaModulus: testLicenseKeys.modulus);
      // Clean database connection for each test run
      await DatabaseManager().close();
    });

    test('getDeviceUuid returns stored or newly generated UUID', () {
      final uuid1 = licenseService.getDeviceUuid();
      expect(uuid1.length, 36); // v4 UUID length

      final uuid2 = licenseService.getDeviceUuid();
      expect(uuid2, uuid1); // Should be persistent
    });

    test('verifyLicenseToken succeeds with valid token', () {
      final uuid = licenseService.getDeviceUuid();
      final expiry = DateTime.now().add(const Duration(days: 30));

      final token = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: expiry,
      );

      final isValid = licenseService.verifyLicenseToken(token);
      expect(isValid, isTrue);
    });

    test('verifyLicenseToken fails on device UUID mismatch', () {
      final expiry = DateTime.now().add(const Duration(days: 30));

      final token = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: ['another-device-uuid'],
        expiryDate: expiry,
      );

      final isValid = licenseService.verifyLicenseToken(token);
      expect(isValid, isFalse);
    });

    test('verifyLicenseToken fails on signature tampering', () {
      final uuid = licenseService.getDeviceUuid();
      final expiry = DateTime.now().add(const Duration(days: 30));

      final token = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: expiry,
      );

      // Tamper signature string
      final decodedBytes = base64.decode(token);
      final decodedStr = utf8.decode(decodedBytes);
      final map = json.decode(decodedStr) as Map<String, dynamic>;
      map['signature'] = 'tampered_signature';
      final tamperedToken = base64.encode(utf8.encode(json.encode(map)));

      final isValid = licenseService.verifyLicenseToken(tamperedToken);
      expect(isValid, isFalse);
    });

    test('checkLicenseStatus checks expiry and grace period', () async {
      final uuid = licenseService.getDeviceUuid();

      // 1. Valid (future expiry)
      final futureExpiry = DateTime.now().add(const Duration(days: 30));
      final validToken = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: futureExpiry,
      );
      await licenseService.saveLicenseToken(validToken);
      expect(licenseService.checkLicenseStatus(), 'valid');

      // 2. Expired (but inside 3-day grace period)
      final insideGrace = DateTime.now().subtract(const Duration(days: 2));
      final graceToken = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: insideGrace,
      );
      await licenseService.saveLicenseToken(graceToken);
      expect(licenseService.checkLicenseStatus(),
          'valid'); // Inside grace still counts as valid but near-expired

      // 3. Fully expired (outside 7-day grace period)
      final expiredDate = DateTime.now().subtract(const Duration(days: 8));
      final expiredToken = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: expiredDate,
      );
      await licenseService.saveLicenseToken(expiredToken);
      expect(licenseService.checkLicenseStatus(), 'expired');
    });

    test('checkClockIntegrity detects system time travel / tempering',
        () async {
      final uuid = licenseService.getDeviceUuid();
      final futureExpiry = DateTime.now().add(const Duration(days: 30));
      final token = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: futureExpiry,
      );
      await licenseService.saveLicenseToken(token);

      // Check initially succeeds and saves last time
      expect(licenseService.checkLicenseStatus(), 'valid');

      // Simulate time traveling backwards by 2 hours (more than 5 mins limit)
      final futureTime = DateTime.now().toUtc().add(const Duration(hours: 2));
      await prefs.setString('last_system_time', futureTime.toIso8601String());

      // Re-create to force reading SharedPreferences without memory cache
      licenseService =
          LicenseService(prefs, rsaModulus: testLicenseKeys.modulus);

      // Next check fails with 'tampered'
      expect(licenseService.checkLicenseStatus(), 'tampered');
    });

    test('checkClockIntegrity is immune to DST transitions (1 hour back)',
        () async {
      final uuid = licenseService.getDeviceUuid();
      final futureExpiry = DateTime.now().add(const Duration(days: 30));
      final token = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: futureExpiry,
      );
      await licenseService.saveLicenseToken(token);

      // Write last system time in UTC (e.g. 50 minutes ago in UTC)
      final pastUtc =
          DateTime.now().toUtc().subtract(const Duration(minutes: 50));
      await prefs.setString('last_system_time', pastUtc.toIso8601String());

      // Re-create to force reading SharedPreferences without memory cache
      licenseService =
          LicenseService(prefs, rsaModulus: testLicenseKeys.modulus);

      // Simulate a local clock going back by 1 hour (DST transition)
      // Since UTC remains correct, the UTC-based checks pass and status remains 'valid'
      expect(licenseService.checkLicenseStatus(), 'valid');
    });

    test(
        'checkClockIntegrity correctly parses legacy local timestamps and migrates them to UTC',
        () async {
      final uuid = licenseService.getDeviceUuid();
      final futureExpiry = DateTime.now().add(const Duration(days: 30));
      final token = generateLicenseTokenHelper(
        merchantId: 'M123',
        allowedDevices: [uuid],
        expiryDate: futureExpiry,
      );
      await licenseService.saveLicenseToken(token);

      // Save time in legacy format (local time string without 'Z')
      // To simulate compatibility, we write a time from 10 minutes ago
      final legacyTimeLocalStr = DateTime.now()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
      // Ensure it has no 'Z' suffix (representing legacy local time)
      final legacyCleanStr = legacyTimeLocalStr.replaceAll('Z', '');
      await prefs.setString('last_system_time', legacyCleanStr);

      // Re-create to force reading SharedPreferences without memory cache
      licenseService =
          LicenseService(prefs, rsaModulus: testLicenseKeys.modulus);

      // Check should succeed because legacy parses properly and uses the 2-hour grace margin
      expect(licenseService.checkLicenseStatus(), 'valid');

      // Verify that after checking, the value in SharedPreferences is updated to new UTC format (has 'Z')
      final updatedTimeStr = prefs.getString('last_system_time')!;
      expect(updatedTimeStr.endsWith('Z'), isTrue);
    });
  });
}
