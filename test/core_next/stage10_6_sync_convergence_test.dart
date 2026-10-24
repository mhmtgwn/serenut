// test/core_next/stage10_6_sync_convergence_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/models/sync_dtos.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/schema_definitions.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart';

/// Sunucu tarafı transaction, idempotency ve replikasyon simülasyon motoru
class SimulatedSyncV4Server {
  final Map<String, int> products = {};
  final Map<String, Map<String, dynamic>> sales = {};
  final List<Map<String, dynamic>> movements = [];
  final List<Map<String, dynamic>> changes = [];
  int currentRevision = 0;

  void addProduct(String id, int initialQty) {
    products[id] = initialQty;
  }

  /// Sunucu `POST /api/v4/sync/push` akışı (PostgreSQL transaction simülasyonu)
  Map<String, dynamic> pushMutation({
    required String mutationId,
    required String deviceId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    bool simulateDbError = false,
  }) {
    // 1. Transaction savepoint başlangıcı
    final snapshotProducts = Map<String, int>.from(products);
    final snapshotSales = Map<String, Map<String, dynamic>>.from(sales);
    final snapshotMovements = List<Map<String, dynamic>>.from(movements);
    final snapshotChanges = List<Map<String, dynamic>>.from(changes);
    final snapshotRevision = currentRevision;

    try {
      if (simulateDbError) {
        throw StateError('db_connection_error_during_transaction');
      }

      // 2. mutation_id idempotency kontrolü
      final existingChange = changes.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['mutation_id'] == mutationId,
            orElse: () => null,
          );
      if (existingChange != null) {
        final prevPayload = existingChange['payload'] as Map<String, dynamic>;
        if (prevPayload.toString() != payload.toString()) {
          throw StateError('mutation_payload_conflict');
        }
        return {'status': 'ACK', 'revision': existingChange['revision']};
      }

      // 3. Domain materialization (upsertSale)
      if (entityType == 'sale') {
        if (sales.containsKey(entityId)) {
          final prior = sales[entityId]!;
          // Payload çakışma kontrolü
          final priorTotal = (prior['total_amount'] as num?)?.toDouble() ?? 0.0;
          final newTotal = (payload['total_amount'] as num?)?.toDouble() ?? 0.0;
          if ((priorTotal - newTotal).abs() > 0.05) {
            throw StateError('sale_payload_conflict');
          }
          final priorItems = prior['items'] as List;
          final newItems = payload['items'] as List;
          if (priorItems.length != newItems.length) {
            throw StateError('sale_payload_conflict');
          }
          for (int i = 0; i < priorItems.length; i++) {
            if (priorItems[i]['quantity'] != newItems[i]['quantity'] ||
                priorItems[i]['product_id'] != newItems[i]['product_id']) {
              throw StateError('sale_payload_conflict');
            }
          }
          return {'status': 'NOOP_IDEMPOTENT', 'revision': currentRevision};
        }

        // Satış ve kalemleri kaydet
        sales[entityId] = Map<String, dynamic>.from(payload);
        final items = (payload['items'] as List).cast<Map<String, dynamic>>();
        for (final item in items) {
          final prodId = item['product_id'] as String;
          final qty = (item['quantity'] as num).toInt();
          products[prodId] = (products[prodId] ?? 0) - qty;
          movements.add({
            'reference_id': entityId,
            'product_id': prodId,
            'delta': -qty,
            'type': 'sale',
          });
        }
      } else if (entityType == 'refund') {
        final items = (payload['items'] as List).cast<Map<String, dynamic>>();
        for (final item in items) {
          final prodId = item['product_id'] as String;
          final qty = (item['quantity'] as num).toInt();
          products[prodId] = (products[prodId] ?? 0) + qty;
          movements.add({
            'reference_id': entityId,
            'product_id': prodId,
            'delta': qty,
            'type': 'refund',
          });
        }
      }

      // 4. sync_v4_changes içine replikasyon kaydı yazma (aynı transaction)
      currentRevision++;
      final rev = currentRevision;
      changes.add({
        'revision': rev,
        'mutation_id': mutationId,
        'device_id': deviceId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': 'UPSERT',
        'payload': payload,
        'created_at': DateTime.now().toIso8601String(),
      });

      return {'status': 'COMMITTED', 'revision': rev};
    } catch (e) {
      // Transaction Rollback!
      products.clear();
      products.addAll(snapshotProducts);
      sales.clear();
      sales.addAll(snapshotSales);
      movements.clear();
      movements.addAll(snapshotMovements);
      changes.clear();
      changes.addAll(snapshotChanges);
      currentRevision = snapshotRevision;
      return {'status': 'REJECTED', 'error': e.toString()};
    }
  }

  /// Sunucu `GET /api/v4/sync/pull` akışı
  SyncPullResponseDto pull({required int cursor, int limit = 100}) {
    final available = changes.where((c) => (c['revision'] as int) > cursor).take(limit).toList();
    final dtoList = available.map((c) {
      return SyncPullChange(
        revision: c['revision'] as int,
        mutationId: c['mutation_id'] as String,
        deviceId: c['device_id'] as String,
        entityType: c['entity_type'] as String,
        entityId: c['entity_id'] as String,
        operation: c['operation'] as String,
        payload: c['payload'] as Map<String, dynamic>,
        createdAt: c['created_at'] as String,
      );
    }).toList();

    final nextCursor = dtoList.isNotEmpty ? dtoList.last.revision : cursor;
    return SyncPullResponseDto(
      changes: dtoList,
      nextCursor: nextCursor,
    );
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Stage 10.6 — Çok Kasalı Stok Yakınsaması ve Senkronizasyon Adli Testleri', () {
    late SimulatedSyncV4Server server;
    late CoreAppDatabase dbKasaA;
    late CoreAppDatabase dbKasaB;
    late SyncV4PullIngestionService syncKasaA;
    late SyncV4PullIngestionService syncKasaB;

    int _counter = 0;

    setUp(() async {
      server = SimulatedSyncV4Server();
      server.addProduct('p-zeytin', 10);

      _counter++;
      dbKasaA = await CoreAppDatabase.open(
        inMemoryOrCustomPath: 'file:mem_kasa_a_$_counter?mode=memory&cache=shared',
      );
      dbKasaB = await CoreAppDatabase.open(
        inMemoryOrCustomPath: 'file:mem_kasa_b_$_counter?mode=memory&cache=shared',
      );

      // Kasa A başlangıç stoğu
      await dbKasaA.db.insert('products', {
        'id': 'p-zeytin',
        'barcode': '869001',
        'name': 'Gemlik Zeytini 1kg',
        'price_cents': 15000,
        'vat_rate': 10,
        'unit': 'piece',
        'stock_quantity': 10,
        'critical_threshold': 5,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Kasa B başlangıç stoğu
      await dbKasaB.db.insert('products', {
        'id': 'p-zeytin',
        'barcode': '869001',
        'name': 'Gemlik Zeytini 1kg',
        'price_cents': 15000,
        'vat_rate': 10,
        'unit': 'piece',
        'stock_quantity': 10,
        'critical_threshold': 5,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      syncKasaA = SyncV4PullIngestionService(dbKasaA, localDeviceId: 'kasa-a');
      syncKasaB = SyncV4PullIngestionService(dbKasaB, localDeviceId: 'kasa-b');
    });

    tearDown(() async {
      await dbKasaA.close();
      await dbKasaB.close();
    });

    Future<int> getStock(CoreAppDatabase db, String prodId) async {
      final rows = await db.query('products', where: 'id = ?', whereArgs: [prodId]);
      return (rows.first['stock_quantity'] as num).toInt();
    }

    test('Test A — Normal satış yayılımı: Kasa A satar, Kasa B pull eder, iki kasa 8 adette buluşur', () async {
      // 1. Kasa A yerel olarak 2 adet satar
      await dbKasaA.db.execute('UPDATE products SET stock_quantity = stock_quantity - 2 WHERE id = "p-zeytin"');
      expect(await getStock(dbKasaA, 'p-zeytin'), 8);

      // 2. Kasa A satış mutasyonunu sunucuya push eder
      final pushResult = server.pushMutation(
        mutationId: 'mut-sale-001',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-001',
        payload: {
          'total_amount': 300.0,
          'paid_amount': 300.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 2, 'unit_price': 150.0}
          ],
        },
      );
      expect(pushResult['status'], 'COMMITTED');
      expect(server.products['p-zeytin'], 8);

      // 3. Kasa B pull yapar
      final pullB = server.pull(cursor: 0);
      expect(pullB.changes.length, 1);
      final resB = await syncKasaB.ingestPull(pullB);
      expect(resB.salesApplied, 1);
      expect(await getStock(dbKasaB, 'p-zeytin'), 8);

      // 4. Kasa A da pull yapar (kendi satışını tekrar alsa bile mükerrer düşmemeli!)
      final pullA = server.pull(cursor: 0);
      final resA = await syncKasaA.ingestPull(pullA);
      expect(resA.salesApplied, 1);
      expect(await getStock(dbKasaA, 'p-zeytin'), 8, reason: 'Kasa A kendi satışını tekrar uygulayıp 6 adede düşürmemeli');
    });

    test('Test B — İade yayılımı: Kasa A 3 satıp 1 iade eder; Kasa B pull edince nihai stok 8 olur', () async {
      // Satış: 3 adet düşer
      server.pushMutation(
        mutationId: 'mut-sale-002',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-002',
        payload: {
          'total_amount': 450.0,
          'paid_amount': 450.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 3, 'unit_price': 150.0}
          ],
        },
      );
      // İade: 1 adet geri artar
      server.pushMutation(
        mutationId: 'mut-ref-001',
        deviceId: 'kasa-a',
        entityType: 'refund',
        entityId: 'ref-001',
        payload: {
          'sale_id': 'sale-002',
          'refund_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 1}
          ],
        },
      );
      expect(server.products['p-zeytin'], 8);

      // Kasa B olayları pull eder
      final pullB = server.pull(cursor: 0);
      expect(pullB.changes.length, 2);
      await syncKasaB.ingestPull(pullB);
      expect(await getStock(dbKasaB, 'p-zeytin'), 8);

      // Aynı iade tekrar pull edilirse mükerrer stok artışı olmamalıdır
      await syncKasaB.ingestPull(pullB);
      expect(await getStock(dbKasaB, 'p-zeytin'), 8);
    });

    test('Test C — Yinelenen push: Aynı satış aynı id ve payload ile 2 kez gönderilirse stok ikinci kez düşmez', () async {
      final salePayload = {
        'total_amount': 300.0,
        'paid_amount': 300.0,
        'payment_method': 'cash',
        'items': [
          {'product_id': 'p-zeytin', 'quantity': 2, 'unit_price': 150.0}
        ],
      };

      final res1 = server.pushMutation(
        mutationId: 'mut-sale-dup',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-dup',
        payload: salePayload,
      );
      expect(res1['status'], 'COMMITTED');
      expect(server.products['p-zeytin'], 8);

      // İkinci gönderim (zaman aşımı / retry)
      final res2 = server.pushMutation(
        mutationId: 'mut-sale-dup',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-dup',
        payload: salePayload,
      );
      expect(res2['status'], 'ACK');
      expect(server.products['p-zeytin'], 8, reason: 'Stok ikinci kez eksilmemelidir');
      expect(server.movements.length, 1, reason: 'Tek bir mantıksal hareket kaydı bulunmalıdır');
    });

    test('Test D — Payload çakışması: Aynı satış id ile değiştirilmiş payload gönderilirse açıkça reddedilir', () async {
      final res1 = server.pushMutation(
        mutationId: 'mut-sale-orig',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-conflict',
        payload: {
          'total_amount': 300.0,
          'paid_amount': 300.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 2, 'unit_price': 150.0}
          ],
        },
      );
      expect(res1['status'], 'COMMITTED');
      expect(server.products['p-zeytin'], 8);

      // Aynı sale_id fakat 3 adetlik değiştirilmiş payload
      final res2 = server.pushMutation(
        mutationId: 'mut-sale-altered',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-conflict',
        payload: {
          'total_amount': 450.0,
          'paid_amount': 450.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 3, 'unit_price': 150.0}
          ],
        },
      );
      expect(res2['status'], 'REJECTED');
      expect(res2['error'], contains('sale_payload_conflict'));
      expect(server.products['p-zeytin'], 8, reason: 'İlk satışın stok etkisi korunmalı, ikinci hareket yazılmamalıdır');
    });

    test('Test E — Çok satırlı satış: Aynı ürün 2 ayrı satırda satılırsa toplam miktar doğru düşer', () async {
      server.pushMutation(
        mutationId: 'mut-sale-multi',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-multi',
        payload: {
          'total_amount': 750.0,
          'paid_amount': 750.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 2, 'unit_price': 150.0},
            {'product_id': 'p-zeytin', 'quantity': 3, 'unit_price': 150.0},
          ],
        },
      );
      // 10 - 2 - 3 = 5
      expect(server.products['p-zeytin'], 5);

      final pullB = server.pull(cursor: 0);
      await syncKasaB.ingestPull(pullB);
      expect(await getStock(dbKasaB, 'p-zeytin'), 5);
    });

    test('Test F — Transaction rollback: Hata anında satış, hareket ve log birlikte geri alınır', () async {
      final res = server.pushMutation(
        mutationId: 'mut-fail',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-fail',
        payload: {
          'total_amount': 150.0,
          'paid_amount': 150.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 1, 'unit_price': 150.0}
          ],
        },
        simulateDbError: true,
      );
      expect(res['status'], 'REJECTED');
      expect(server.products['p-zeytin'], 10, reason: 'Stok rollback olmalıdır');
      expect(server.sales.containsKey('sale-fail'), isFalse);
      expect(server.movements.isEmpty, isTrue);
      expect(server.changes.isEmpty, isTrue);
    });

    test('Test G — Sayfalı pull ve retry: Parçalı sayfalama ve tekrar istekte veri kaybı ve mükerrerlik olmaz', () async {
      // 5 adet satış oluştur
      for (int i = 1; i <= 5; i++) {
        server.pushMutation(
          mutationId: 'mut-batch-$i',
          deviceId: 'kasa-a',
          entityType: 'sale',
          entityId: 'sale-batch-$i',
          payload: {
            'total_amount': 150.0,
            'paid_amount': 150.0,
            'payment_method': 'cash',
            'items': [
              {'product_id': 'p-zeytin', 'quantity': 1, 'unit_price': 150.0}
            ],
          },
        );
      }
      expect(server.products['p-zeytin'], 5);

      // Sayfa boyutu 2 ile pull yap
      final p1 = server.pull(cursor: 0, limit: 2);
      expect(p1.changes.length, 2);
      await syncKasaB.ingestPull(p1);
      expect(await getStock(dbKasaB, 'p-zeytin'), 8);

      // Ağ tekrarı: p1 tekrar alınırsa
      await syncKasaB.ingestPull(p1);
      expect(await getStock(dbKasaB, 'p-zeytin'), 8);

      // p2 çekilir
      final p2 = server.pull(cursor: p1.nextCursor, limit: 2);
      expect(p2.changes.length, 2);
      await syncKasaB.ingestPull(p2);
      expect(await getStock(dbKasaB, 'p-zeytin'), 6);

      // p3 çekilir (kalan 1 satış)
      final p3 = server.pull(cursor: p2.nextCursor, limit: 2);
      expect(p3.changes.length, 1);
      await syncKasaB.ingestPull(p3);
      expect(await getStock(dbKasaB, 'p-zeytin'), 5);
    });

    test('Test H — Snapshot ve olay sırası: Eski snapshot yeni stok hareketini ezmez', () async {
      // 1. Kasa B'ye rev 105 ile 2 adetlik satış gelir -> stok 8'e iner
      final saleChange = SyncPullChange(
        revision: 105,
        mutationId: 'mut-rev-105',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-105',
        operation: 'UPSERT',
        payload: {
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 2}
          ]
        },
        createdAt: DateTime.now().toIso8601String(),
      );
      await syncKasaB.ingestPull(SyncPullResponseDto(changes: [saleChange], nextCursor: 105));
      expect(await getStock(dbKasaB, 'p-zeytin'), 8);

      // 2. Şimdi gecikmiş, eski bir ürün snapshot'ı (rev 100, stok 10) gelir
      final oldSnapshotChange = SyncPullChange(
        revision: 100,
        mutationId: 'mut-snap-100',
        deviceId: 'server',
        entityType: 'product',
        entityId: 'p-zeytin',
        operation: 'UPSERT',
        payload: {
          'stock_quantity': 10,
          'name': 'Gemlik Zeytini 1kg',
        },
        createdAt: DateTime.now().toIso8601String(),
      );
      await syncKasaB.ingestPull(SyncPullResponseDto(changes: [oldSnapshotChange], nextCursor: 105));

      // Kasa B'deki stok 10'a geri sıçramamalı, 8 olarak kalmalıdır!
      expect(await getStock(dbKasaB, 'p-zeytin'), 8, reason: 'Eski katalog snapshot yeni satış düşümünü ezmemelidir');
    });

    test('Test I — Eşzamanlı çevrimdışı satış: İki kasa bağımsız satar ve senkronize olunca negatif stokta deterministik birleşir', () async {
      // Başlangıç: 5 adet
      server.products['p-zeytin'] = 5;
      await dbKasaA.db.execute('UPDATE products SET stock_quantity = 5 WHERE id = "p-zeytin"');
      await dbKasaB.db.execute('UPDATE products SET stock_quantity = 5 WHERE id = "p-zeytin"');

      // Kasa A çevrimdışı 4 adet satar (yerel stok = 1)
      await dbKasaA.db.execute('UPDATE products SET stock_quantity = 1 WHERE id = "p-zeytin"');
      // Kasa B çevrimdışı 3 adet satar (yerel stok = 2)
      await dbKasaB.db.execute('UPDATE products SET stock_quantity = 2 WHERE id = "p-zeytin"');

      // İki kasa da sunucuya push yapar
      server.pushMutation(
        mutationId: 'mut-offline-a',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-offline-a',
        payload: {
          'total_amount': 600.0,
          'paid_amount': 600.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 4, 'unit_price': 150.0}
          ],
        },
      );
      server.pushMutation(
        mutationId: 'mut-offline-b',
        deviceId: 'kasa-b',
        entityType: 'sale',
        entityId: 'sale-offline-b',
        payload: {
          'total_amount': 450.0,
          'paid_amount': 450.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 3, 'unit_price': 150.0}
          ],
        },
      );
      // Sunucu 5 - 4 - 3 = -2
      expect(server.products['p-zeytin'], -2);

      // Kasa A pull yapar (Kasa B'nin 3 adetlik satışını alır)
      final pullA = server.pull(cursor: 0);
      await syncKasaA.ingestPull(pullA);
      // Kasa A: 1 - 3 = -2
      expect(await getStock(dbKasaA, 'p-zeytin'), -2);

      // Kasa B pull yapar (Kasa A'nın 4 adetlik satışını alır)
      final pullB = server.pull(cursor: 0);
      await syncKasaB.ingestPull(pullB);
      // Kasa B: 2 - 4 = -2
      expect(await getStock(dbKasaB, 'p-zeytin'), -2);

      // Her iki kasa ve sunucu -2 nihai stokta deterministik olarak birleşir
      expect(await getStock(dbKasaA, 'p-zeytin'), await getStock(dbKasaB, 'p-zeytin'));
    });

    test('Test J — Bootstrap ardından incremental pull: Bootstrap sonrası hareketler mükerrer düşmez', () async {
      // 1. Kasa B sıfırdan bootstrap alır (rev 50 cursor ile stok 10)
      final bootstrapDto = SyncBootstrapResponseDto(
        changes: [
          SyncPullChange(
            revision: 50,
            mutationId: 'bootstrap-prod',
            deviceId: 'server',
            entityType: 'product',
            entityId: 'p-zeytin',
            operation: 'UPSERT',
            payload: {'stock_quantity': 10, 'name': 'Gemlik Zeytini 1kg'},
            createdAt: DateTime.now().toIso8601String(),
          )
        ],
        nextCursor: 50,
      );
      await syncKasaB.ingestBootstrap(bootstrapDto);
      expect(await getStock(dbKasaB, 'p-zeytin'), 10);
      expect(await syncKasaB.getSavedCursor(), 50);

      // 2. Ardından sunucuda rev 51 olarak 2 adetlik yeni bir satış gerçekleşir
      server.currentRevision = 50;
      server.pushMutation(
        mutationId: 'mut-post-bootstrap',
        deviceId: 'kasa-a',
        entityType: 'sale',
        entityId: 'sale-post-bootstrap',
        payload: {
          'total_amount': 300.0,
          'paid_amount': 300.0,
          'payment_method': 'cash',
          'items': [
            {'product_id': 'p-zeytin', 'quantity': 2, 'unit_price': 150.0}
          ],
        },
      );

      // 3. Kasa B cursor 50 üzerinden incremental pull yapar
      final incPull = server.pull(cursor: 50);
      expect(incPull.changes.length, 1);
      expect(incPull.changes.first.revision, 51);

      await syncKasaB.ingestPull(incPull);
      expect(await getStock(dbKasaB, 'p-zeytin'), 8);
      expect(await syncKasaB.getSavedCursor(), 51);
    });
  });
}
