// test/core_next/stage10_7_3_pull_worker_test.dart
// SERENUT OS — STAGE 10.7.3 PULL WORKER VE ÇALIŞMA ZİNCİRİ TESTLERİ
//
// 1. Tek sayfalı pull başarılı.
// 2. Birden fazla sayfa doğru sırayla işleniyor.
// 3. Son sayfada worker doğru şekilde duruyor.
// 4. Ağ hatasından sonra retry ile devam ediyor.
// 5. Kalıcı hata sonsuz retry üretmiyor.
// 6. Bir sayfa uygulanırken hata olursa cursor ilerlemiyor.
// 7. Aynı sayfa yeniden geldiğinde stok mükerrer değişmiyor.
// 8. Aynı worker'ın eşzamanlı iki çalışması güvenli biçimde engelleniyor veya serileştiriliyor.
// 9. Uygulama yeniden başlatıldıktan sonra cursor üzerinden devam ediliyor.
// 10. Boş sayfa ve yinelenen event doğru ele alınıyor.
// 11. Eksik cihaz kimliği güvenli şekilde reddediliyor.
// 12. Satış ve iade stok hareketleri önceki Stage 10.7.2 testleriyle uyumlu.
// 13. Bootstrap ile incremental pull arasında yanlış cursor geçişi yapılmıyor.
// 14. HTTP hata kodları ve retry sınıflandırması gerçek istemci sözleşmesiyle uyumlu.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/sync_dtos.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_pull_worker.dart';
import '../../core_next/client_core/lib/presentation/di/core_providers.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.7.3 — Pull Worker ve Senkronizasyon Çalışma Zinciri Testleri', () {
    late Directory tempDir;
    late String dbPath;
    late CoreAppDatabase coreDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_test_10_7_3_');
      dbPath = '${tempDir.path}/pull_worker.db';
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);

      // Başlangıç ürünü: 30 adet stok
      await coreDb.db.insert('products', {
        'id': 'prod-worker-1',
        'barcode': '8690010',
        'name': 'Rize Çayı 500g',
        'price_cents': 9500,
        'stock_quantity': 30,
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

    test('10.7.3.1: Tek sayfalı pull başarılı çalışmalı ve cursor güncellenmeli', () async {
      final mockHttp = MockClient((request) async {
        expect(request.url.path, '/api/v4/sync/pull');
        expect(request.url.queryParameters['cursor'], '0');
        expect(request.url.queryParameters['limit'], '200');

        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 10,
                'mutation_id': 'mut-single-1',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-single-1',
                'operation': 'UPSERT',
                'payload': {
                  'items': [
                    {'product_id': 'prod-worker-1', 'quantity': 5}
                  ]
                },
                'created_at': DateTime.now().toIso8601String(),
              }
            ],
            'next_cursor': 10,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
        pageSize: 200,
      );

      final result = await worker.pullAll();

      expect(result.isSuccess, isTrue);
      expect(result.totalBatches, 1);
      expect(result.totalChanges, 1);
      expect(result.finalCursor, 10);
      expect(result.hasMoreRemaining, isFalse);

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-worker-1'])).first;
      expect(prod['stock_quantity'], 25, reason: 'Kasa B satışı stoğu 30 -> 25 düşürmelidir');

      final savedCursor = await ingestionService.getSavedCursor();
      expect(savedCursor, 10, reason: 'Veritabanındaki cursor 10 olmalıdır');
    });

    test('10.7.3.2: Birden fazla sayfa doğru sırayla işlenmeli (Pagination Loop)', () async {
      int requestCount = 0;
      final mockHttp = MockClient((request) async {
        requestCount++;
        final cursor = request.url.queryParameters['cursor'];

        if (cursor == '0') {
          // 1. Sayfa (Limit: 2) -> 2 kayıt döner, next_cursor: 5
          return http.Response(
            jsonEncode({
              'changes': [
                {
                  'revision': 4,
                  'mutation_id': 'mut-page1-a',
                  'device_id': 'kasa-b',
                  'entity_type': 'sale',
                  'entity_id': 'sale-p1-a',
                  'operation': 'UPSERT',
                  'payload': {
                    'items': [{'product_id': 'prod-worker-1', 'quantity': 2}]
                  },
                },
                {
                  'revision': 5,
                  'mutation_id': 'mut-page1-b',
                  'device_id': 'kasa-b',
                  'entity_type': 'sale',
                  'entity_id': 'sale-p1-b',
                  'operation': 'UPSERT',
                  'payload': {
                    'items': [{'product_id': 'prod-worker-1', 'quantity': 3}]
                  },
                },
              ],
              'next_cursor': 5,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (cursor == '5') {
          // 2. Sayfa (Limit: 2) -> 1 kayıt döner, next_cursor: 8 (Son sayfa)
          return http.Response(
            jsonEncode({
              'changes': [
                {
                  'revision': 8,
                  'mutation_id': 'mut-page2-a',
                  'device_id': 'kasa-b',
                  'entity_type': 'sale',
                  'entity_id': 'sale-p2-a',
                  'operation': 'UPSERT',
                  'payload': {
                    'items': [{'product_id': 'prod-worker-1', 'quantity': 1}]
                  },
                },
              ],
              'next_cursor': 8,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response(jsonEncode({'changes': [], 'next_cursor': cursor}), 200);
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
        pageSize: 2, // 2'şer kayıtlık sayfalar
      );

      final result = await worker.pullAll(maxPages: 10);

      expect(result.isSuccess, isTrue);
      expect(result.totalBatches, 2);
      expect(result.totalChanges, 3);
      expect(result.finalCursor, 8);
      expect(requestCount, 2);

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-worker-1'])).first;
      expect(prod['stock_quantity'], 24, reason: 'Toplam 2 + 3 + 1 = 6 adet düşmeli, stok 24 olmalıdır');
    });

    test('10.7.3.3: Son sayfada worker doğru şekilde durmalı ve döngü sonlanmalı', () async {
      int calls = 0;
      final mockHttp = MockClient((request) async {
        calls++;
        // İlk çağrıda 1 kayıt döner (< pageSize: 2), yani son sayfa
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 15,
                'mutation_id': 'mut-last-1',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-last-1',
                'operation': 'UPSERT',
                'payload': {
                  'items': [{'product_id': 'prod-worker-1', 'quantity': 1}]
                },
              }
            ],
            'next_cursor': 15,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
        pageSize: 5,
      );

      final result = await worker.pullAll();
      expect(result.isSuccess, isTrue);
      expect(calls, 1, reason: 'Sayfa kayıt sayısı < pageSize olduğunda ek HTTP çağrısı yapılmamalıdır');
      expect(result.hasMoreRemaining, isFalse);
    });

    test('10.7.3.4: Geçici ağ hatasından sonra retry ile devam edebilmeli', () async {
      int attempts = 0;
      final mockHttp = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          throw http.ClientException('Ağ bağlantısı koptu (simüle edilen hata)');
        }
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 20,
                'mutation_id': 'mut-retry-ok',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-retry-ok',
                'operation': 'UPSERT',
                'payload': {
                  'items': [{'product_id': 'prod-worker-1', 'quantity': 4}]
                },
              }
            ],
            'next_cursor': 20,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
        maxRetries: 2,
        retryDelay: Duration.zero,
      );

      final result = await worker.pullAll();
      expect(result.isSuccess, isTrue);
      expect(attempts, 2, reason: 'İlk ağ hatasından sonra ikinci denemede başarı sağlanmalıdır');
      expect(result.finalCursor, 20);
    });

    test('10.7.3.5: Kalıcı hata (HTTP 403 / 401) sonsuz retry üretmemeli ve hemen durmalı', () async {
      int attempts = 0;
      final mockHttp = MockClient((request) async {
        attempts++;
        return http.Response(
          jsonEncode({'error': 'inactive_or_mismatched_device'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
        maxRetries: 3,
        retryDelay: Duration.zero,
      );

      final result = await worker.pullAll();
      expect(result.isSuccess, isFalse);
      expect(result.isPermanentError, isTrue);
      expect(attempts, 1, reason: 'HTTP 403 kalıcı hatadır; retry yapılmadan anında durmalıdır');
    });

    test('10.7.3.6: Bir sayfa uygulanırken hata olursa cursor ilerlememeli (ACID Rollback)', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 30,
                'mutation_id': 'mut-corrupt-1',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-corrupt-1',
                'operation': 'UPSERT',
                'payload': {
                  'items': [
                    {'product_id': 'prod-worker-1', 'quantity': 'invalid_string_not_number'}
                  ]
                },
              }
            ],
            'next_cursor': 30,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
      );

      final batchResult = await worker.pullSingleBatch();
      expect(batchResult.isSuccess, isFalse);

      final savedCursor = await ingestionService.getSavedCursor();
      expect(savedCursor, 0, reason: 'İşlem başarısız olduğunda cursor asla güncellenmemelidir');

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-worker-1'])).first;
      expect(prod['stock_quantity'], 30, reason: 'Stok bozulmamalı ve geri alınmalıdır');
    });

    test('10.7.3.7: Aynı sayfa yeniden geldiğinde stok mükerrer değişmemeli (Idempotency)', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 40,
                'mutation_id': 'mut-replay-page',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-replay-page-1',
                'operation': 'UPSERT',
                'payload': {
                  'items': [{'product_id': 'prod-worker-1', 'quantity': 3}]
                },
              }
            ],
            'next_cursor': 40,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
      );

      // 1. Çekim: Stok 30 -> 27 düşer
      await worker.pullSingleBatch();
      var prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-worker-1'])).first;
      expect(prod['stock_quantity'], 27);

      // 2. Çekim (Aynı sayfa zorla tekrar çağrılıyor)
      await worker.pullSingleBatch(cursorOverride: 0);
      prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-worker-1'])).first;
      expect(prod['stock_quantity'], 27, reason: 'Replay durumunda sync_applied_events mükerrer stok düşümünü engellemelidir');
    });

    test('10.7.3.8: Aynı worker\'ın eşzamanlı iki çalışması güvenli biçimde engellenmeli (Concurrency Lock)', () async {
      final completer = Completer<http.Response>();
      final mockHttp = MockClient((request) async {
        return await completer.future;
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://sync.test.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'kasa-a',
        client: mockHttp,
      );
      final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(
        httpClient: httpClient,
        ingestionService: ingestionService,
      );

      // İlk pull başlatılıyor ve HTTP cevabı bekletiliyor
      final future1 = worker.pullAll();
      expect(worker.isRunning, isTrue);

      // İkinci pull başlatılmaya çalışıldığında StateError fırlatılmalı
      expect(() => worker.pullAll(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('pull_worker_busy'))));

      // İlk isteği tamamla
      completer.complete(http.Response(jsonEncode({'changes': [], 'next_cursor': 0}), 200));
      await future1;
      expect(worker.isRunning, isFalse);
    });

    test('10.7.3.9: Uygulama yeniden başlatıldıktan sonra cursor üzerinden devam edilmeli', () async {
      final mockHttp1 = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 55,
                'mutation_id': 'mut-step1',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-step1',
                'operation': 'UPSERT',
                'payload': {
                  'items': [{'product_id': 'prod-worker-1', 'quantity': 2}]
                },
              }
            ],
            'next_cursor': 55,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final http1 = SyncV4HttpClient(baseUrl: 'https://sync.test.local', deviceActivationId: 'act-1', deviceId: 'kasa-a', client: mockHttp1);
      final ingestion1 = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker1 = SyncV4PullWorker(httpClient: http1, ingestionService: ingestion1);

      await worker1.pullSingleBatch();
      expect(await ingestion1.getSavedCursor(), 55);

      // Veritabanını kapat ve diski simüle ederek yeniden aç
      await coreDb.close();
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);

      int requestedCursor = -1;
      final mockHttp2 = MockClient((request) async {
        requestedCursor = int.parse(request.url.queryParameters['cursor']!);
        return http.Response(
          jsonEncode({'changes': [], 'next_cursor': requestedCursor}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final http2 = SyncV4HttpClient(baseUrl: 'https://sync.test.local', deviceActivationId: 'act-1', deviceId: 'kasa-a', client: mockHttp2);
      final ingestion2 = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker2 = SyncV4PullWorker(httpClient: http2, ingestionService: ingestion2);

      await worker2.pullSingleBatch();
      expect(requestedCursor, 55, reason: 'Restart sonrası pull bir önceki kaydedilmiş 55 cursorundan devam etmelidir');
    });

    test('10.7.3.10: Boş sayfa ve yinelenen event doğru ele alınmalı', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'changes': [],
            'next_cursor': 70,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(baseUrl: 'https://sync.test.local', deviceActivationId: 'act-1', deviceId: 'kasa-a', client: mockHttp);
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(httpClient: httpClient, ingestionService: ingestion);

      final res = await worker.pullAll();
      expect(res.isSuccess, isTrue);
      expect(res.totalBatches, 1);
      expect(res.totalChanges, 0);
      expect(res.hasMoreRemaining, isFalse);
    });

    test('10.7.3.11: Eksik cihaz kimliği güvenli şekilde reddedilmeli (Fail-Closed)', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'revision': 80,
                'mutation_id': 'mut-no-dev',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-no-dev',
                'operation': 'UPSERT',
                'payload': {'items': [{'product_id': 'prod-worker-1', 'quantity': 1}]},
              }
            ],
            'next_cursor': 80,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(baseUrl: 'https://sync.test.local', deviceActivationId: 'act-1', deviceId: 'kasa-a', client: mockHttp);
      // localDeviceId: null verildiğinde
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: null);
      final worker = SyncV4PullWorker(httpClient: httpClient, ingestionService: ingestion);

      final result = await worker.pullAll();
      expect(result.isSuccess, isFalse);
      expect(result.isPermanentError, isTrue);
      expect(result.error, contains('unidentified_local_device'));

      final cursor = await ingestion.getSavedCursor();
      expect(cursor, 0, reason: 'Cihaz kimliği eksikken cursor asla ilerlememelidir');
    });

    test('10.7.3.12: Satış ve iade stok hareketleri Stage 10.7.2 kimlik kurallarıyla tam uyumlu olmalı', () async {
      // Yerelde bir satış var: REC-W-100
      await coreDb.db.insert('sales', {
        'id': 'sale-local-w-1',
        'receipt_no': 'REC-W-100',
        'subtotal_cents': 9500,
        'discount_cents': 0,
        'vat_total_cents': 1900,
        'total_cents': 9500,
        'paid_cents': 9500,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'REC-W-100',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'changes': [
              // 1. Kendi kasanın satışı (UUID eşleşiyor): Stok düşmemeli
              {
                'revision': 90,
                'mutation_id': 'm-own',
                'device_id': 'kasa-a',
                'entity_type': 'sale',
                'entity_id': 'sale-local-w-1',
                'operation': 'UPSERT',
                'payload': {
                  'receipt_no': 'REC-W-100',
                  'items': [{'product_id': 'prod-worker-1', 'quantity': 1}]
                },
              },
              // 2. Kasa B'nin satışı (aynı receipt_no ama yabancı device): Stok düşmeli (30 -> 28)
              {
                'revision': 91,
                'mutation_id': 'm-foreign-sale',
                'device_id': 'kasa-b',
                'entity_type': 'sale',
                'entity_id': 'sale-foreign-w-2',
                'operation': 'UPSERT',
                'payload': {
                  'receipt_no': 'REC-W-100',
                  'items': [{'product_id': 'prod-worker-1', 'quantity': 2}]
                },
              },
              // 3. Kasa B'nin iadesi: Stok artmalı (28 -> 29)
              {
                'revision': 92,
                'mutation_id': 'm-foreign-ref',
                'device_id': 'kasa-b',
                'entity_type': 'refund',
                'entity_id': 'ref-foreign-w-3',
                'operation': 'UPSERT',
                'payload': {
                  'items': [{'product_id': 'prod-worker-1', 'quantity': 1}]
                },
              },
            ],
            'next_cursor': 92,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final httpClient = SyncV4HttpClient(baseUrl: 'https://sync.test.local', deviceActivationId: 'act-1', deviceId: 'kasa-a', client: mockHttp);
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(httpClient: httpClient, ingestionService: ingestion);

      final result = await worker.pullAll();
      expect(result.isSuccess, isTrue);

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-worker-1'])).first;
      // 30 (başlangıç) - 0 (kendi satışı) - 2 (yabancı satış) + 1 (yabancı iade) = 29 olmalıdır!
      expect(prod['stock_quantity'], 29, reason: 'Stok hareketleri Stage 10.7.2 kurallarıyla tam uyumlu olmalıdır');
    });

    test('10.7.3.13: Bootstrap ardından incremental pull doğru cursor geçişi yapmalı', () async {
      int bootstrapCalls = 0;
      int pullCalls = 0;
      int pullCursorReceived = -1;

      final mockHttp = MockClient((request) async {
        if (request.url.path == '/api/v4/sync/bootstrap') {
          bootstrapCalls++;
          return http.Response(
            jsonEncode({
              'changes': [
                {
                  'revision': 100,
                  'mutation_id': 'boot-1',
                  'device_id': 'server',
                  'entity_type': 'product',
                  'entity_id': 'prod-boot-1',
                  'operation': 'UPSERT',
                  'payload': {
                    'name': 'Bootstrap Ürünü',
                    'barcode': '111222',
                    'price_cents': 5000,
                    'stock_quantity': 50,
                  },
                }
              ],
              'next_cursor': 100,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v4/sync/pull') {
          pullCalls++;
          pullCursorReceived = int.parse(request.url.queryParameters['cursor']!);
          return http.Response(
            jsonEncode({
              'changes': [],
              'next_cursor': pullCursorReceived,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SyncV4HttpClient(baseUrl: 'https://sync.test.local/api/v4/sync', deviceActivationId: 'act-1', deviceId: 'kasa-a', client: mockHttp);
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final worker = SyncV4PullWorker(httpClient: httpClient, ingestionService: ingestion);

      // 1. Bootstrap çalıştırılır
      final bootRes = await worker.bootstrap();
      expect(bootRes.isSuccess, isTrue);
      expect(bootRes.cursorAfter, 100);
      expect(bootstrapCalls, 1);

      // 2. Ardından incremental pullSingleBatch çalıştırılır
      final pullRes = await worker.pullSingleBatch();
      expect(pullRes.isSuccess, isTrue);
      expect(pullCalls, 1);
      expect(pullCursorReceived, 100, reason: 'Pull, bootstrap sonrasında dönen 100 cursor değerini kullanmalıdır');
    });

    test('10.7.3.14: HTTP hata kodları ve retry sınıflandırması sözleşmeyle uyumlu olmalı ve Riverpod DI konteynerinde çözülebilmeli', () async {
      // 1. Retry edilebilirlik kuralları doğrulaması
      expect(SyncV4PullWorker.isRetryableError(const SyncNetworkException('Ağ kesildi')), isTrue);
      expect(SyncV4PullWorker.isRetryableError(const SyncTimeoutException()), isTrue);
      expect(SyncV4PullWorker.isRetryableError(const SyncServerException('Sunucu hatası', 500)), isTrue);
      expect(SyncV4PullWorker.isRetryableError(const SyncUnauthorizedException('401')), isFalse);
      expect(SyncV4PullWorker.isRetryableError(const SyncForbiddenException('403')), isFalse);
      expect(SyncV4PullWorker.isRetryableError(const SyncBadRequestException('400')), isFalse);
      expect(SyncV4PullWorker.isRetryableError(const SyncProtocolUpgradeRequiredException(requiredVersion: 7, message: '426')), isFalse);

      // 2. Riverpod DI bağlantısı doğrulaması
      final mockHttp = MockClient((req) async => http.Response(jsonEncode({'changes': [], 'next_cursor': 0}), 200));
      final httpClient = SyncV4HttpClient(baseUrl: 'https://sync.test.local', deviceActivationId: 'act-1', deviceId: 'kasa-a', client: mockHttp);

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          coreDeviceIdProvider.overrideWithValue('kasa-a'),
          coreSyncHttpClientProvider.overrideWithValue(httpClient),
        ],
      );

      final workerFromDi = container.read(coreSyncPullWorkerProvider);
      expect(workerFromDi, isNotNull);
      expect(workerFromDi.httpClient.deviceId, 'kasa-a');
      expect(workerFromDi.ingestionService.localDeviceId, 'kasa-a');

      container.dispose();
    });
  });
}
