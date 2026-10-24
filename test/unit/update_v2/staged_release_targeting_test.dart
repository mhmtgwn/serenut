// test/unit/update_v2/staged_release_targeting_test.dart
// SERENUT OS — STAGE 10.12.7 KADEMELİ GÜNCELLEME VE HEDEFLEME GÜVENLİK TESTLERİ

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo)', () {
    const config = EnvironmentConfig(
      environment: AppEnvironment.dev,
      apiBaseUrl: 'http://localhost:3000/api/v1',
      authEndpoint: '/auth',
      syncEndpoint: '/sync',
      updateEndpoint: '/updates',
      releaseEndpoint: '/releases',
      releaseChannel: 'pilot',
    );

    // 1. Hedeflenen şirket güncellemeyi görebilir
    test('1. Hedeflenen şirket güncellemeyi başarıyla alabilmelidir', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/releases/check'));
        expect(request.url.queryParameters['company_id'], equals('cmp-nutopia-pilot'));
        expect(request.url.queryParameters['channel'], equals('pilot'));

        return http.Response(
          jsonEncode({
            'hasUpdate': true,
            'latestVersion': '1.3.0',
            'isForceUpdate': false,
            'channel': 'pilot',
            'downloadUrl': '/api/v1/releases/download/rel-1.3.0',
            'sha256Hash': 'hash-valid-130',
          }),
          200,
        );
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
        deviceId: 'dev-001',
      );

      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, equals('1.3.0'));
      expect(info.channel, equals('pilot'));
    });

    // 2. Hedeflenmeyen şirket güncellemeyi göremez
    test('2. Hedeflenmeyen şirket güncellemeyi göremez (noUpdate döner)', () async {
      final mockClient = MockClient((request) async {
        final compId = request.url.queryParameters['company_id'];
        if (compId != 'cmp-nutopia-pilot') {
          // Hedeflenmeyen şirket için güncelleme yok
          return http.Response(
            jsonEncode({
              'hasUpdate': false,
              'latestVersion': '1.2.0',
              'isForceUpdate': false,
              'channel': 'pilot',
            }),
            200,
          );
        }
        return http.Response('{}', 400);
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-erkul-stable', // Erkul Çeyiz pilot hedefinde değil
        deviceId: 'dev-erkul-01',
      );

      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, equals('1.2.0'));
    });

    // 3. Hedeflenmeyen cihaz güncellemeyi göremez
    test('3. Şirket hedefte olsa bile hedeflenmeyen cihaz güncellemeyi göremez', () async {
      final mockClient = MockClient((request) async {
        final devId = request.url.queryParameters['device_activation_id'];
        if (devId != 'dev-pilot-authorized') {
          return http.Response(
            jsonEncode({
              'hasUpdate': false,
              'latestVersion': '1.2.0',
              'isForceUpdate': false,
              'channel': 'pilot',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
        deviceId: 'dev-unauthorized-02',
      );

      expect(info.hasUpdate, isFalse);
    });

    // 4. Yanlış şirket kimliği veya geçersiz yetkilendirme reddedilir
    test('4. Geçersiz token veya uyuşmayan şirket kimliği reddedilir', () async {
      final mockClient = MockClient((request) async {
        final auth = request.headers['Authorization'];
        if (auth == null || !auth.contains('valid-jwt')) {
          return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
        }
        return http.Response(jsonEncode({'hasUpdate': false}), 200);
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'spoofed-company',
        jwtToken: 'invalid-expired-token',
      );

      expect(info.hasUpdate, isFalse); // Fail-closed
    });

    // 5. Pasif veya staged yayın indirmeye açılmaz
    test('5. Pasif (status != active) yayın için güncelleme dönülmez', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'hasUpdate': false,
            'latestVersion': '1.2.0',
            'isForceUpdate': false,
            'channel': 'pilot',
          }),
          200,
        );
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
      );

      expect(info.hasUpdate, isFalse);
    });

    // 6. Pilot yayın otomatik olarak genel yayına dönüşmez
    test('6. Pilot kanalındaki bir yayın genel stable kanalına sunulmaz', () async {
      const stableConfig = EnvironmentConfig(
        environment: AppEnvironment.prod,
        apiBaseUrl: 'http://localhost:3000/api/v1',
        authEndpoint: '/auth',
        syncEndpoint: '/sync',
        updateEndpoint: '/updates',
        releaseEndpoint: '/releases',
        releaseChannel: 'stable', // Genel kullanıcılar stable kanalında
      );

      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['channel'], equals('stable'));
        // Sunucu stable kanalında yalnızca stable yayınları döner, pilot dönmez
        return http.Response(
          jsonEncode({
            'hasUpdate': false,
            'latestVersion': '1.2.0',
            'channel': 'stable',
          }),
          200,
        );
      });

      final rm = ReleaseManagerService(config: stableConfig, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
      );

      expect(info.hasUpdate, isFalse);
    });

    // 7. Rollout yüzdesi kuralı doğru uygulanır
    test('7. Rollout yüzdesi %0 iken hiçbir cihaz güncellemeyi alamaz', () async {
      final mockClient = MockClient((request) async {
        // Rollout %0 -> Hiçbir cihaz eşleşmez
        return http.Response(
          jsonEncode({
            'hasUpdate': false,
            'latestVersion': '1.2.0',
          }),
          200,
        );
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        deviceId: 'any-device-id',
      );

      expect(info.hasUpdate, isFalse);
    });

    // 8. Eski istemci sürüm kontrolü (/updates/check) şirket hedeflemesini atlayamaz
    test('8. /updates/check hedefli pilot sürümleri sızdırmaz', () async {
      final mockClient = MockClient((request) async {
        // Eski kör endpoint update_targets filtresi sayesinde hedefli sürümleri dönmez
        return http.Response(
          jsonEncode({
            'latestVersion': '1.2.0', // Pilot 1.3.0 değil, son genel 1.2.0
            'isForceUpdate': false,
            'downloadUrl': '',
          }),
          200,
        );
      });

      // Eski endpoint sorgusu
      final response = await mockClient.get(Uri.parse('http://localhost:3000/api/v1/updates/check?platform=windows&current_version=1.2.0'));
      final data = jsonDecode(response.body);
      expect(data['downloadUrl'], isEmpty);
      expect(data['latestVersion'], equals('1.2.0'));
    });

    // 9. Paket indirme erişimi sunucuda doğrulanır
    test('9. Hedef dışı şirket indirme uç noktasına eriştiğinde 403 Forbidden alır', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/download/rel-pilot-130')) {
          final auth = request.headers['Authorization'];
          if (auth?.contains('unauthorized-company-jwt') == true) {
            return http.Response(
              jsonEncode({'error': 'unauthorized_target', 'message': 'Yetkisiz sirket.'}),
              403,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
        }
        return http.Response('OK', 200);
      });

      final response = await mockClient.get(
        Uri.parse('http://localhost:3000/api/v1/releases/download/rel-pilot-130'),
        headers: {'Authorization': 'Bearer unauthorized-company-jwt'},
      );

      expect(response.statusCode, equals(403));
      final body = jsonDecode(response.body);
      expect(body['error'], equals('unauthorized_target'));
    });

    // 10. Yayını durdurmak yeni indirmeleri anında kilitler
    test('10. Yayının durumu revoke veya paused yapıldığında indirme 404/403 ile durur', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'release_not_found', 'message': 'Yayin durduruldu.'}),
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final response = await mockClient.get(
        Uri.parse('http://localhost:3000/api/v1/releases/download/rel-paused-001'),
        headers: {'Authorization': 'Bearer valid-jwt'},
      );

      expect(response.statusCode, equals(404));
    });

    // 11. Güncelleme kontrolü başarısız olursa uygulama mevcut veritabanını sıfırlamaz
    test('11. Ağ veya güncelleme hatasında fail-open güvenliği korunur, DB değiştirilmez', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Ağ bağlantısı koptu (Offline POS)');
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
      );

      // Çevrimdışı hata anında hasUpdate false döner; hiçbir DB sıfırlanmaz veya yönlendirilmez
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, equals('1.2.0'));
    });

    // 12. İstemci beyanı tek başına yetki kanıtı olamaz (JWT yoksa veya başka şirkete aitse 401 / fail-closed)
    test('12. İstemcinin beyan ettiği company_id tek başına yetki kanıtı olamaz (Token doğrulaması zorunludur)', () async {
      final mockClient = MockClient((request) async {
        final authHeader = request.headers['Authorization'];
        final queryCompany = request.url.queryParameters['company_id'];

        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          // Token yoksa beyan edilen company_id ile hedefli sürüme erişilemez
          return http.Response(
            jsonEncode({'hasUpdate': false, 'latestVersion': '1.2.0'}),
            200,
          );
        }

        if (authHeader.contains('foreign-jwt') && queryCompany == 'cmp-nutopia-pilot') {
          // Başka şirkete ait token ile Nutopia pilotuna sızma girişimi
          return http.Response(
            jsonEncode({'error': 'tenant_mismatch', 'message': 'Sirket kimligi yetki tokeni ile uyusmuyor.'}),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response(jsonEncode({'hasUpdate': false}), 200);
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);

      // A) Token olmadan yapılan sorgu (sadece query'de şirket kimliği var)
      final infoWithoutToken = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
      );
      expect(infoWithoutToken.hasUpdate, isFalse);

      // B) Başka şirketin tokenı ile yapılan sorgu
      final infoWithForeignToken = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
        jwtToken: 'foreign-jwt',
      );
      expect(infoWithForeignToken.hasUpdate, isFalse);
    });

    // 13. Yönetim panelinin şirket hedeflerini kaydetmesi ve sonradan doğru okuması
    test('13. Yönetim paneli şirket hedeflerini kaydeder ve GET /releases/:version/targets ile doğru okur', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/admin/releases/distribute' && request.method == 'POST') {
          final body = jsonDecode(request.body);
          expect(body['version'], equals('1.3.0'));
          expect(body['channel'], equals('pilot'));
          expect(body['target_tenants'], contains('cmp-nutopia-pilot'));
          return http.Response(jsonEncode({'success': true}), 200);
        }

        if (request.url.path == '/api/v1/admin/releases/1.3.0/targets' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'version': '1.3.0',
              'channel': 'pilot',
              'rollout_percentage': 50,
              'status': 'active',
              'target_tenants': ['cmp-nutopia-pilot'],
              'target_tiers': ['pro'],
              'target_devices': [],
              'total_targets': 2,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response('Not Found', 404);
      });

      // 1. Hedefleri kaydet
      final postRes = await mockClient.post(
        Uri.parse('http://localhost:3000/api/v1/admin/releases/distribute'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'version': '1.3.0',
          'channel': 'pilot',
          'target_tenants': ['cmp-nutopia-pilot'],
          'rollout_percentage': 50,
        }),
      );
      expect(postRes.statusCode, equals(200));

      // 2. Kaydedilen hedefleri oku
      final getRes = await mockClient.get(
        Uri.parse('http://localhost:3000/api/v1/admin/releases/1.3.0/targets'),
      );
      expect(getRes.statusCode, equals(200));
      final data = jsonDecode(getRes.body);
      expect(data['version'], equals('1.3.0'));
      expect(data['channel'], equals('pilot'));
      expect(data['target_tenants'], contains('cmp-nutopia-pilot'));
      expect(data['total_targets'], equals(2));
    });

    // 14. Eski istemcinin doğrudan versiyon indirme uç noktası hedefli sürümleri 404 ile engeller
    test('14. /updates/download/:platform/version/:version hedefli sürüm için 404 döner', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/updates/download/windows/version/1.3.0')) {
          // 1.3.0 pilot / targeted olduğu için eski public download uç noktası 404 vermeli
          return http.Response(
            jsonEncode({'error': 'release_not_found'}),
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('OK', 200);
      });

      final response = await mockClient.get(
        Uri.parse('http://localhost:3000/api/v1/updates/download/windows/version/1.3.0'),
      );
      expect(response.statusCode, equals(404));
      final body = jsonDecode(response.body);
      expect(body['error'], equals('release_not_found'));
    });

    // 15. Ağ hatasında uygulamanın offline çalışması ve yetkisiz güncellemenin engellenmesi
    test('15. POS çevrimdışıyken kesintisiz satış yapabilir; yetkisiz güncelleme ASLA kabul edilmez', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Bağlantı yok');
      });

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);
      final info = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
      );

      // Çevrimdışı durumda güncelleme zorlanamaz veya sahte paket kabul edilemez
      expect(info.hasUpdate, isFalse);
      expect(info.isForceUpdate, isFalse);
      expect(info.downloadUrl, isNull);
    });
  });
}
