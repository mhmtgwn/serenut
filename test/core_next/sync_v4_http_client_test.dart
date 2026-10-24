// test/core_next/sync_v4_http_client_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/sync_dtos.dart';
import '../../core_next/client_core/lib/domain/models/sync_mutation.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const fakeBaseUrl = 'https://fake-isolated-test-server.local/api/v4/sync';
  const fakeActivationId = 'act-test-uuid-001';
  const fakeDeviceId = 'dev-test-uuid-001';
  const fakeToken = 'fake_bearer_token_for_testing_only';

  group('Stage 8.3 — İzole Sync V4 HTTP İstemcisi ve Outbox Zorunlu Testleri', () {
    late CoreAppDatabase coreDb;

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
    });

    tearDown(() async {
      await coreDb.close();
    });

    // Helper: Test mutasyonu oluşturup sync_events tablosuna yazar
    Future<SyncMutation> insertTestMutation({
      required String eventId,
      required String entityType,
      required String entityId,
      required String operation,
      required Map<String, dynamic> payload,
      int causalSequence = 0,
      String? groupId,
      String syncState = 'PENDING',
      int attempts = 0,
    }) async {
      final mutation = SyncMutation(
        eventId: eventId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payload: payload,
        clientTimestamp: DateTime.now().millisecondsSinceEpoch,
        syncState: syncState,
        baseRevision: 0,
        attempts: attempts,
        causalSequence: causalSequence,
        groupId: groupId,
      );

      await coreDb.db.insert('sync_events', mutation.toDbRow());
      return mutation;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 1: Geçerli push isteği ve başarılı yanıt
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Geçerli push isteği ve başarılı yanıt', () async {
      final mutation = await insertTestMutation(
        eventId: 'mut-1-success',
        entityType: 'sale',
        entityId: 'sale-1',
        operation: 'UPSERT',
        payload: {
          'receipt_no': 'REC-001',
          'total_amount': 150.0,
          'paid_amount': 150.0,
          'payment_method': 'cash',
        },
      );

      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v4/sync/push');
        expect(request.headers['x-sync-protocol-version'], '6');
        expect(request.headers['x-device-activation-id'], fakeActivationId);
        expect(request.headers['x-device-id'], fakeDeviceId);
        expect(request.headers['authorization'], 'Bearer $fakeToken');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device_activation_id'], fakeActivationId);
        expect(body['device_id'], fakeDeviceId);
        final mutations = body['mutations'] as List;
        expect(mutations.length, 1);
        expect(mutations.first['mutation_id'], 'mut-1-success');

        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': 'mut-1-success', 'revision': 101}
            ],
            'conflicts': [],
            'rejected': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        tokenProvider: () async => fakeToken,
        client: mockClient,
      );

      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);
      final result = await processor.processOutbox();

      expect(result.totalProcessed, 1);
      expect(result.syncedCount, 1);
      expect(result.rejectedCount, 0);
      expect(result.transientErrorCount, 0);
      expect(result.hasErrors, false);

      // Veritabanı durumunu doğrula
      final rows = await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-1-success']);
      expect(rows.length, 1);
      expect(rows.first['sync_state'], 'SYNCED');
      expect(rows.first['last_error'], isNull);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 2: Protocol 6 uyumsuzluğu ve HTTP 426
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Protocol 6 uyumsuzluğu ve HTTP 426', () async {
      await insertTestMutation(
        eventId: 'mut-2-proto',
        entityType: 'sale',
        entityId: 'sale-2',
        operation: 'UPSERT',
        payload: {'total_amount': 50.0},
      );

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'upgrade_required',
            'required_version': 7,
          }),
          426,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        tokenProvider: () async => fakeToken,
        client: mockClient,
      );

      // Doğrudan HTTP çağrısı tip hatası fırlatmalı
      expect(
        () => httpClient.push([
          SyncMutation(
            eventId: 'direct-test',
            entityType: 'sale',
            entityId: 's',
            operation: 'UPSERT',
            payload: {},
            clientTimestamp: 0,
            syncState: 'PENDING',
          )
        ]),
        throwsA(
          isA<SyncProtocolUpgradeRequiredException>()
              .having((e) => e.requiredVersion, 'requiredVersion', 7)
              .having((e) => e.statusCode, 'statusCode', 426),
        ),
      );

      // Outbox işlemcisi HTTP 426 aldığında kayıtları silmemeli, TRANSIENT_ERROR yapmalı
      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);
      final result = await processor.processOutbox();

      expect(result.hasErrors, true);
      expect(result.transientErrorCount, 1);
      expect(result.syncedCount, 0);

      final row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-2-proto'])).first;
      expect(row['sync_state'], 'TRANSIENT_ERROR');
      expect(row['attempts'], 1);
      expect(row['last_error'], contains('upgrade_required'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 3: Yetkisiz istek ve HTTP 401/403
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Yetkisiz istek ve HTTP 401/403', () async {
      // 3A: HTTP 401 Unauthorized
      final mock401 = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'invalid_or_expired_token'}), 401);
      });
      final client401 = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mock401,
      );
      expect(() => client401.pull(), throwsA(isA<SyncUnauthorizedException>()));

      // 3B: HTTP 403 Forbidden
      final mock403 = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'device_revoked'}), 403);
      });
      final client403 = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mock403,
      );
      expect(() => client403.bootstrap(), throwsA(isA<SyncForbiddenException>()));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 4: Zaman aşımı ve bağlantının kesilmesi
    // ─────────────────────────────────────────────────────────────────────────
    test('4. Zaman aşımı ve bağlantının kesilmesi', () async {
      await insertTestMutation(
        eventId: 'mut-4-timeout',
        entityType: 'sale',
        entityId: 'sale-4',
        operation: 'UPSERT',
        payload: {'total_amount': 100.0},
      );

      // 4A: Zaman aşımı (Timeout) simülasyonu
      final timeoutClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 50));
        throw TimeoutException('Request timeout');
      });
      final httpTimeoutClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        timeout: const Duration(milliseconds: 10),
        client: timeoutClient,
      );

      final procTimeout = SyncV4OutboxProcessor(db: coreDb, httpClient: httpTimeoutClient);
      final resTimeout = await procTimeout.processOutbox();

      expect(resTimeout.transientErrorCount, 1);
      var row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-4-timeout'])).first;
      expect(row['sync_state'], 'TRANSIENT_ERROR');
      expect(row['attempts'], 1);

      // 4B: Ağ bağlantısının kopması (ClientException / SocketException)
      final dropClient = MockClient((request) async {
        throw http.ClientException('Connection dropped by peer');
      });
      final httpDropClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: dropClient,
      );

      final procDrop = SyncV4OutboxProcessor(db: coreDb, httpClient: httpDropClient);
      final resDrop = await procDrop.processOutbox();

      expect(resDrop.transientErrorCount, 1);
      row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-4-timeout'])).first;
      expect(row['attempts'], 2); // Deneme sayısı 2 oldu
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 5: Bozuk veya beklenmeyen JSON yanıtı
    // ─────────────────────────────────────────────────────────────────────────
    test('5. Bozuk veya beklenmeyen JSON yanıtı', () async {
      // 5A: HTML dönmesi (502 proxy sayfası gibi)
      final htmlMock = MockClient((request) async {
        return http.Response('<html><head><title>502 Bad Gateway</title></head></html>', 200);
      });
      final clientHtml = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: htmlMock,
      );
      expect(() => clientHtml.pull(), throwsA(isA<SyncFormatException>()));

      // 5B: JSON Array dönmesi (Beklenen Map/Object)
      final arrayMock = MockClient((request) async {
        return http.Response(jsonEncode([1, 2, 3]), 200);
      });
      final clientArray = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: arrayMock,
      );
      expect(() => clientArray.bootstrap(), throwsA(isA<SyncFormatException>()));

      // 5C: Kırık/Eksik JSON metni
      final brokenMock = MockClient((request) async {
        return http.Response('{"results": [{"mutation_id": ', 200);
      });
      final clientBroken = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: brokenMock,
      );
      expect(
        () => clientBroken.push([
          SyncMutation(
            eventId: 'ev',
            entityType: 'sale',
            entityId: 's',
            operation: 'UPSERT',
            payload: {},
            clientTimestamp: 0,
            syncState: 'PENDING',
          )
        ]),
        throwsA(isA<SyncFormatException>()),
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 6: Aynı mutasyonun aynı kimlikle yeniden gönderilmesi
    // ─────────────────────────────────────────────────────────────────────────
    test('6. Aynı mutasyonun aynı kimlikle yeniden gönderilmesi', () async {
      final mut = await insertTestMutation(
        eventId: 'mut-6-idemp',
        entityType: 'sale',
        entityId: 'sale-6',
        operation: 'UPSERT',
        payload: {'total_amount': 200.0},
      );

      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final mutations = body['mutations'] as List;
        expect(mutations.first['mutation_id'], 'mut-6-idemp');

        // Sunucu idempotency sözleşmesi: Daha önce işlenmişse aynı revizyonla ack döner
        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': 'mut-6-idemp', 'revision': 55}
            ],
            'conflicts': [],
            'rejected': [],
          }),
          200,
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      // İlk gönderim
      final res1 = await httpClient.push([mut]);
      expect(res1.results.first.mutationId, 'mut-6-idemp');
      expect(res1.results.first.revision, 55);

      // İkinci gönderim (Aynı mutasyon, aynı ID)
      final res2 = await httpClient.push([mut]);
      expect(res2.results.first.mutationId, 'mut-6-idemp');
      expect(res2.results.first.revision, 55);
      expect(callCount, 2);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 7: Aynı batch içinde kısmi başarı ve ret
    // ─────────────────────────────────────────────────────────────────────────
    test('7. Aynı batch içinde kısmi başarı ve ret', () async {
      await insertTestMutation(
        eventId: 'mut-7-ok',
        entityType: 'sale',
        entityId: 'sale-7-ok',
        operation: 'UPSERT',
        payload: {'total_amount': 100.0},
        causalSequence: 1,
      );
      await insertTestMutation(
        eventId: 'mut-7-fail',
        entityType: 'sale',
        entityId: 'sale-7-fail',
        operation: 'UPSERT',
        payload: {'total_amount': 200.0},
        causalSequence: 2,
      );

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': 'mut-7-ok', 'revision': 12}
            ],
            'conflicts': [],
            'rejected': [
              {'mutation_id': 'mut-7-fail', 'error': 'invalid_sale_item'}
            ],
          }),
          200,
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);
      final result = await processor.processOutbox();

      expect(result.totalProcessed, 2);
      expect(result.syncedCount, 1);
      expect(result.rejectedCount, 1);
      expect(result.transientErrorCount, 0);

      // Veritabanı teyidi:
      final rowOk = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-7-ok'])).first;
      expect(rowOk['sync_state'], 'SYNCED');
      expect(rowOk['last_error'], isNull);

      final rowFail = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-7-fail'])).first;
      expect(rowFail['sync_state'], 'REJECTED'); // nonRetryableServerErrors listesinde
      expect(rowFail['last_error'], 'invalid_sale_item');
      expect(rowFail['attempts'], 1);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 8: Satışın kabul edilip finansal işlemin reddedilmesi
    // ─────────────────────────────────────────────────────────────────────────
    test('8. Satışın kabul edilip finansal işlemin reddedilmesi', () async {
      const saleEventId = 'ev-sale-8';
      const finEventId = 'ev-fin-8';
      const groupId = 'group-sale-8';

      await insertTestMutation(
        eventId: saleEventId,
        entityType: 'sale',
        entityId: 'sale-8',
        operation: 'UPSERT',
        payload: {'total_amount': 300.0, 'paid_amount': 100.0, 'payment_method': 'mixed'},
        groupId: groupId,
        causalSequence: 1,
      );

      await insertTestMutation(
        eventId: finEventId,
        entityType: 'financial_transaction',
        entityId: 'fin-8',
        operation: 'UPSERT',
        payload: {'type': 'sale', 'customer_id': 'cust-missing', 'amount': 300.0},
        groupId: groupId,
        causalSequence: 2,
      );

      // Sunucu Savepoint simülasyonu: Satış commit edildi, cari mutasyonu reddedildi
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': saleEventId, 'revision': 80}
            ],
            'conflicts': [],
            'rejected': [
              {'mutation_id': finEventId, 'error': 'invalid_customer'}
            ],
          }),
          200,
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);
      final result = await processor.processOutbox();

      expect(result.syncedCount, 1);
      expect(result.rejectedCount, 1);

      // Kritik Güvenlik Kontrolü:
      // Satış kesin olarak SYNCED olmalı
      final saleRow = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: [saleEventId])).first;
      expect(saleRow['sync_state'], 'SYNCED');

      // Finansal işlem REJECTED olmalı (silinmemeli, hata korunmalı)
      final finRow = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: [finEventId])).first;
      expect(finRow['sync_state'], 'REJECTED');
      expect(finRow['last_error'], 'invalid_customer');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 9: Başarılı sunucu işlemi sonrası yanıt kaybı
    // ─────────────────────────────────────────────────────────────────────────
    test('9. Başarılı sunucu işlemi sonrası yanıt kaybı', () async {
      final mut = await insertTestMutation(
        eventId: 'mut-9-drop',
        entityType: 'sale',
        entityId: 'sale-9',
        operation: 'UPSERT',
        payload: {'total_amount': 500.0},
      );

      int pushAttempts = 0;
      final mockClient = MockClient((request) async {
        pushAttempts++;
        if (pushAttempts == 1) {
          // Sunucu işlemi gerçekleştirdi ama tam yanıt dönerken bağlantı koptu
          throw http.ClientException('Connection terminated unexpectedly by network');
        } else {
          // İkinci denemede istemci AYNI mutation_id ile tekrar gönderdi; sunucu idempotent olarak onayladı
          return http.Response(
            jsonEncode({
              'results': [
                {'mutation_id': 'mut-9-drop', 'revision': 99}
              ],
              'conflicts': [],
              'rejected': [],
            }),
            200,
          );
        }
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      // 1. Tur: Yanıt kaybı nedeniyle geçici hata oluştu
      final res1 = await processor.processOutbox();
      expect(res1.transientErrorCount, 1);
      var row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-9-drop'])).first;
      expect(row['sync_state'], 'TRANSIENT_ERROR');
      expect(row['attempts'], 1);

      // 2. Tur: Yeniden deneme (Aynı mutation_id ile)
      final res2 = await processor.processOutbox();
      expect(res2.syncedCount, 1);
      row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-9-drop'])).first;
      expect(row['sync_state'], 'SYNCED');
      expect(pushAttempts, 2);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 10: Kalıcı 4xx hatası ve geçici 5xx hatası
    // ─────────────────────────────────────────────────────────────────────────
    test('10. Kalıcı 4xx hatası ve geçici 5xx hatası', () async {
      // 10A: Kalıcı 4xx (sale_total_mismatch) -> REJECTED
      await insertTestMutation(
        eventId: 'mut-10-perm',
        entityType: 'sale',
        entityId: 'sale-10-perm',
        operation: 'UPSERT',
        payload: {'total_amount': 100.0},
      );

      final mockPerm = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [],
            'rejected': [
              {'mutation_id': 'mut-10-perm', 'error': 'sale_total_mismatch'}
            ],
          }),
          200,
        );
      });
      final clientPerm = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockPerm,
      );
      final procPerm = SyncV4OutboxProcessor(db: coreDb, httpClient: clientPerm);
      final resPerm = await procPerm.processOutbox();
      expect(resPerm.rejectedCount, 1);

      final rowPerm = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-10-perm'])).first;
      expect(rowPerm['sync_state'], 'REJECTED'); // Kalıcı olarak kuyruktan düşer

      // 10B: Geçici 5xx (HTTP 503 Service Unavailable) -> TRANSIENT_ERROR
      await insertTestMutation(
        eventId: 'mut-10-trans',
        entityType: 'sale',
        entityId: 'sale-10-trans',
        operation: 'UPSERT',
        payload: {'total_amount': 100.0},
      );

      final mockTrans = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'server_under_maintenance'}), 503);
      });
      final clientTrans = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockTrans,
      );
      final procTrans = SyncV4OutboxProcessor(db: coreDb, httpClient: clientTrans);
      final resTrans = await procTrans.processOutbox();
      expect(resTrans.transientErrorCount, 1);

      final rowTrans = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-10-trans'])).first;
      expect(rowTrans['sync_state'], 'TRANSIENT_ERROR'); // Tekrar denenebilir durumda kalır
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 11: Pull sayfalaması ve cursor devamlılığı
    // ─────────────────────────────────────────────────────────────────────────
    test('11. Pull sayfalaması ve cursor devamlılığı', () async {
      int pullCallCount = 0;
      final mockClient = MockClient((request) async {
        pullCallCount++;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v4/sync/pull');

        final cursor = request.url.queryParameters['cursor'];
        final limit = request.url.queryParameters['limit'];
        expect(limit, '100');

        if (cursor == '0') {
          return http.Response(
            jsonEncode({
              'changes': [
                {
                  'revision': 1,
                  'mutation_id': 'm-pull-1',
                  'device_id': 'dev-other',
                  'entity_type': 'product',
                  'entity_id': 'p-1',
                  'operation': 'UPSERT',
                  'payload': {'name': 'Peynir', 'price': 250.0},
                  'created_at': '2026-10-13T10:00:00Z',
                }
              ],
              'next_cursor': 100,
            }),
            200,
          );
        } else if (cursor == '100') {
          return http.Response(
            jsonEncode({
              'changes': [
                {
                  'revision': 2,
                  'mutation_id': 'm-pull-2',
                  'device_id': 'dev-other',
                  'entity_type': 'product',
                  'entity_id': 'p-2',
                  'operation': 'UPSERT',
                  'payload': {'name': 'Zeytin', 'price': 180.0},
                  'created_at': '2026-10-13T10:05:00Z',
                }
              ],
              'next_cursor': 250,
            }),
            200,
          );
        }

        return http.Response(jsonEncode({'changes': [], 'next_cursor': cursor}), 200);
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      // Sayfa 1: cursor 0 -> 100
      final page1 = await httpClient.pull(cursor: 0, limit: 100);
      expect(page1.changes.length, 1);
      expect(page1.changes.first.entityId, 'p-1');
      expect(page1.nextCursor, 100);

      // Sayfa 2: cursor 100 -> 250
      final page2 = await httpClient.pull(cursor: page1.nextCursor, limit: 100);
      expect(page2.changes.length, 1);
      expect(page2.changes.first.entityId, 'p-2');
      expect(page2.nextCursor, 250);
      expect(pullCallCount, 2);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 12: Bootstrap hatası ve geçerli bootstrap yanıtı
    // ─────────────────────────────────────────────────────────────────────────
    test('12. Bootstrap hatası ve geçerli bootstrap yanıtı', () async {
      // 12A: Geçerli bootstrap
      final mockOk = MockClient((request) async {
        expect(request.url.path, '/api/v4/sync/bootstrap');
        expect(request.url.queryParameters['device_activation_id'], fakeActivationId);
        expect(request.url.queryParameters['device_id'], fakeDeviceId);
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 1,
                'mutation_id': 'boot-1',
                'device_id': 'srv',
                'entity_type': 'product',
                'entity_id': 'p-boot',
                'operation': 'UPSERT',
                'payload': {'name': 'Tereyagi'},
                'created_at': '2026-10-13T09:00:00Z',
              }
            ],
            'next_cursor': 1000,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final clientOk = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockOk,
      );
      final bootRes = await clientOk.bootstrap();
      expect(bootRes.changes.length, 1);
      expect(bootRes.changes.first.entityId, 'p-boot');
      expect(bootRes.nextCursor, 1000);

      // 12B: Bootstrap sunucu hatası (HTTP 500)
      final mockErr = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'database_backup_in_progress'}), 500);
      });
      final clientErr = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockErr,
      );
      expect(() => clientErr.bootstrap(), throwsA(isA<SyncServerException>()));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 13: Uygulama yeniden başladığında bekleyen outbox kayıtlarının korunması
    // ─────────────────────────────────────────────────────────────────────────
    test('13. Uygulama yeniden başladığında bekleyen outbox kayıtlarının korunması', () async {
      final tempDir = Directory.systemTemp.createTempSync('serenut_sync_test_');
      final testDbFile = '${tempDir.path}\\restart_test.db';

      try {
        // 1. Veritabanını aç ve bekleyen kayıtları ekle
        var diskDb = await CoreAppDatabase.open(inMemoryOrCustomPath: testDbFile);
        await diskDb.db.insert('sync_events', {
          'event_id': 'mut-restart-pending',
          'entity_type': 'sale',
          'entity_id': 'sale-rst-1',
          'operation': 'UPSERT',
          'payload_json': jsonEncode({'total_amount': 75.0}),
          'client_timestamp': 1000,
          'sync_state': 'PENDING',
          'base_revision': 0,
          'attempts': 0,
          'causal_sequence': 1,
        });
        await diskDb.db.insert('sync_events', {
          'event_id': 'mut-restart-transient',
          'entity_type': 'sale',
          'entity_id': 'sale-rst-2',
          'operation': 'UPSERT',
          'payload_json': jsonEncode({'total_amount': 85.0}),
          'client_timestamp': 1001,
          'sync_state': 'TRANSIENT_ERROR',
          'base_revision': 0,
          'attempts': 1,
          'causal_sequence': 2,
        });

        // 2. Uygulama kapandı (Veritabanı kapatıldı)
        await diskDb.close();

        // 3. Uygulama yeniden başladı (Veritabanı tekrar açıldı)
        diskDb = await CoreAppDatabase.open(inMemoryOrCustomPath: testDbFile);

        // 4. Kuyruğun aynen korunduğunu doğrula
        final pendingRows = await diskDb.query(
          'sync_events',
          where: "sync_state IN ('PENDING', 'TRANSIENT_ERROR')",
          orderBy: 'causal_sequence ASC',
        );
        expect(pendingRows.length, 2);
        expect(pendingRows[0]['event_id'], 'mut-restart-pending');
        expect(pendingRows[0]['sync_state'], 'PENDING');
        expect(pendingRows[1]['event_id'], 'mut-restart-transient');
        expect(pendingRows[1]['sync_state'], 'TRANSIENT_ERROR');

        // 5. İşlemcinin yeniden başlayan veritabanını başarıyla tüketebildiğini doğrula
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'results': [
                {'mutation_id': 'mut-restart-pending', 'revision': 1},
                {'mutation_id': 'mut-restart-transient', 'revision': 2},
              ],
              'conflicts': [],
              'rejected': [],
            }),
            200,
          );
        });

        final httpClient = SyncV4HttpClient(
          baseUrl: fakeBaseUrl,
          deviceActivationId: fakeActivationId,
          deviceId: fakeDeviceId,
          client: mockClient,
        );
        final processor = SyncV4OutboxProcessor(db: diskDb, httpClient: httpClient);
        final result = await processor.processOutbox();

        expect(result.syncedCount, 2);
        final finalRows = await diskDb.query('sync_events', where: "sync_state = 'SYNCED'");
        expect(finalRows.length, 2);

        await diskDb.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 14: Başarılı mutasyonun tekrar gönderilmemesi
    // ─────────────────────────────────────────────────────────────────────────
    test('14. Başarılı mutasyonun tekrar gönderilmemesi', () async {
      await insertTestMutation(
        eventId: 'mut-14-once',
        entityType: 'sale',
        entityId: 'sale-14',
        operation: 'UPSERT',
        payload: {'total_amount': 120.0},
      );

      int pushCallCount = 0;
      final mockClient = MockClient((request) async {
        pushCallCount++;
        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': 'mut-14-once', 'revision': 14}
            ],
            'conflicts': [],
            'rejected': [],
          }),
          200,
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      // 1. Çalıştırma: Mutasyon gönderilir ve SYNCED yapılır
      final res1 = await processor.processOutbox();
      expect(res1.syncedCount, 1);
      expect(pushCallCount, 1);

      // 2. Çalıştırma: Mutasyon artık SYNCED olduğu için sorgulanmaz ve HTTP push ÇAĞRILMAZ
      final res2 = await processor.processOutbox();
      expect(res2.totalProcessed, 0);
      expect(pushCallCount, 1); // push sayısı hâlâ 1 olmalıdır!
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 15: Bir finansal mutasyonun başarısız olmasının ikinci kez stok düşümüne yol açmaması
    // ─────────────────────────────────────────────────────────────────────────
    test('15. Bir finansal mutasyonun başarısız olmasının ikinci kez stok düşümüne yol açmaması', () async {
      // 1. Checkout ile gerçek bir satış ve cari mutasyonu üret
      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);
      final hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();

      // Test ürünü ve müşterisi oluştur
      await coreDb.db.insert('products', {
        'id': 'p-stok-test',
        'barcode': '8699999',
        'name': 'Kaşar Peyniri',
        'price_cents': 20000, // 200 TL
        'stock_quantity': 50,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': 'c-stok-cust',
        'name': 'Ahmet Bey',
        'phone': '05550001122',
        'balance_cents': 0,
        'credit_limit_cents': 500000,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(
        ProductEntity(
          id: 'p-stok-test',
          barcode: '8699999',
          name: 'Kaşar Peyniri',
          price: const MoneyCents(20000),
          stockQuantity: 50,
          updatedAt: DateTime.now(),
        ),
        quantity: 1,
      );
      final cust = await ledgerRepo.getCustomer('c-stok-cust');
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(20000)),
      ]);

      final completedSale = await notifier.completeCheckout(
        receiptNo: 'REC-STOCK-01',
        storeTitle: 'Serenut Gurme',
        actor: ActorContext.testManager,
      );

      // Yerel stok 50 -> 49'a düştü
      final localProd = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-stok-test'])).first;
      expect(localProd['stock_quantity'], 49);

      // Outbox kayıtlarını kontrol et
      final initialOutbox = await coreDb.db.query('sync_events', orderBy: 'causal_sequence ASC');
      expect(initialOutbox.length, 2);
      final saleMutationId = initialOutbox[0]['event_id'] as String;
      final finMutationId = initialOutbox[1]['event_id'] as String;
      expect(initialOutbox[0]['entity_type'], 'sale');
      expect(initialOutbox[1]['entity_type'], 'financial_transaction');

      // 2. Tur 1: Satış onaylanır (stok sunucuda düşer), cari işlem geçici hata (503) alır
      int pushRound = 0;
      List<dynamic>? round2MutationsSent;

      final mockClient = MockClient((request) async {
        pushRound++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final sentMutations = body['mutations'] as List;

        if (pushRound == 1) {
          // İlk turda 2 mutasyon da gönderildi
          expect(sentMutations.length, 2);
          // Sunucu satışı onayladı, cari mutasyonunu savepoint hatasıyla reddetti
          return http.Response(
            jsonEncode({
              'results': [
                {'mutation_id': saleMutationId, 'revision': 100}
              ],
              'conflicts': [],
              'rejected': [
                {'mutation_id': finMutationId, 'error': 'temporary_ledger_lock'} // Geçici hata
              ],
            }),
            200,
          );
        } else {
          // İkinci turda sunucuya ne gönderildiğini kaydet
          round2MutationsSent = sentMutations;
          return http.Response(
            jsonEncode({
              'results': [
                {'mutation_id': finMutationId, 'revision': 101}
              ],
              'conflicts': [],
              'rejected': [],
            }),
            200,
          );
        }
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      // Tur 1'i çalıştır
      final res1 = await processor.processOutbox();
      expect(res1.syncedCount, 1);
      expect(res1.transientErrorCount, 1);

      // Tur 1 sonrası DB durumu:
      final saleRow = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: [saleMutationId])).first;
      expect(saleRow['sync_state'], 'SYNCED');

      final finRow = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: [finMutationId])).first;
      expect(finRow['sync_state'], 'TRANSIENT_ERROR');

      // Tur 2'yi çalıştır (Yeniden deneme)
      final res2 = await processor.processOutbox();
      expect(res2.syncedCount, 1);
      expect(pushRound, 2);

      // KRİTİK GÜVENLİK İNCELEMESİ:
      // İkinci turda sunucuya push edilen mutasyon listesinde satış ASLA yer almamalıdır!
      expect(round2MutationsSent, isNotNull);
      expect(round2MutationsSent!.length, 1, reason: 'İkinci turda yalnızca finansal mutasyon gönderilmelidir');
      expect(round2MutationsSent!.first['mutation_id'], finMutationId);
      expect(round2MutationsSent!.first['entity_type'], 'financial_transaction');

      // Yerel stok hâlâ 49 (ikinci kez stok düşülmedi)
      final finalProd = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-stok-test'])).first;
      expect(finalProd['stock_quantity'], 49);

      await hardwareWorker.dispose();
    });
  });
}
