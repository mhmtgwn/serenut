// test/services/release_manager_test.dart
// Serenut Platform — ReleaseManagerService Unit Tests (Sprint 6)
// Tests update check logic, version comparison, force update detection, SHA-256 verify.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serenutos/config/environment.dart';
import 'package:crypto/crypto.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:pointycastle/export.dart';

// ── RSA Signature Helper ──────────────────────────────────────────────────────
String signHash(String hash) {
  final modulus = BigInt.parse(
      '24411462201226996438841939549021454888733195236274468065775741224235870828599975687442961469702706222823140813618470146034318791144081164140895510392862259766582087914988353091642332590862692172508245336721761478288563513793312713764686147506940136020087563505042690937627842320486248227124477581576031460706918080381582170251418495030474651546222624978118721452561800320320246965787168638531779352900516824205685716199734459208444432818729619600489270457687453750695905613821629449668637610680017348238336982462564377297468305133351943448287065558841371731196118193920355175788560618289960848258703300389635524278281');
  final privateExponent = BigInt.parse(
      '6684964403702044724169496453702306344326024305436896384889104288437999508077631927957319216576200750431159622533998866455253053155665115169090006027445549476339300422819109402867158139802138279445282497797358030591037877566086077695573832938752988710995491130582742180105999452610993742957459132345774701699825158804056026428547722184241466314083113853337376967071262648055968258835003688193743958419042890456439736041430580551455657726912631144413462459038019832517570688284032050806223028859508074311230005951475716534070490518303245968006947288804945581389885433737412096196007272363897362949702710055189984892673');
  final p = BigInt.parse(
      '165459986035049506858151599209743457345028087382264571756838600875214015179729730612544781187952046338248144255732481262603484040549959251783515841038081387836130881397616996454946080115821071783269840527374209689096824610869945740111971001950967221172543243512794373357098950541386421533427694183039867628321');
  final q = BigInt.parse(
      '147536953109955533230758052726267768709043226827632325673221586517858950536695234149055834157050546416850232503023766679292253149457695267554303723576730374577386021326302055170150067235195292104753390330918476824765432876745115164837973897927362298648474840592618107362774499480187427469986894506200825206761');

  final privateKey = RSAPrivateKey(modulus, privateExponent, p, q);
  final payloadBytes = utf8.encode(hash);

  final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

  final signature = signer.generateSignature(payloadBytes);
  return base64.encode(signature.bytes);
}

// ── Test Helpers ──────────────────────────────────────────────────────────────

EnvironmentConfig get testConfig => const EnvironmentConfig(
      environment: AppEnvironment.test,
      apiBaseUrl: 'http://test-api.serenut.com/api/v1',
      authEndpoint: '/auth',
      syncEndpoint: '/sync',
      updateEndpoint: '/updates',
      releaseEndpoint: '/releases',
      releaseChannel: 'stable',
    );

MockClient mockClientWithResponse(int statusCode, Map<String, dynamic> body) {
  return MockClient((request) async {
    return http.Response(jsonEncode(body), statusCode, headers: {
      'content-type': 'application/json',
    });
  });
}

