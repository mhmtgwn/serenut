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
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/access_manager.dart';
import 'package:pointycastle/export.dart';

String generateLicenseTokenHelper({
  required String merchantId,
  required List<String> allowedDevices,
  required DateTime expiryDate,
  LicenseTier tier = LicenseTier.basic,
  List<String> features = const [],
}) {
  final modulus = BigInt.parse(
      '24411462201226996438841939549021454888733195236274468065775741224235870828599975687442961469702706222823140813618470146034318791144081164140895510392862259766582087914988353091642332590862692172508245336721761478288563513793312713764686147506940136020087563505042690937627842320486248227124477581576031460706918080381582170251418495030474651546222624978118721452561800320320246965787168638531779352900516824205685716199734459208444432818729619600489270457687453750695905613821629449668637610680017348238336982462564377297468305133351943448287065558841371731196118193920355175788560618289960848258703300389635524278281');
  final privateExponent = BigInt.parse(
      '6684964403702044724169496453702306344326024305436896384889104288437999508077631927957319216576200750431159622533998866455253053155665115169090006027445549476339300422819109402867158139802138279445282497797358030591037877566086077695573832938752988710995491130582742180105999452610993742957459132345774701699825158804056026428547722184241466314083113853337376967071262648055968258835003688193743958419042890456439736041430580551455657726912631144413462459038019832517570688284032050806223028859508074311230005951475716534070490518303245968006947288804945581389885433737412096196007272363897362949702710055189984892673');
  final p = BigInt.parse(
      '165459986035049506858151599209743457345028087382264571756838600875214015179729730612544781187952046338248144255732481262603484040549959251783515841038081387836130881397616996454946080115821071783269840527374209689096824610869945740111971001950967221172543243512794373357098950541386421533427694183039867628321');
  final q = BigInt.parse(
      '147536953109955533230758052726267768709043226827632325673221586517858950536695234149055834157050546416850232503023766679292253149457695267554303723576730374577386021326302055170150067235195292104753390330918476824765432876745115164837973897927362298648474840592618107362774499480187427469986894506200825206761');

  final privateKey = RSAPrivateKey(modulus, privateExponent, p, q);

  final payloadMap = {
    'allowed_devices': allowedDevices,
    'expiry_date': expiryDate.toIso8601String(),
    'features': features,
    'merchant_id': merchantId,
    'tier': tier == LicenseTier.proPlus ? 'pro_plus' : tier.name.toLowerCase(),
  };
  final payload = json.encode(payloadMap);
  final payloadBytes = utf8.encode(payload);

  final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

  final signature = signer.generateSignature(payloadBytes);
  final signatureBase64 = base64.encode(signature.bytes);

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

    test('New installation gets 30 days trial', () async {
      await prefs.setInt('nutopiano_first_launch_timestamp', DateTime.now().millisecondsSinceEpoch);
      final manager = TrialManager(prefs);
      manager.initTrialIfNeeded();

      expect(manager.isTrialActive(), isTrue);
      expect(manager.getRemainingDays(), equals(30));
    });

    test('Trial expires after 30 days', () async {
      final manager = TrialManager(prefs);
      // Mock setting start date to 31 days ago
      final pastDate = DateTime.now().subtract(const Duration(days: 31));
      await prefs.setInt(
          'nutopiano_first_launch_timestamp', pastDate.millisecondsSinceEpoch);

      expect(manager.isTrialActive(), isFalse);
      expect(manager.getRemainingDays(), equals(0));
    });
  });

  group('LicenseManager & Quota Tests', () {
    test('Validates device capacity limits according to package tier',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final licenseService = LicenseService(prefs);
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

      // New device within limit (3rd device)
      expect(manager.isDeviceAllowed('device_3'), isTrue);

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
    test('Allows access when trial is active', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('nutopiano_first_launch_timestamp', DateTime.now().millisecondsSinceEpoch);
      final device = DeviceManager(prefs);
      final trial = TrialManager(prefs);
      final licenseService = LicenseService(prefs);
      final license = LicenseManager(licenseService);
      final orchestrator = AccessManager(
        trialManager: trial,
        licenseManager: license,
        deviceManager: device,
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
          equals(AccessStatus.trialActive));
    });

    test(
        'Redirects to paywall when trial is expired and no valid license is set',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final device = DeviceManager(prefs);
      final trial = TrialManager(prefs);
      final licenseService = LicenseService(prefs);
      final license = LicenseManager(licenseService);
      final orchestrator = AccessManager(
        trialManager: trial,
        licenseManager: license,
        deviceManager: device,
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

    test('Allows access when trial is expired but valid license is configured',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final device = DeviceManager(prefs);
      final trial = TrialManager(prefs);
      final licenseService = LicenseService(prefs);
      final license = LicenseManager(licenseService);
      final orchestrator = AccessManager(
        trialManager: trial,
        licenseManager: license,
        deviceManager: device,
      );

      // Expire trial but mock active
      await prefs.setString('serenut_subscription_cache',
          '{"status":"active", "current_period_end": "${DateTime.now().add(const Duration(days: 30)).toIso8601String()}"}');

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
          equals(AccessStatus.trialActive));
    });
  });
}
