// test/core_next/customer_balance_polarity_convergence_test.dart
// SERENUT OS — ARCHITECTURAL REPAIR PHASE 1
// Customer Balance Polarity & Sync V4 Convergence Test
// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/core_next/domain/models/sync_dtos.dart';
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/sync/sync_v4_pull_ingestion_service.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FAZ 1: Müşteri Bakiye Polaritesi ve Sync V4 Cari Mutabakatı', () {
    late CoreAppDatabase coreDb;
    late SyncV4PullIngestionService pullService;
    late CoreNextCustomerRepository customerRepo;

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      pullService = SyncV4PullIngestionService(coreDb, localDeviceId: 'local-pos-1');
      customerRepo = CoreNextCustomerRepository(coreDb.db);
    });

    tearDown(() async {
      await coreDb.close();
    });

    test('1.1 Sunucudan Gelen Pozitif Borç (+500 TL) İstemcide Negatif Cari Bakiyeye (-50000 kuruş) Dönüşmelidir', () async {
      // Sunucu (schema_v72.sql / bi.controller.ts) alacaklı perspektifindedir:
      // balance = debt_amount - paid_amount = +500.00 TL (Müşteri şirkete 500 TL borçludur).
      final change = SyncPullChange(
        revision: 10,
        mutationId: 'mut-cust-1',
        deviceId: 'server-sync',
        entityType: 'customer',
        entityId: 'cust-ahmet-1',
        operation: 'UPSERT',
        payload: {
          'id': 'cust-ahmet-1',
          'name': 'Ahmet Yılmaz',
          'phone': '05551112233',
          'balance': 500.00, // 500 TL borç
          'credit_limit': 2000.00,
          'status': 'active',
          'is_deleted': 0,
        },
        createdAt: '2026-10-25T12:00:00Z',
      );

      final result = await pullService.ingestPull(SyncPullResponseDto(
        changes: [change],
        nextCursor: 10,
      ));
      expect(result.customersApplied, equals(1));

      // Veritabanı doğrudan kuruş sorgusu
      final rows = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust-ahmet-1']);
      expect(rows, isNotEmpty);
      expect(rows.first['balance_cents'], equals(-50000), reason: '500 TL borç -50000 kuruş olmalıdır');

      // Repository ve UI Entity dönüşümü
      final entity = await customerRepo.findById('cust-ahmet-1');
      expect(entity, isNotNull);
      expect(entity!.balance, equals(-500.0), reason: 'CustomerEntity.balance -500.0 olmalıdır');

      // UI Polarity Kuralı Kontrolü:
      // Presentation katmanındaki tüm widget'lar (isDebt = balance < 0) kuralını uygular.
      final isDebt = entity.balance < -0.009;
      expect(isDebt, isTrue, reason: 'Borçlu müşteri UI üzerinde kırmızı/borçlu olarak algılanmalıdır');
    });

    test('1.2 Sunucudan Gelen Negatif Avans/Alacak (-200 TL) İstemcide Pozitif Cari Bakiyeye (+20000 kuruş) Dönüşmelidir', () async {
      // Sunucuda balance = -200.00 TL (Müşteri fazla ödeme yapmıştır veya avans vermiştir).
      final change = SyncPullChange(
        revision: 11,
        mutationId: 'mut-cust-2',
        deviceId: 'server-sync',
        entityType: 'customer',
        entityId: 'cust-ayse-2',
        operation: 'UPSERT',
        payload: {
          'id': 'cust-ayse-2',
          'name': 'Ayşe Kaya',
          'phone': '05552223344',
          'balance': -200.00, // 200 TL avans/alacak
          'credit_limit': 1000.00,
          'status': 'active',
          'is_deleted': 0,
        },
        createdAt: '2026-10-25T12:00:00Z',
      );

      final result = await pullService.ingestPull(SyncPullResponseDto(
        changes: [change],
        nextCursor: 11,
      ));
      expect(result.customersApplied, equals(1));

      final rows = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust-ayse-2']);
      expect(rows.first['balance_cents'], equals(20000), reason: '200 TL avans +20000 kuruş olmalıdır');

      final entity = await customerRepo.findById('cust-ayse-2');
      expect(entity!.balance, equals(200.0));

      final isDebt = entity.balance < -0.009;
      expect(isDebt, isFalse, reason: 'Alacaklı müşteri yeşil/alacaklı olarak algılanmalıdır');
    });

    test('1.3 Yerelde Bekleyen (Unreflected) Vadeli Satış (-100 TL) Sunucu Bakiyesiyle (-500 TL) Toplanarak -600 TL Olmalıdır', () async {
      // Kasa çevrimdışıyken müşteriye 100 TL veresiye satış yapılmış ve sync_events kuyruğunda beklemektedir:
      await coreDb.db.insert('sync_events', {
        'event_id': 'ev-sale-1',
        'entity_type': 'sale',
        'entity_id': 'sale-101',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({
          'id': 'sale-101',
          'customer_id': 'cust-ahmet-1',
          'total_amount': 100.00,
          'paid_amount': 0.0,
          'debt_amount': 100.00,
        }),
        'client_timestamp': 1792000500,
        'sync_state': 'PENDING',
        'base_revision': 0,
      });

      // Şimdi sunucudan müşterinin snapshot'ı çekilir (Sunucu henüz bu satışı görmemiştir: balance: 500.00 TL)
      final change = SyncPullChange(
        revision: 15,
        mutationId: 'mut-cust-1-refresh',
        deviceId: 'server-sync',
        entityType: 'customer',
        entityId: 'cust-ahmet-1',
        operation: 'UPSERT',
        payload: {
          'id': 'cust-ahmet-1',
          'name': 'Ahmet Yılmaz',
          'balance': 500.00, // Sunucu tabanı: 500 TL borç
          'status': 'active',
          'is_deleted': 0,
        },
        createdAt: '2026-10-25T12:00:00Z',
      );

      final result = await pullService.ingestPull(SyncPullResponseDto(
        changes: [change],
        nextCursor: 15,
      ));
      expect(result.customersApplied, equals(1));

      // Beklenen Bakiye: Sunucu (-50000 kuruş) + Yerel Unreflected (-10000 kuruş) = -60000 kuruş (-600.00 TL)
      final rows = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust-ahmet-1']);
      expect(rows.first['balance_cents'], equals(-60000), reason: 'Kasadaki yerel vadeli satış sunucudan gelen snapshot tarafından ezilmemelidir');

      final entity = await customerRepo.findById('cust-ahmet-1');
      expect(entity!.balance, equals(-600.0));
    });

    test('1.4 Yerelde Bekleyen Tahsilat (+150 TL) Sunucu Bakiyesiyle (-500 TL) Toplanarak -350 TL Olmalıdır', () async {
      // Müşteri kasaya 150 TL borç ödemiş ve outbox kuyruğunda PENDING olarak durmaktadır:
      await coreDb.db.insert('sync_events', {
        'event_id': 'ev-coll-1',
        'entity_type': 'financial_transaction',
        'entity_id': 'ft-101',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({
          'id': 'ft-101',
          'type': 'collection',
          'customer_id': 'cust-mehmet-1',
          'amount': 150.00,
          'paid_amount': 150.00,
        }),
        'client_timestamp': 1792000500,
        'sync_state': 'PENDING',
        'base_revision': 0,
      });

      // Sunucudan müşterinin snapshot'ı çekilir (balance: 500.00 TL borç)
      final change = SyncPullChange(
        revision: 20,
        mutationId: 'mut-cust-m-refresh',
        deviceId: 'server-sync',
        entityType: 'customer',
        entityId: 'cust-mehmet-1',
        operation: 'UPSERT',
        payload: {
          'id': 'cust-mehmet-1',
          'name': 'Mehmet Demir',
          'balance': 500.00,
          'status': 'active',
          'is_deleted': 0,
        },
        createdAt: '2026-10-25T12:00:00Z',
      );

      await pullService.ingestPull(SyncPullResponseDto(
        changes: [change],
        nextCursor: 20,
      ));

      // Beklenen: -50000 + 15000 = -35000 kuruş (-350.00 TL borç)
      final rows = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust-mehmet-1']);
      expect(rows.first['balance_cents'], equals(-35000), reason: 'Kasadaki tahsilat sunucu bakiye çekiminde hesaba katılmalıdır');

      final entity = await customerRepo.findById('cust-mehmet-1');
      expect(entity!.balance, equals(-350.0));
    });
  });
}
