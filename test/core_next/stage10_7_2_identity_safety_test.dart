// test/core_next/stage10_7_2_identity_safety_test.dart
// SERENUT OS — STAGE 10.7.2 REGRESYON VE KİMLİK GÜVENLİĞİ TESTLERİ
//
// Senaryo 1: Kendi satışının pull event'i ikinci stok düşümüne yol açmamalı.
// Senaryo 2: Başka cihazın satışında aynı receipt_no bulunsa bile yabancı satışın stok düşümü atlanmamalı.
// Senaryo 3: Yerel ve sunucu satış UUID'leri farklıysa davranış açık ve güvenli olmalı.
// Senaryo 4: Aynı yabancı satış olayı iki kez geldiğinde stok yalnızca bir kez düşmeli.
// Senaryo 5: Aynı iade olayı iki kez geldiğinde stok yalnızca bir kez artmalı.
// Senaryo 6: İade olayı yanlışlıkla orijinal satışla eşleştirilmemeli.
// Senaryo 7: Olay uygulaması başarısız olduğunda sync_applied_events ve cursor tutarsız kalmamalı.
// Senaryo 8: Cihaz kimliği eksik olduğunda mevcut fail-safe davranışı korunmalı.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/sync_dtos.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.7.2 — Satış Kimliği ve Stok Bütünlüğü Güvenlik Testleri', () {
    late Directory tempDir;
    late String dbPath;
    late CoreAppDatabase coreDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_test_10_7_2_');
      dbPath = '${tempDir.path}/identity_safety.db';
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);

      // Başlangıç ürünü: 20 adet stok
      await coreDb.db.insert('products', {
        'id': 'prod-cay-1',
        'barcode': '8690005',
        'name': 'Doğu Karadeniz Çayı 1000g',
        'price_cents': 18000,
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

    test('10.7.2.1: Kendi satışının pull event\'i ikinci stok düşümüne yol açmamalı', () async {
      // Yerel kasanın kendi satışı: Kasa A
      await coreDb.db.insert('sales', {
        'id': 'sale-kasa-a-1',
        'receipt_no': 'REC-KASA-A-01',
        'subtotal_cents': 36000,
        'discount_cents': 0,
        'vat_total_cents': 7200,
        'total_cents': 36000,
        'paid_cents': 36000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEMP-A-1',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final change = SyncPullChange(
        mutationId: 'mut-pull-own-1',
        entityType: 'sale',
        entityId: 'sale-kasa-a-1',
        operation: 'UPSERT',
        revision: 10,
        deviceId: 'kasa-a',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'receipt_no': 'REC-KASA-A-01',
          'idempotency_key': 'IDEMP-A-1',
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 2}
          ]
        },
      );

      final result = await ingestion.ingestPull(SyncPullResponseDto(
        changes: [change],
        nextCursor: 10,
      ));

      expect(result.salesApplied, 1);
      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 20, reason: 'Kendi kasanın satışı pull edildiğinde stok ikinci kez düşmemelidir');

      final appliedEvents = await coreDb.db.query('sync_applied_events', where: 'id = ?', whereArgs: ['sale:sale-kasa-a-1']);
      expect(appliedEvents.length, 1);
    });

    test('10.7.2.2: Başka cihazın satışında aynı receipt_no bulunsa bile yabancı satışın stok düşümü atlanmamalı', () async {
      // Yerel Kasa A'da REC-COMMON-100 fiş numaralı bir satış olsun
      await coreDb.db.insert('sales', {
        'id': 'sale-local-common-1',
        'receipt_no': 'REC-COMMON-100',
        'subtotal_cents': 18000,
        'discount_cents': 0,
        'vat_total_cents': 3600,
        'total_cents': 18000,
        'paid_cents': 18000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'REC-COMMON-100', // Varsayılan fallback
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Başka cihaz (Kasa B) tesadüfen aynı formatta aynı receipt_no üretmiş
      final changeFromKasaB = SyncPullChange(
        mutationId: 'mut-b-foreign-100',
        entityType: 'sale',
        entityId: 'sale-kasa-b-foreign-1',
        operation: 'UPSERT',
        revision: 20,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'receipt_no': 'REC-COMMON-100', // AYNI FİŞ NUMARASI!
          'idempotency_key': 'REC-COMMON-100',
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 3}
          ]
        },
      );

      final result = await ingestion.ingestPull(SyncPullResponseDto(
        changes: [changeFromKasaB],
        nextCursor: 20,
      ));

      expect(result.salesApplied, 1);
      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      // Güvenlik doğrulaması: Yabancı satışın stok düşümü atlanmamalı, 20 - 3 = 17 olmalıdır!
      expect(prod['stock_quantity'], 17, reason: 'Fiş numarası yerelde çakışsa dahi yabancı kasanın satışı atlanmamalıdır (False-positive önlendi)');
    });

    test('10.7.2.3: Yerel ve sunucu satış UUID\'leri farklıysa davranış açık ve güvenli olmalı', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // 1. Durum: deviceId yabancı (kasa-b) ve entityId yerel veritabanında yok.
      // Açık ve güvenli davranış: Yabancı satış kabul edilip stok düşülmelidir.
      final changeForeign = SyncPullChange(
        mutationId: 'mut-diff-1',
        entityType: 'sale',
        entityId: 'server-foreign-uuid-888',
        operation: 'UPSERT',
        revision: 25,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 4}
          ]
        },
      );
      await ingestion.ingestPull(SyncPullResponseDto(changes: [changeForeign], nextCursor: 25));

      var prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 16, reason: 'Farklı UUID ve yabancı deviceId taşıyan satış stok düşmelidir');

      // 2. Durum: deviceId kendi cihazımız (kasa-a) ancak sunucu UUID\'si yereldeki ile uyuşmuyor.
      // Açık ve güvenli davranış: change.deviceId == localDeviceId olduğu için kendi kasanın satışı kabul edilir ve mükerrer stok düşülmez.
      final changeOwnDiffUuid = SyncPullChange(
        mutationId: 'mut-diff-2',
        entityType: 'sale',
        entityId: 'server-mapped-uuid-777',
        operation: 'UPSERT',
        revision: 26,
        deviceId: 'kasa-a', // Kendi cihazımız!
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 4}
          ]
        },
      );
      await ingestion.ingestPull(SyncPullResponseDto(changes: [changeOwnDiffUuid], nextCursor: 26));

      prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 16, reason: 'Kendi cihazımızdan gelen satış UUID farklı olsa dahi yerel kabul edilmeli ve stok mükerrer düşmemelidir');
    });

    test('10.7.2.4: Aynı yabancı satış olayı iki kez geldiğinde stok yalnızca bir kez düşmeli', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      final change = SyncPullChange(
        mutationId: 'mut-foreign-replay-1',
        entityType: 'sale',
        entityId: 'sale-replay-uuid-1',
        operation: 'UPSERT',
        revision: 30,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 5}
          ]
        },
      );

      // İlk pull: 20 -> 15 düşmeli
      await ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 30));
      var prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 15);

      // İkinci pull: Tekrar aynı change geliyor
      await ingestion.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 30));
      prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 15, reason: 'Replay durumunda sync_applied_events mükerrer stok düşüşünü engellemelidir');
    });

    test('10.7.2.5: Aynı iade olayı iki kez geldiğinde stok yalnızca bir kez artmalı', () async {
      // Önce stok 15'e düşmüş olsun
      await coreDb.db.update('products', {'stock_quantity': 15}, where: 'id = ?', whereArgs: ['prod-cay-1']);

      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');
      final changeRefund = SyncPullChange(
        mutationId: 'mut-ref-replay-1',
        entityType: 'refund',
        entityId: 'ref-replay-uuid-1',
        operation: 'UPSERT',
        revision: 35,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 2}
          ]
        },
      );

      // İlk pull: 15 + 2 = 17 olmalı
      await ingestion.ingestPull(SyncPullResponseDto(changes: [changeRefund], nextCursor: 35));
      var prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 17);

      // İkinci pull: Replay
      await ingestion.ingestPull(SyncPullResponseDto(changes: [changeRefund], nextCursor: 35));
      prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 17, reason: 'Replay iade olayında stok ikinci kez artmamalıdır');
    });

    test('10.7.2.6: İade olayı yanlışlıkla orijinal satışla eşleştirilmemeli', () async {
      // Yerelde orijinal bir satış mevcut: status = 'COMPLETED'
      await coreDb.db.insert('sales', {
        'id': 'sale-orig-target-1',
        'receipt_no': 'REC-ORIG-TARGET',
        'subtotal_cents': 18000,
        'discount_cents': 0,
        'vat_total_cents': 3600,
        'total_cents': 18000,
        'paid_cents': 18000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'REC-ORIG-TARGET',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Başka kasa (Kasa B) bu satışa ait bir iade işlemi yapmış
      final refundChange = SyncPullChange(
        mutationId: 'mut-foreign-ref-1',
        entityType: 'refund',
        entityId: 'ref-foreign-target-1',
        operation: 'UPSERT',
        revision: 40,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'sale_id': 'sale-orig-target-1', // Orijinal satış ID'si!
          'receipt_no': 'REC-ORIG-TARGET', // Orijinal satışın fiş no'su
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 1}
          ]
        },
      );

      final result = await ingestion.ingestPull(SyncPullResponseDto(
        changes: [refundChange],
        nextCursor: 40,
      ));

      expect(result.refundsApplied, 1);
      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      // Orijinal satışla iade karıştırılmamalı, yabancı iade stoğu 20 -> 21 artırmalıdır!
      expect(prod['stock_quantity'], 21, reason: 'Yabancı iade olayı yerel orijinal satış kaydıyla karıştırılıp atlanmamalıdır');
    });

    test('10.7.2.7: Olay uygulaması başarısız olduğunda sync_applied_events ve cursor tutarsız kalmamalı', () async {
      final ingestion = SyncV4PullIngestionService(coreDb, localDeviceId: 'kasa-a');

      // Geçerli bir satış ve ardından simüle edilmiş bozuk bir transaction senaryosu
      expect(
        () async {
          await coreDb.transaction((txn) async {
            await txn.insert('sync_applied_events', {
              'id': 'temp-corrupt',
              'entity_type': 'sale',
              'entity_id': 'temp',
              'revision': 99,
              'device_id': 'kasa-b',
              'product_id': null,
              'quantity_delta': 0,
              'applied_at': 1000,
            });
            throw StateError('simulated_failure_during_pull');
          });
        },
        throwsA(isA<StateError>()),
      );

      // sync_applied_events içinde yarım/artık kayıt kalmamalı
      final rows = await coreDb.db.query('sync_applied_events', where: 'id = ?', whereArgs: ['temp-corrupt']);
      expect(rows, isEmpty);

      final cursor = await ingestion.getSavedCursor();
      expect(cursor, 0);
    });

    test('10.7.2.8: Cihaz kimliği eksik olduğunda mevcut fail-safe davranışı korunmalı', () async {
      final ingestionNull = SyncV4PullIngestionService(coreDb, localDeviceId: null);
      final ingestionEmpty = SyncV4PullIngestionService(coreDb, localDeviceId: '   ');

      final change = SyncPullChange(
        mutationId: 'mut-fail-1',
        entityType: 'sale',
        entityId: 'sale-fail-1',
        operation: 'UPSERT',
        revision: 50,
        deviceId: 'kasa-b',
        createdAt: DateTime.now().toIso8601String(),
        payload: {
          'items': [
            {'product_id': 'prod-cay-1', 'quantity': 1}
          ]
        },
      );

      expect(
        () => ingestionNull.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 50)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('unidentified_local_device'))),
      );

      expect(
        () => ingestionEmpty.ingestPull(SyncPullResponseDto(changes: [change], nextCursor: 50)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('unidentified_local_device'))),
      );

      final prod = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-cay-1'])).first;
      expect(prod['stock_quantity'], 20);
    });
  });
}
