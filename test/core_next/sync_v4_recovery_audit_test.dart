// test/core_next/sync_v4_recovery_audit_test.dart

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

  const fakeBaseUrl = 'https://fake-isolated-audit.local/api/v4/sync';
  const fakeActivationId = 'audit-activation-uuid';
  const fakeDeviceId = 'audit-device-uuid';
  const fakeToken = 'fake_audit_token_123';

  group('Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri', () {
    late CoreAppDatabase coreDb;

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
    });

    tearDown(() async {
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 1: Satış başarılı, finansal hareket reddedildiğinde
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 1: Kısmi batch kabulünde satış kilitlenmeli, finansal mutasyon korunmalı, stok tekrarlanmamalı', () async {
      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);
      final hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();

      // Ürün ve müşteri ekle
      await coreDb.db.insert('products', {
        'id': 'prod-recovery-1',
        'barcode': '86900100',
        'name': 'Test Ürünü',
        'price_cents': 10000, // 100.00 TL
        'stock_quantity': 20,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': 'cust-recovery-1',
        'name': 'Ali Veli',
        'phone': '05559998877',
        'balance_cents': 0,
        'credit_limit_cents': 50000,
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
          id: 'prod-recovery-1',
          barcode: '86900100',
          name: 'Test Ürünü',
          price: const MoneyCents(10000),
          stockQuantity: 20,
          updatedAt: DateTime.now(),
        ),
        quantity: 2,
      );
      final cust = await ledgerRepo.getCustomer('cust-recovery-1');
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(20000)),
      ]);

      final sale = await notifier.completeCheckout(
        receiptNo: 'REC-AUDIT-1',
        storeTitle: 'Mağaza',
        actor: ActorContext.testManager,
      );
      expect(sale.receiptNo, 'REC-AUDIT-1');

      // Yerel stok 20 -> 18'e indi
      final p1 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-recovery-1'])).first;
      expect(p1['stock_quantity'], 18);

      final outbox1 = await coreDb.db.query('sync_events', orderBy: 'causal_sequence ASC');
      expect(outbox1.length, 2);
      final saleId = outbox1[0]['event_id'] as String;
      final finId = outbox1[1]['event_id'] as String;

      int pushCount = 0;
      List<dynamic>? round2Mutations;

      final mockClient = MockClient((request) async {
        pushCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final mutations = body['mutations'] as List;

        if (pushCount == 1) {
          expect(mutations.length, 2);
          // Satış sunucuda başarılı, finansal hareket reddedildi (invalid_customer)
          return http.Response(
            jsonEncode({
              'results': [
                {'mutation_id': saleId, 'revision': 10}
              ],
              'conflicts': [],
              'rejected': [
                {'mutation_id': finId, 'error': 'invalid_customer'} // Kalıcı ret
              ],
            }),
            200,
          );
        } else {
          round2Mutations = mutations;
          return http.Response(jsonEncode({'results': [], 'conflicts': [], 'rejected': []}), 200);
        }
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );
      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      // 1. Tur Senkronizasyon
      final res1 = await processor.processOutbox();
      expect(res1.syncedCount, 1);
      expect(res1.rejectedCount, 1);

      // Satış kesin olarak SYNCED olmalı
      final saleRow = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: [saleId])).first;
      expect(saleRow['sync_state'], 'SYNCED');

      // Finansal mutasyon REJECTED olmalı (silinmemeli, hata bilgisi korunmalı)
      final finRow = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: [finId])).first;
      expect(finRow['sync_state'], 'REJECTED');
      expect(finRow['last_error'], 'invalid_customer');

      // 2. Tur Senkronizasyon (Tekrar deneme)
      final res2 = await processor.processOutbox();
      expect(res2.totalProcessed, 0); // Hiçbir bekleyen mutasyon kalmadı
      expect(pushCount, 1); // Satış tekrar gönderilmedi!
      expect(round2Mutations, isNull);

      // Stok hâlâ 18 (ikinci kez düşürülmedi)
      final p2 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-recovery-1'])).first;
      expect(p2['stock_quantity'], 18);

      await hardwareWorker.dispose();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 2: Yanıt kaybı sonrası aynı mutation_id ile güvenli tekrar
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 2: Sunucunun işlemi kaydedip yanıtın kaybolduğu durumda aynı mutation_id ile güvenli tekrar', () async {
      await coreDb.db.insert('sync_events', {
        'event_id': 'idemp-audit-mutation-001',
        'entity_type': 'sale',
        'entity_id': 'sale-loss-1',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'total_amount': 250.0}),
        'client_timestamp': 1700000000,
        'sync_state': 'PENDING',
        'base_revision': 0,
        'attempts': 0,
        'causal_sequence': 1,
      });

      int attemptCount = 0;
      final sentMutationIds = <String>[];

      final mockClient = MockClient((request) async {
        attemptCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final mutations = body['mutations'] as List;
        sentMutationIds.add(mutations.first['mutation_id'] as String);

        if (attemptCount == 1) {
          // Sunucu DB'ye kaydetti ancak yanıt istemciye ulaşmadan soket kapandı
          throw http.ClientException('Network pipe closed before HTTP response received');
        } else {
          // İkinci denemede sunucu aynı mutation_id'yi tanır ve ack döner
          return http.Response(
            jsonEncode({
              'results': [
                {'mutation_id': 'idemp-audit-mutation-001', 'revision': 42}
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

      // 1. Çalıştırma: Hata yakalanır, TRANSIENT_ERROR yapılır
      final res1 = await processor.processOutbox();
      expect(res1.transientErrorCount, 1);
      var row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['idemp-audit-mutation-001'])).first;
      expect(row['sync_state'], 'TRANSIENT_ERROR');
      expect(row['attempts'], 1);

      // 2. Çalıştırma: Aynı ID tekrar gönderilir
      final res2 = await processor.processOutbox();
      expect(res2.syncedCount, 1);
      row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['idemp-audit-mutation-001'])).first;
      expect(row['sync_state'], 'SYNCED');

      // Her iki gönderimde de aynı mutation_id kullanılmıştır!
      expect(sentMutationIds.length, 2);
      expect(sentMutationIds[0], 'idemp-audit-mutation-001');
      expect(sentMutationIds[1], 'idemp-audit-mutation-001');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 3: İki istemcinin çakışan değişiklikleri ve base_revision
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 3: Eşzamanlı çakışmada server_revision > base_revision ise CONFLICT durumuna alınmalı', () async {
      await coreDb.db.insert('sync_events', {
        'event_id': 'mut-conflict-01',
        'entity_type': 'product',
        'entity_id': 'prod-conf-1',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'price': 150.0}),
        'client_timestamp': 1700000000,
        'sync_state': 'PENDING',
        'base_revision': 3, // İstemcinin gördüğü son revizyon 3
        'attempts': 0,
        'causal_sequence': 0,
      });

      final mockClient = MockClient((request) async {
        // Sunucuda başka bir cihaz revizyonu 5'e yükseltmiş -> Çakışma!
        return http.Response(
          jsonEncode({
            'results': [],
            'conflicts': [
              {
                'mutation_id': 'mut-conflict-01',
                'entity_type': 'product',
                'entity_id': 'prod-conf-1',
                'server_revision': 5,
              }
            ],
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

      final res = await processor.processOutbox();
      expect(res.conflictCount, 1);
      expect(res.syncedCount, 0);

      final row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-conflict-01'])).first;
      expect(row['sync_state'], 'CONFLICT');
      expect(row['last_error'], contains('rev: 5'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 4: Uygulamanın yeniden başlatılması ve yarıda kesilen işlemler
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 4: Yarıda kesilen transaction rollback olmalı, disk DB yeniden açıldığında kuyruk bozulmamalı', () async {
      final tempDir = Directory.systemTemp.createTempSync('audit_restart_');
      final dbPath = '${tempDir.path}\\restart_audit.db';

      try {
        var diskDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);

        // 1. Transaction yarıda kesildiğinde (Crash simülasyonu)
        try {
          await diskDb.transaction((txn) async {
            await txn.insert('sync_events', {
              'event_id': 'crash-mutation',
              'entity_type': 'sale',
              'entity_id': 's-crash',
              'operation': 'UPSERT',
              'payload_json': jsonEncode({'total': 100}),
              'client_timestamp': 1000,
              'sync_state': 'PENDING',
              'base_revision': 0,
              'attempts': 0,
              'causal_sequence': 1,
            });
            throw Exception('Power cut during outbox insert!');
          });
        } catch (_) {}

        // Yarıda kesilen kayıt kesinlikle veritabanında olmamalı (ACID Atomicity)
        var checkRows = await diskDb.query('sync_events', where: 'event_id = ?', whereArgs: ['crash-mutation']);
        expect(checkRows.isEmpty, true);

        // 2. Başarıyla eklenmiş kayıtları koy
        await diskDb.db.insert('sync_events', {
          'event_id': 'persist-1',
          'entity_type': 'sale',
          'entity_id': 's-1',
          'operation': 'UPSERT',
          'payload_json': jsonEncode({'total': 100}),
          'client_timestamp': 2000,
          'sync_state': 'PENDING',
          'base_revision': 0,
          'attempts': 0,
          'causal_sequence': 1,
        });
        await diskDb.db.insert('sync_events', {
          'event_id': 'persist-synced',
          'entity_type': 'sale',
          'entity_id': 's-synced',
          'operation': 'UPSERT',
          'payload_json': jsonEncode({'total': 200}),
          'client_timestamp': 1500,
          'sync_state': 'SYNCED',
          'base_revision': 0,
          'attempts': 0,
          'causal_sequence': 1,
        });

        // Veritabanını kapat
        await diskDb.close();

        // 3. Uygulama yeniden başladı
        diskDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);

        // SYNCED kaydı SYNCED olarak durmalı, PENDING kaydı PENDING olarak durmalı
        final syncedRow = (await diskDb.query('sync_events', where: 'event_id = ?', whereArgs: ['persist-synced'])).first;
        expect(syncedRow['sync_state'], 'SYNCED');

        final pendingRows = await diskDb.query('sync_events', where: "sync_state = 'PENDING'");
        expect(pendingRows.length, 1);
        expect(pendingRows.first['event_id'], 'persist-1');

        await diskDb.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 5: group_id ve causal_sequence sıralaması
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 5: Outbox tüketicisi causal_sequence ve client_timestamp sırasına kesinlikle uymalı', () async {
      // Bilerek ters sırada ekle: causal_sequence 2 önce, 1 sonra
      await coreDb.db.insert('sync_events', {
        'event_id': 'seq-fin-tx',
        'entity_type': 'financial_transaction',
        'entity_id': 'fin-seq-1',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'amount': 100.0}),
        'client_timestamp': 5000,
        'sync_state': 'PENDING',
        'base_revision': 0,
        'attempts': 0,
        'group_id': 'sale-group-seq',
        'causal_sequence': 2, // 2. sıra
      });

      await coreDb.db.insert('sync_events', {
        'event_id': 'seq-sale',
        'entity_type': 'sale',
        'entity_id': 'sale-seq-1',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'total_amount': 100.0}),
        'client_timestamp': 5000,
        'sync_state': 'PENDING',
        'base_revision': 0,
        'attempts': 0,
        'group_id': 'sale-group-seq',
        'causal_sequence': 1, // 1. sıra
      });

      late List<dynamic> pushedMutations;
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        pushedMutations = body['mutations'] as List;
        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': 'seq-sale', 'revision': 1},
              {'mutation_id': 'seq-fin-tx', 'revision': 2},
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

      await processor.processOutbox();

      // Gönderilen mutasyon listesinde satış (causal 1) kesinlikle cari hareketten (causal 2) önce gelmeli!
      expect(pushedMutations.length, 2);
      expect(pushedMutations[0]['mutation_id'], 'seq-sale');
      expect(pushedMutations[0]['entity_type'], 'sale');
      expect(pushedMutations[1]['mutation_id'], 'seq-fin-tx');
      expect(pushedMutations[1]['entity_type'], 'financial_transaction');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 6: Pull cursor, sayfalama ve bootstrap devamlılığı
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 6: Bootstrap sonrası next_cursor pull çağrısına kesintisiz aktarılmalı ve sayfalama devam etmeli', () async {
      int apiCallIndex = 0;
      final mockClient = MockClient((request) async {
        apiCallIndex++;
        if (request.url.path == '/api/v4/sync/bootstrap') {
          return http.Response(
            jsonEncode({
              'changes': [
                {
                  'revision': 10,
                  'mutation_id': 'b-1',
                  'device_id': 'srv',
                  'entity_type': 'product',
                  'entity_id': 'p-b1',
                  'operation': 'UPSERT',
                  'payload': {'name': 'Ürün 1'},
                  'created_at': '2026-10-13T08:00:00Z',
                }
              ],
              'next_cursor': 1000,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        } else if (request.url.path == '/api/v4/sync/pull') {
          final cursor = request.url.queryParameters['cursor'];
          if (cursor == '1000') {
            return http.Response(
              jsonEncode({
                'changes': [
                  {
                    'revision': 11,
                    'mutation_id': 'p-1',
                    'device_id': 'srv',
                    'entity_type': 'product',
                    'entity_id': 'p-b1', // Aynı ürün güncellenmiş (LWW)
                    'operation': 'UPSERT',
                    'payload': {'name': 'Ürün 1 (Revize)'},
                    'created_at': '2026-10-13T08:30:00Z',
                  }
                ],
                'next_cursor': 1050,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          } else if (cursor == '1050') {
            // Boş sayfa (değişiklik yok)
            return http.Response(
              jsonEncode({
                'changes': [],
                'next_cursor': 1050,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: fakeBaseUrl,
        deviceActivationId: fakeActivationId,
        deviceId: fakeDeviceId,
        client: mockClient,
      );

      // 1. Bootstrap çağrısı
      final bootstrap = await httpClient.bootstrap();
      expect(bootstrap.changes.length, 1);
      expect(bootstrap.nextCursor, 1000);

      // 2. Bootstrap cursor'ı ile ilk pull
      final pull1 = await httpClient.pull(cursor: bootstrap.nextCursor);
      expect(pull1.changes.length, 1);
      expect(pull1.changes.first.payload['name'], 'Ürün 1 (Revize)');
      expect(pull1.nextCursor, 1050);

      // 3. Sonraki cursor ile ikinci pull
      final pull2 = await httpClient.pull(cursor: pull1.nextCursor);
      expect(pull2.changes.isEmpty, true);
      expect(pull2.nextCursor, 1050);
      expect(apiCallIndex, 3);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 7: Finansal mutasyon determinizmi ve sunucu idempotency garantisi
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 7: Finansal mutasyon deterministik kimlik üretmeli ve sunucu sözleşmesinde bakiye çift değişmemeli', () {
      const saleId = 'sale-determ-uuid';
      const custId = 'cust-determ-uuid';
      final saleDate = DateTime.parse('2026-10-13T12:00:00Z');

      // İstemci tarafı deterministik mutasyon inşası
      final mut1 = SyncV4PayloadAdapter.buildFinancialTransactionMutation(
        saleId: saleId,
        customerId: custId,
        total: const MoneyCents(15000), // 150 TL
        paid: const MoneyCents(5000),   // 50 TL peşin
        debt: const MoneyCents(10000),  // 100 TL veresiye
        paymentMethod: 'mixed',
        createdAt: saleDate,
        deterministicEventId: 'ev-fin-$saleId',
        deterministicEntityId: 'tx-fin-$saleId',
      );

      final mut2 = SyncV4PayloadAdapter.buildFinancialTransactionMutation(
        saleId: saleId,
        customerId: custId,
        total: const MoneyCents(15000),
        paid: const MoneyCents(5000),
        debt: const MoneyCents(10000),
        paymentMethod: 'mixed',
        createdAt: saleDate,
        deterministicEventId: 'ev-fin-$saleId',
        deterministicEntityId: 'tx-fin-$saleId',
      );

      // İstemci tarafı doğrulama: Aynı satış için üretilen finansal mutasyon kimliği ve gövdesi birebir eşittir
      expect(mut1.eventId, mut2.eventId);
      expect(mut1.entityId, mut2.entityId);
      expect(mut1.toServerMutationDto(), mut2.toServerMutationDto());

      final serverDto = mut1.toServerMutationDto();
      expect(serverDto['mutation_id'], 'ev-fin-$saleId');
      expect(serverDto['entity_id'], 'tx-fin-$saleId');
      expect(serverDto['entity_type'], 'financial_transaction');
      final payload = serverDto['payload'] as Map<String, dynamic>;
      expect(payload['amount'], 150.0);
      expect(payload['paid_amount'], 50.0);
      expect(payload['debt_amount'], 100.0);
      expect(payload['reference_id'], saleId);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // DENETİM 8: Sunucu yanıtında atlanan (unacknowledged) mutasyon güvenliği
    // ─────────────────────────────────────────────────────────────────────────
    test('Denetim 8: Sunucu yanıtında yer almayan atlanmış mutasyon TRANSIENT_ERROR olmalı ve güvenle korunmalı', () async {
      await coreDb.db.insert('sync_events', {
        'event_id': 'mut-omitted-1',
        'entity_type': 'sale',
        'entity_id': 'sale-omitted',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'total': 50}),
        'client_timestamp': 1000,
        'sync_state': 'PENDING',
        'base_revision': 0,
        'attempts': 0,
        'causal_sequence': 1,
      });

      // Sunucu 200 döner ancak results, conflicts ve rejected bomboştur (yanıt eksik/atlandı)
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [],
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

      final res = await processor.processOutbox();
      expect(res.transientErrorCount, 1);
      expect(res.syncedCount, 0);

      final row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-omitted-1'])).first;
      expect(row['sync_state'], 'TRANSIENT_ERROR');
      expect(row['attempts'], 1);
      expect(row['last_error'], 'unacknowledged_by_server');
    });
  });
}
