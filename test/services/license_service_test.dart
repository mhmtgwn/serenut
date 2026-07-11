// test/services/license_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:pointycastle/export.dart';

class MockSharedPreferences {
  final Map<String, dynamic> _data = {};

  String? getString(String key) => _data[key] as String?;
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }
}

String generateLicenseTokenHelper({
  required String merchantId,
  required List<String> allowedDevices,
  required DateTime expiryDate,
  LicenseTier tier = LicenseTier.basic,
  List<String> features = const [],
}) {
  final modulus = BigInt.parse('24411462201226996438841939549021454888733195236274468065775741224235870828599975687442961469702706222823140813618470146034318791144081164140895510392862259766582087914988353091642332590862692172508245336721761478288563513793312713764686147506940136020087563505042690937627842320486248227124477581576031460706918080381582170251418495030474651546222624978118721452561800320320246965787168638531779352900516824205685716199734459208444432818729619600489270457687453750695905613821629449668637610680017348238336982462564377297468305133351943448287065558841371731196118193920355175788560618289960848258703300389635524278281');
  final privateExponent = BigInt.parse('6684964403702044724169496453702306344326024305436896384889104288437999508077631927957319216576200750431159622533998866455253053155665115169090006027445549476339300422819109402867158139802138279445282497797358030591037877566086077695573832938752988710995491130582742180105999452610993742957459132345774701699825158804056026428547722184241466314083113853337376967071262648055968258835003688193743958419042890456439736041430580551455657726912631144413462459038019832517570688284032050806223028859508074311230005951475716534070490518303245968006947288804945581389885433737412096196007272363897362949702710055189984892673');
  final p = BigInt.parse('165459986035049506858151599209743457345028087382264571756838600875214015179729730612544781187952046338248144255732481262603484040549959251783515841038081387836130881397616996454946080115821071783269840527374209689096824610869945740111971001950967221172543243512794373357098950541386421533427694183039867628321');
  final q = BigInt.parse('147536953109955533230758052726267768709043226827632325673221586517858950536695234149055834157050546416850232503023766679292253149457695267554303723576730374577386021326302055170150067235195292104753390330918476824765432876745115164837973897927362298648474840592618107362774499480187427469986894506200825206761');

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
  group('LicenseService Tests', () {
    late SharedPreferences prefs;
    late LicenseService licenseService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      licenseService = LicenseService(prefs);
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
      expect(licenseService.checkLicenseStatus(), 'valid'); // Inside grace still counts as valid but near-expired

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

    test('checkClockIntegrity detects system time travel / tempering', () async {
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

      // Simulate time traveling backwards (manually modify stored last system time to future)
      final futureTime = DateTime.now().add(const Duration(hours: 2));
      await prefs.setString('last_system_time', futureTime.toIso8601String());

      // Next check fails with 'tampered'
      expect(licenseService.checkLicenseStatus(), 'tampered');
    });
  });
}