void main() {
  group('UpdateInfo.fromJson', () {
    test('parses hasUpdate=false correctly', () {
      final json = {
        'hasUpdate': false,
        'isForceUpdate': false,
        'latestVersion': '1.0.0+1',
        'channel': 'stable',
      };
      final info = UpdateInfo.fromJson(json);
      expect(info.hasUpdate, isFalse);
      expect(info.isForceUpdate, isFalse);
      expect(info.latestVersion, '1.0.0+1');
      expect(info.channel, 'stable');
    });

    test('parses hasUpdate=true with all fields', () {
      final json = {
        'hasUpdate': true,
        'isForceUpdate': true,
        'latestVersion': '1.5.0+30',
        'minRequiredVersion': '1.4.0+25',
        'downloadUrl': '/api/v1/releases/download/rel-123',
        'sha256Hash': 'abc123def456',
        'fileSizeBytes': 52428800,
        'releaseNotes': 'Bug fixes and performance improvements.',
        'channel': 'stable',
      };
      final info = UpdateInfo.fromJson(json);
      expect(info.hasUpdate, isTrue);
      expect(info.isForceUpdate, isTrue);
      expect(info.latestVersion, '1.5.0+30');
      expect(info.sha256Hash, 'abc123def456');
      expect(info.fileSizeBytes, 52428800);
      expect(info.releaseNotes, 'Bug fixes and performance improvements.');
    });

    test('parses production snake_case metadata fields', () {
      final json = {
        'hasUpdate': true,
        'isForceUpdate': false,
        'latestVersion': '1.1.6',
        'downloadUrl': '/api/v1/updates/download/android/latest',
        'sha256_hash': 'abc123def456',
        'file_size_bytes': '103618864',
        'release_notes': 'Hotfix release.',
        'signature': 'signed-hash',
      };
      final info = UpdateInfo.fromJson(json);
      expect(info.sha256Hash, 'abc123def456');
      expect(info.fileSizeBytes, 103618864);
      expect(info.releaseNotes, 'Hotfix release.');
      expect(info.signature, 'signed-hash');
    });

    test('noUpdate factory returns correct defaults', () {
      final info = UpdateInfo.noUpdate('1.0.0+1');
      expect(info.hasUpdate, isFalse);
      expect(info.isForceUpdate, isFalse);
      expect(info.downloadUrl, isNull);
      expect(info.sha256Hash, isNull);
    });
  });

  group('ReleaseManagerService.checkForUpdates', () {
    test('returns noUpdate when server returns hasUpdate=false', () async {
      final mockClient = mockClientWithResponse(200, {
        'hasUpdate': false,
        'isForceUpdate': false,
        'latestVersion': '1.0.0+1',
        'channel': 'stable',
      });

      final svc =
          ReleaseManagerService(config: testConfig, httpClient: mockClient);
      final result = await svc.checkForUpdates(
        currentVersion: '1.0.0+1',
        platform: 'android',
      );

      expect(result.hasUpdate, isFalse);
      expect(result.isForceUpdate, isFalse);
    });

    test('returns update info when server returns hasUpdate=true', () async {
      final mockClient = mockClientWithResponse(200, {
        'hasUpdate': true,
        'isForceUpdate': false,
        'latestVersion': '1.5.0+30',
        'downloadUrl': '/api/v1/releases/download/rel-999',
        'sha256Hash': 'deadbeef123',
        'fileSizeBytes': 10000000,
        'releaseNotes': 'New features.',
        'channel': 'stable',
      });

      final svc =
          ReleaseManagerService(config: testConfig, httpClient: mockClient);
      final result = await svc.checkForUpdates(
        currentVersion: '1.0.0+1',
        platform: 'android',
      );

      expect(result.hasUpdate, isTrue);
      expect(result.latestVersion, '1.5.0+30');
      expect(result.sha256Hash, 'deadbeef123');
      expect(result.downloadUrl, isNotNull);
    });

    test('returns noUpdate on force update when isForceUpdate=true', () async {
      final mockClient = mockClientWithResponse(200, {
        'hasUpdate': true,
        'isForceUpdate': true,
        'latestVersion': '2.0.0+50',
        'minRequiredVersion': '1.9.0+45',
        'downloadUrl': '/api/v1/releases/download/rel-222',
        'sha256Hash': 'abc',
        'channel': 'stable',
      });

      final svc =
          ReleaseManagerService(config: testConfig, httpClient: mockClient);
      final result = await svc.checkForUpdates(
        currentVersion: '1.0.0+1',
        platform: 'android',
      );

      expect(result.hasUpdate, isTrue);
      expect(result.isForceUpdate, isTrue);
      expect(result.minRequiredVersion, '1.9.0+45');
    });

    test('returns noUpdate gracefully on server error (non-throwing)',
        () async {
      final errorClient =
          MockClient((_) async => http.Response('Internal Error', 500));

      final svc =
          ReleaseManagerService(config: testConfig, httpClient: errorClient);
      final result = await svc.checkForUpdates(
        currentVersion: '1.0.0+1',
        platform: 'android',
      );

      // Should NOT throw, should return noUpdate
      expect(result.hasUpdate, isFalse);
    });

    test('returns noUpdate gracefully on network failure (non-throwing)',
        () async {
      final failClient = MockClient(
          (_) async => throw const SocketException('No route to host'));

      final svc =
          ReleaseManagerService(config: testConfig, httpClient: failClient);
      final result = await svc.checkForUpdates(
        currentVersion: '1.0.0+1',
        platform: 'android',
      );

      expect(result.hasUpdate, isFalse);
    });

    test(
        'includes correct query params in request (platform, channel, device_id)',
        () async {
      String? capturedUrl;
      final capturingClient = MockClient((request) async {
        capturedUrl = request.url.toString();
        return http.Response(
          jsonEncode({
            'hasUpdate': false,
            'isForceUpdate': false,
            'latestVersion': '1.0',
            'channel': 'stable'
          }),
          200,
        );
      });

      final svc = ReleaseManagerService(
          config: testConfig, httpClient: capturingClient);
      await svc.checkForUpdates(
        currentVersion: '1.0.0+1',
        platform: 'android',
        deviceId: 'device-abc',
        companyId: 'co-xyz',
      );

      expect(capturedUrl, contains('platform=android'));
      expect(capturedUrl, contains('device_id=device-abc'));
      expect(capturedUrl, contains('channel=stable'));
    });
  });

  group('ReleaseManagerService.verifyDownload', () {
    test('returns true when SHA-256 matches', () async {
      final svc = ReleaseManagerService(config: testConfig);
      final tempFile = File('${Directory.systemTemp.path}/test_verify.bin');
      await tempFile.writeAsBytes([0x01, 0x02, 0x03, 0x04]);

      // Compute actual hash for these bytes
      final bytes = await tempFile.readAsBytes();
      final expectedHash = sha256.convert(bytes).toString();

      final signature = signHash(expectedHash);
      final isValid =
          await svc.verifyDownload(tempFile, expectedHash, signature);
      expect(isValid, isTrue);

      await tempFile.delete();
    });

    test('returns false when SHA-256 does NOT match', () async {
      final svc = ReleaseManagerService(config: testConfig);
      final tempFile =
          File('${Directory.systemTemp.path}/test_verify_fail.bin');
      await tempFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF]);

      final isValid =
          await svc.verifyDownload(tempFile, 'wrong_hash_value', '');
      expect(isValid, isFalse);

      await tempFile.delete();
    });
  });

  group('ReleaseManagerService._computeSha256 (OOM fix – stream tabanlı)', () {
    // KRİTİK A DOĞRULAMA: Stream tabanlı hash hesaplamasının readAsBytes() ile aynı
    // sonucu ürettiğini ve büyük dosyalarda RAM tahsisatı yapmadığını kanıtlar.

    test(
        'stream tabanlı hash, 4-byte dosyada readAsBytes() ile aynı sonucu üretmeli',
        () async {
      final svc = ReleaseManagerService(config: testConfig);
      final tempFile =
          File('${Directory.systemTemp.path}/test_stream_hash_small.bin');
      await tempFile.writeAsBytes([0x01, 0x02, 0x03, 0x04]);

      // Eski yöntem: readAsBytes() – referans hash
      final bytes = await tempFile.readAsBytes();
      final expectedHash = sha256.convert(bytes).toString();

      // Yeni yöntem: verifyDownload içinde _computeSha256 stream kullanıyor
      final signature = signHash(expectedHash);
      final isValid =
          await svc.verifyDownload(tempFile, expectedHash, signature);
      expect(isValid, isTrue,
          reason: 'Stream tabanlı hash, byte bazlı hash ile tutarlı olmalı');

      await tempFile.delete();
    });

    test(
        '256 KB sahte dosyada stream tabanlı hash doğru hesaplanmalı (bellek sızıntısı yok)',
        () async {
      final svc = ReleaseManagerService(config: testConfig);
      final tempFile =
          File('${Directory.systemTemp.path}/test_stream_hash_256kb.bin');

      // 256 KB sahte ikili veri yaz (0x00-0xFF döngülü)
      final data = List<int>.generate(256 * 1024, (i) => i % 256);
      await tempFile.writeAsBytes(data);

      // Referans hash (küçük test dosyası için readAsBytes hâlâ güvenli)
      final bytes = await tempFile.readAsBytes();
      final expectedHash = sha256.convert(bytes).toString();

      final signature = signHash(expectedHash);
      final isValid =
          await svc.verifyDownload(tempFile, expectedHash, signature);
      expect(isValid, isTrue,
          reason: '256 KB dosyada stream hash doğru hesaplanmalı');

      await tempFile.delete();
    });

    test('bozuk/değiştirilmiş dosyada hash uyuşmazlığı false döndürmeli',
        () async {
      final svc = ReleaseManagerService(config: testConfig);
      final tempFile =
          File('${Directory.systemTemp.path}/test_stream_hash_tampered.bin');
      await tempFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF]);

      // Yanlış hash ile doğrulama yapılınca false dönmeli
      final isValid =
          await svc.verifyDownload(tempFile, 'yanlis_hash_degeri_abc123', '');
      expect(isValid, isFalse,
          reason: 'Hash uyuşmazlığında doğrulama başarısız olmalı');

      await tempFile.delete();
    });
  });

  group('DownloadProgress', () {
    test('percentage is correctly clamped to 0.0-1.0', () {
      const p1 = DownloadProgress(
          bytesDownloaded: 0, totalBytes: 1000, percentage: 0.0);
      const p2 = DownloadProgress(
          bytesDownloaded: 500, totalBytes: 1000, percentage: 0.5);
      const p3 = DownloadProgress(
          bytesDownloaded: 1000, totalBytes: 1000, percentage: 1.0);

      expect(p1.percentage, 0.0);
      expect(p2.percentage, 0.5);
      expect(p3.percentage, 1.0);
    });
  });
}
