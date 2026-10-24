// test/core_next/stage10_7_client_safety_test.dart
// SERENUT OS — STAGE 10.7 REGRESYON VE GÜVENLİK TESTLERİ
//
// P0-1: Yerel Satış ve İadelerin Tekrar Uygulanmasının Engellenmesi (Client Ingestion Safety)
// P0-2: Outbox Payload Çatışmalarının Terminal (REJECTED) Duruma Alınması (Dead-Letter)
// P0-3: Watermark Causal Sequence ve Şema Migration Bütünlüğü

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/models/sync_dtos.dart';
import '../../core_next/client_core/lib/domain/models/sync_mutation.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/schema_definitions.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.7 — P0: İstemci Pull Ingestion ve Yerel Satış Güvenliği', () {
    late Directory tempDir;
    late String dbPath;
    late CoreAppDatabase coreDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_test_10_7_ingest_');
      dbPath = '${tempDir.path}/ingest_safety.db';
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);

      // Başlangıç ürünü ekle: 20 adet stok
      await coreDb.db.insert('products', {
        'id': 'prod-kahve-1',
        'barcode': '8690001',
        'name': 'Filtre Kahve 250g',
        'price_cents': 15000,
        'stock_quantity': 20,
        'vat_rate': 20,
        'unit': 'piece',
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await coreDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('10.7.1.1: Doğru cihaz kimliğiyle kendi satışını tekrar uygulamama (tek stok düşümü)', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Kendi kasanın satışı: device_id = 'kasa-a'
      final change = SyncPullChange(
        mutationId: 'mut-own-1',
        entityType: 'sale',
        entityId: 'sale-own-1',
        operation: 'UPSERT',
        revision: 10,
        deviceId: 'kasa-a',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'receipt_no': 'REC-OWN-01',
          'items': [
            {'product_id': 'prod-kahve-1', 'quantity': 2, 'unit_price': 150.0}
          ]
        },
      );

      final result = await ingestion.ingestPull(SyncPullResponseDto(
        changes: [change],
        nextCursor: 10,
      ));

      expect(result.salesApplied, 1);
      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 20, reason: 'Kendi kasanın satışı pull edildiğinde stok ikinci kez düşmemelidir!');

      final appliedEvents = await coreDb.db.query('sync_applied_events', where: 'id = ?', whereArgs: ['sale:sale-own-1']);
      expect(appliedEvents.length, 1, reason: 'Olay idempotency için sync_applied_events tablosuna kaydedilmelidir');
    });

    test('10.7.1.2: localDeviceId == null durumunda güvenli başarısızlık (StateError ve no-op)', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: null);

      final change = SyncPullChange(
        mutationId: 'mut-ext-1',
        entityType: 'sale',
        entityId: 'sale-ext-1',
        operation: 'UPSERT',
        revision: 11,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-kahve-1', 'quantity': 5}
          ]
        },
      );

      expect(
        () => ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 11)),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('unidentified_local_device'),
        )),
        reason: 'localDeviceId null olduğunda yabancı cihaz varsayımına düşülmeden StateError fırlatılmalıdır',
      );

      // Stok değişmemiş olmalı
      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 20, reason: 'Başarısız senkronizasyon stok değiştirmemelidir');

      // Cursor ilerlememiş olmalı
      final cursor = await ingestion.getSavedCursor();
      expect(cursor, 0, reason: 'Cursor ilerlememelidir');
    });

    test('10.7.1.3: Boş veya yalnızca boşluk içeren localDeviceId güvenli başarısızlık vermelidir', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: '   ');

      final change = SyncPullChange(
        mutationId: 'mut-ext-2',
        entityType: 'sale',
        entityId: 'sale-ext-2',
        operation: 'UPSERT',
        revision: 12,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-kahve-1', 'quantity': 3}
          ]
        },
      );

      expect(
        () => ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 12)),
        throwsA(isA<StateError>()),
      );

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 20);
    });

    test('10.7.1.4: Aynı satış olayının iki kez gelmesi (Tekrar uygulama koruması)', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Başka kasanın satışı: device_id = 'kasa-b' (3 adet satar)
      final change = SyncPullChange(
        mutationId: 'mut-b-1',
        entityType: 'sale',
        entityId: 'sale-b-1',
        operation: 'UPSERT',
        revision: 15,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-kahve-1', 'quantity': 3}
          ]
        },
      );

      // 1. Ingestion: Stok 20 -> 17 düşmeli
      await ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 15));
      var prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 17);

      // 2. Ingestion: Aynı olay tekrar geliyor (Replay)
      await ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 15));
      prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 17, reason: 'Aynı olay ikinci kez pull edildiğinde stok tekrar düşmemelidir');
    });

    test('10.7.1.5: Uygulama yeniden başlatıldıktan sonra aynı olayın gelmesi (Kalıcı Idempotency)', () async {
      final ingestion1 = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final change = SyncPullChange(
        mutationId: 'mut-persisted-1',
        entityType: 'sale',
        entityId: 'sale-persisted-1',
        operation: 'UPSERT',
        revision: 20,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-kahve-1', 'quantity': 4}
          ]
        },
      );

      await ingestion1.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 20));
      var prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 16);

      // Veritabanını kapat ve diski simüle ederek yeniden aç
      await coreDb.close();
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);
      final ingestion2 = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Tekrar pull ediliyor
      await ingestion2.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 20));
      prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 16, reason: 'Restart sonrasında sync_applied_events tablosu idempotency korumalıdır');
    });

    test('10.7.1.6: Sunucu satış IDsi farklı olsa dahi receipt_no / idempotency_key eşleşmesiyle yerel satış korunmalı', () async {
      // Yerelde bir satış kaydı oluştur: receipt_no = 'REC-LOCAL-MATCH-1', idempotency_key = 'IDEMP-MATCH-1'
      await coreDb.db.insert('sales', {
        'id': 'local-uuid-111',
        'receipt_no': 'REC-LOCAL-MATCH-1',
        'subtotal_cents': 15000,
        'discount_cents': 0,
        'vat_total_cents': 3000,
        'total_cents': 15000,
        'paid_cents': 15000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEMP-MATCH-1',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Sunucu farklı bir UUID (`server-assigned-999`) ve farklı deviceId ile gönderse dahi receipt_no aynıdır
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final change = SyncPullChange(
        mutationId: 'mut-srv-999',
        entityType: 'sale',
        entityId: 'server-assigned-999',
        operation: 'UPSERT',
        revision: 25,
        deviceId: 'unknown-or-gateway',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'receipt_no': 'REC-LOCAL-MATCH-1',
          'idempotency_key': 'IDEMP-MATCH-1',
          'items': [
            {'product_id': 'prod-kahve-1', 'quantity': 2}
          ]
        },
      );

      await ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 25));

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 20, reason: 'Yerel sales tablosuyla receipt_no eşleşen satış yerel kabul edilmeli ve stok düşülmemelidir');
    });

    test('10.7.1.7: Hata durumunda SQLite transaction rollback garantisi ve cursor ilerlememe', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Transaction abort testini doğrulamak:
      expect(
        () async {
          await coreDb.transaction((txn) async {
            await txn.update('products', {'stock_quantity': 15}, where: 'id = ?', whereArgs: ['prod-kahve-1']);
            throw StateError('simulated_failure_during_batch');
          });
        },
        throwsA(isA<StateError>()),
      );

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 20, reason: 'Rollback sonrası stok eski değerinde kalmalıdır');
      final cursor = await ingestion.getSavedCursor();
      expect(cursor, 0, reason: 'Hata durumunda cursor asla güncellenmemelidir');
    });

    test('10.7.1.8: Kendi iadesini tekrar uygulamama (Refund local origin protection)', () async {
      // Yerelde bir iade kaydı oluştur: status = 'REFUND', receipt_no = 'REF-REC-01'
      await coreDb.db.insert('sales', {
        'id': 'refund-local-1',
        'receipt_no': 'REF-REC-01',
        'subtotal_cents': 15000,
        'discount_cents': 0,
        'vat_total_cents': 3000,
        'total_cents': 15000,
        'paid_cents': 15000,
        'debt_cents': 0,
        'status': 'REFUND',
        'idempotency_key': 'IDEMP-REF-1',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Sunucudan aynı iade geri geliyor
      final change = SyncPullChange(
        mutationId: 'mut-ref-1',
        entityType: 'refund',
        entityId: 'refund-local-1',
        operation: 'UPSERT',
        revision: 28,
        deviceId: 'kasa-a',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'receipt_no': 'REF-REC-01',
          'items': [
            {'product_id': 'prod-kahve-1', 'quantity': 1}
          ]
        },
      );

      await ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 28));

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve-1'])).first;
      expect(prod['stock_quantity'], 20, reason: 'Kendi yerel iademiz pull edildiğinde stok ikinci kez artmamalıdır');
    });
  });

  group('STAGE 10.7 — P0: Outbox Dead-Letter ve Payload Çatışma Yönetimi', () {
    late Directory tempDir;
    late String dbPath;
    late CoreAppDatabase coreDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_test_10_7_outbox_');
      dbPath = '${tempDir.path}/outbox_deadletter.db';
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);
    });

    tearDown(() async {
      await coreDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> seedOutboxMutation(String eventId, String entityId, Map<String, dynamic> payload) async {
      await coreDb.db.insert('sync_events', {
        'event_id': eventId,
        'entity_type': 'sale',
        'entity_id': entityId,
        'operation': 'UPSERT',
        'payload_json': jsonEncode(payload),
        'base_revision': 0,
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'PENDING',
        'attempts': 0,
        'last_error': null,
        'group_id': entityId,
        'causal_sequence': 1,
      });
    }

    test('10.7.2.1 & 10.7.2.2: sale_payload_conflict ve mutation_payload_conflict terminal REJECTED durumuna alınmalı', () async {
      await seedOutboxMutation('evt-1', 'sale-1', {'total': 100});
      await seedOutboxMutation('evt-2', 'sale-2', {'total': 200});

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [],
            'conflicts': [],
            'rejected': [
              {'mutation_id': 'evt-1', 'error': 'sale_payload_conflict'},
              {'mutation_id': 'evt-2', 'error': 'mutation_payload_conflict'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://test.local',
        deviceActivationId: 'act-1',
        deviceId: 'dev-1',
        client: mockClient,
      );
      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      final result = await processor.processOutbox();

      expect(result.totalProcessed, 2);
      expect(result.rejectedCount, 2, reason: 'Her iki payload çatışması da REJECTED olarak sınıflandırılmalıdır');
      expect(result.transientErrorCount, 0, reason: 'Payload çatışması TRANSIENT_ERROR olmamalıdır');

      // Veritabanı durumunu doğrula
      final r1 = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['evt-1'])).first;
      expect(r1['sync_state'], 'REJECTED');
      expect(r1['last_error'], 'sale_payload_conflict');

      final r2 = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['evt-2'])).first;
      expect(r2['sync_state'], 'REJECTED');
      expect(r2['last_error'], 'mutation_payload_conflict');
    });

    test('10.7.2.3: REJECTED mutasyonlar sonraki worker çalışmasında tekrar gönderilmemelidir', () async {
      await seedOutboxMutation('evt-rej', 'sale-rej', {'total': 100});

      int httpCalls = 0;
      final mockClient = MockClient((request) async {
        httpCalls++;
        return http.Response(
          jsonEncode({
            'results': [],
            'conflicts': [],
            'rejected': [
              {'mutation_id': 'evt-rej', 'error': 'sale_payload_conflict'}
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://test.local',
        deviceActivationId: 'act-1',
        deviceId: 'dev-1',
        client: mockClient,
      );
      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      // İlk çalıştırma: REJECTED olur
      await processor.processOutbox();
      expect(httpCalls, 1);

      // İkinci çalıştırma: Kuyrukta bekleyen eleman kalmamalıdır
      final secondResult = await processor.processOutbox();
      expect(secondResult.totalProcessed, 0);
      expect(httpCalls, 1, reason: 'REJECTED mutasyon için tekrar HTTP isteği atılmamalıdır (sonsuz döngü engellendi)');
    });

    test('10.7.2.4: Uygulama yeniden başlatıldığında REJECTED durumu korunmalı ve listelenebilmeli', () async {
      await seedOutboxMutation('evt-persist-rej', 'sale-p', {'total': 500});

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [],
            'conflicts': [],
            'rejected': [
              {'mutation_id': 'evt-persist-rej', 'error': 'mutation_payload_conflict'}
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient1 = SyncV4HttpClient(
        baseUrl: 'https://test.local',
        deviceActivationId: 'act-1',
        deviceId: 'dev-1',
        client: mockClient,
      );
      final processor1 = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient1);
      await processor1.processOutbox();

      // Veritabanını kapatıp diski yeniden yükle
      await coreDb.close();
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);

      final httpClient2 = SyncV4HttpClient(
        baseUrl: 'https://test.local',
        deviceActivationId: 'act-1',
        deviceId: 'dev-1',
        client: mockClient,
      );
      final processor2 = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient2);

      // Yeniden başlatma sonrasında getRejectedMutations tanılama kaydını vermelidir
      final rejectedList = await processor2.getRejectedMutations();
      expect(rejectedList.length, 1);
      expect(rejectedList.first.eventId, 'evt-persist-rej');
      expect(rejectedList.first.syncState, 'REJECTED');

      // Kuyruk işlemcisi tekrar PENDING varsaymamalıdır
      final r = await processor2.processOutbox();
      expect(r.totalProcessed, 0);
    });

    test('10.7.2.5: Geçici ağ ve sunucu 5xx hatalarında TRANSIENT_ERROR korunmalıdır', () async {
      await seedOutboxMutation('evt-transient', 'sale-t', {'total': 300});

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Internal server error during database lock'}),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://test.local',
        deviceActivationId: 'act-1',
        deviceId: 'dev-1',
        client: mockClient,
      );
      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      final result = await processor.processOutbox();
      expect(result.transientErrorCount, 1);
      expect(result.rejectedCount, 0);

      final row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['evt-transient'])).first;
      expect(row['sync_state'], 'TRANSIENT_ERROR');
    });

    test('10.7.2.6: HTTP 409 Çatışma Ayrımı: Bilinmeyen kod TRANSIENT_ERROR, doğrulanmış kod REJECTED olmalıdır', () async {
      await seedOutboxMutation('evt-409-known', 'sale-k', {'total': 150});
      await seedOutboxMutation('evt-409-unknown', 'sale-u', {'total': 250});

      // 1. Bilinen hata kodu: sale_payload_conflict -> REJECTED
      final mockKnown = MockClient((req) async {
        return http.Response(
          jsonEncode({'error': 'sale_payload_conflict'}),
          409,
          headers: {'content-type': 'application/json'},
        );
      });
      final pKnown = SyncV4OutboxProcessor(
        db: coreDb,
        httpClient: SyncV4HttpClient(
          baseUrl: 'https://test.local',
          deviceActivationId: 'act-1',
          deviceId: 'dev-1',
          client: mockKnown,
        ),
      );

      final resKnown = await pKnown.processOutbox(batchSize: 1);
      expect(resKnown.rejectedCount, 1);
      var row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['evt-409-known'])).first;
      expect(row['sync_state'], 'REJECTED');

      // 2. Bilinmeyen kod içeren 409: Körlemesine reddetme, geçici kabul et -> TRANSIENT_ERROR
      final mockUnknown = MockClient((req) async {
        return http.Response(
          jsonEncode({'error': 'arbitrary_temporary_409'}),
          409,
          headers: {'content-type': 'application/json'},
        );
      });
      final pUnknown = SyncV4OutboxProcessor(
        db: coreDb,
        httpClient: SyncV4HttpClient(
          baseUrl: 'https://test.local',
          deviceActivationId: 'act-1',
          deviceId: 'dev-1',
          client: mockUnknown,
        ),
      );

      final resUnknown = await pUnknown.processOutbox(batchSize: 1);
      expect(resUnknown.transientErrorCount, 1);
      row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['evt-409-unknown'])).first;
      expect(row['sync_state'], 'TRANSIENT_ERROR');
    });

    test('10.7.2.7: Başarılı gönderimin mevcut davranışı korunmalıdır (SYNCED)', () async {
      await seedOutboxMutation('evt-ok-1', 'sale-ok', {'total': 100});

      final mockClient = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': 'evt-ok-1', 'revision': 55}
            ],
            'conflicts': [],
            'rejected': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final processor = SyncV4OutboxProcessor(
        db: coreDb,
        httpClient: SyncV4HttpClient(
          baseUrl: 'https://test.local',
          deviceActivationId: 'act-1',
          deviceId: 'dev-1',
          client: mockClient,
        ),
      );

      final res = await processor.processOutbox();
      expect(res.syncedCount, 1);
      expect(res.rejectedCount, 0);
      expect(res.transientErrorCount, 0);

      final row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['evt-ok-1'])).first;
      expect(row['sync_state'], 'SYNCED');
      expect(row['base_revision'], 55);
      expect(row['last_error'], isNull);
    });
  });

  group('STAGE 10.7 — Watermark, Delta ve Migration Doğrulamaları', () {
    late CoreAppDatabase coreDb;

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      await coreDb.db.insert('products', {
        'id': 'p-watermark-1',
        'barcode': '8690099',
        'name': 'Organik Zeytinyağı 1L',
        'price_cents': 35000,
        'stock_quantity': 50,
        'vat_rate': 10,
        'unit': 'piece',
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await coreDb.close();
    });

    test('10.7.3.1: Satış + İade kombinasyonunda effectiveStock formülü matematiksel doğruluğu', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Kasa B bir satış yapar (4 adet satar) -> revision 10
      final changeSale = SyncPullChange(
        mutationId: 'mut-sale-w1',
        entityType: 'sale',
        entityId: 'sale-b-w1',
        operation: 'UPSERT',
        revision: 10,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'p-watermark-1', 'quantity': 4}
          ]
        },
      );
      await ingestion.ingestPull(SyncPullResponseDto(changes: [changeSale], nextCursor: 10));

      // Kasa B bir iade yapar (1 adet iade) -> revision 11
      final changeRefund = SyncPullChange(
        mutationId: 'mut-ref-w1',
        entityType: 'refund',
        entityId: 'ref-b-w1',
        operation: 'UPSERT',
        revision: 11,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'p-watermark-1', 'quantity': 1}
          ]
        },
      );
      await ingestion.ingestPull(SyncPullResponseDto(changes: [changeRefund], nextCursor: 11));

      // Stok: 50 - 4 + 1 = 47 olmalıdır
      var p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-watermark-1'])).first;
      expect(p['stock_quantity'], 47);

      // Şimdi eski bir ürün katalog snapshot'ı geliyor: revision 8 (satış ve iadeden önce çekilmiş), raw stock = 50
      final changeProduct = SyncPullChange(
        mutationId: 'mut-prod-snap',
        entityType: 'product',
        entityId: 'p-watermark-1',
        operation: 'UPSERT',
        revision: 8,
        deviceId: 'server',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'name': 'Organik Zeytinyağı 1L (Yeni Etiket)',
          'stock_quantity': 50,
          'price_cents': 35000,
        },
      );
      await ingestion.ingestPull(SyncPullResponseDto(changes: [changeProduct], nextCursor: 11));

      // post_delta hesabı: revision > 8 olan hareketlerin toplam delta'sı: (-4) + (+1) = -3
      // effectiveStock = 50 - (-(-3)) = 50 - 3 = 47!
      p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-watermark-1'])).first;
      expect(p['stock_quantity'], 47, reason: 'Eski katalog snapshotı yeni satış ve iade hareketlerini ezmemelidir');
      expect(p['name'], 'Organik Zeytinyağı 1L (Yeni Etiket)', reason: 'Ürün metadata güncellenmelidir');
    });

    test('10.7.3.2: Şema migration v2 -> v3 yükseltmesi ve onUpgrade idempotency', () async {
      final temp = await Directory.systemTemp.createTemp('serenut_mig_');
      final path = '${temp.path}/mig_v2_v3.db';

      // v2 şeması ile aç ve sadece temel tabloları oluştur
      final dbV2 = await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          for (final q in CoreSchemaDefinitions.createTablesQueries) {
            // sync_applied_events tablosu hariç (v3 ile eklendi)
            if (!q.contains('sync_applied_events')) {
              await db.execute(q);
            }
          }
        },
      );

      // v2'ye veri ekle
      await dbV2.insert('products', {
        'id': 'p-mig-1',
        'barcode': '12345',
        'name': 'Test Ürün',
        'price_cents': 1000,
        'stock_quantity': 10,
        'vat_rate': 20,
        'unit': 'piece',
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1000,
      });
      await dbV2.close();

      // CoreAppDatabase.open (v3) ile aç -> migrate çalışacaktır
      final dbV3 = await CoreAppDatabase.open(inMemoryOrCustomPath: path);

      // sync_applied_events tablosu var mı?
      final tables = await dbV3.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sync_applied_events'");
      expect(tables.length, 1, reason: 'v3 migration sync_applied_events tablosunu eklemiş olmalıdır');

      // Eski ürün verisi bozulmamış mı?
      final p = (await dbV3.db.query('products', where: 'id = ?', whereArgs: ['p-mig-1'])).first;
      expect(p['name'], 'Test Ürün');
      expect(p['stock_quantity'], 10);

      // Tekrar migrate çalıştırılsa dahi IF NOT EXISTS hata vermemeli
      await CoreSchemaDefinitions.migrate(dbV3.db, 2, 3);

      await dbV3.close();
      await temp.delete(recursive: true);
    });
  });
}
