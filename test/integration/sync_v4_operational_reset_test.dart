import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/data_reset_service.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sync_v4_legacy_snapshot_v1': true,
      'sync_v4_unsynced_product_recovery_v1': true,
    });
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
    manager = DatabaseManager();
    await manager.close();
  });

  tearDown(() async {
    await manager.close();
    DatabaseManager.overrideDatabasePath = null;
  });

  test('server reset revision atomically clears local data and stale outbox',
      () async {
    final db = await manager.getDatabase();
    await db.insert('products', {
      'id': 'old-product',
      'name': 'Eski ürün',
      'price': 10,
      'quantity': 1,
      'category': 'Test',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 7});
    await db.insert('sync_outbox_v4', {
      'mutation_id': 'stale-mutation',
      'entity_type': 'product',
      'entity_id': 'old-product',
      'operation': 'UPSERT',
      'payload': '{}',
      'state': 'PENDING',
      'attempts': 0,
      'created_at': '2026-01-01T00:00:00Z',
    });

    final api = ApiClient();
    api.mockHandler = (request) {
      expect(request.url.path, endsWith('/api/v4/sync/operational-reset'));
      return const ApiResponse(
        statusCode: 200,
        headers: {},
        body: '{"success":true,"reset_revision":88}',
      );
    };
    final service = SyncV4Service(
      api,
      deviceActivationIdResolver: () async => 'activation-1',
      deviceIdResolver: () async => 'installation-1',
      productImageCleaner: () async {},
    );

    expect(await service.resetOperationalData(), 88);
    expect(await db.query('products'), isEmpty);
    expect(await db.query('sync_outbox_v4'), isEmpty);
    expect((await db.query('sync_cursor_v4')).single['cursor'], 88);
  });

  test('reset journal barrier runs before post-reset changes', () async {
    final db = await manager.getDatabase();
    await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 7});
    await db.insert('products', {
      'id': 'old-product',
      'name': 'Eski ürün',
      'price': 10,
      'quantity': 1,
      'category': 'Test',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });

    final api = ApiClient();
    api.mockHandler = (request) {
      if (request.url.path.endsWith('/api/v4/sync/pull')) {
        return const ApiResponse(
          statusCode: 200,
          headers: {},
          body: '''{"next_cursor":9,"changes":[
            {"entity_type":"system_reset","entity_id":"reset-1","operation":"UPSERT","payload":{"scope":"operational"}},
            {"entity_type":"product","entity_id":"new-product","operation":"UPSERT","payload":{"name":"Yeni ürün","price":20,"quantity":2,"category":"Test","is_active":1,"created_at":"2026-01-02T00:00:00Z","updated_at":"2026-01-02T00:00:00Z"}}
          ]}''',
        );
      }
      throw StateError('Unexpected request: ${request.url}');
    };
    final result = await SyncV4Service(
      api,
      deviceActivationIdResolver: () async => 'activation-1',
      deviceIdResolver: () async => 'installation-1',
      productImageCleaner: () async {},
    ).sync();

    expect(result.success, isTrue);
    expect(
        await db.query('products', where: 'id=?', whereArgs: ['old-product']),
        isEmpty);
    expect(
        await db.query('products', where: 'id=?', whereArgs: ['new-product']),
        hasLength(1));
    expect((await db.query('sync_cursor_v4')).single['cursor'], 9);
  });

  test('catalog reset hides products but preserves operational history',
      () async {
    final db = await manager.getDatabase();
    await db.insert('products', {
      'id': 'old-product',
      'name': 'Eski ürün',
      'price': 10,
      'quantity': 1,
      'category': 'Test',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 7});
    await db.insert('sync_outbox_v4', {
      'mutation_id': 'stale-product-mutation',
      'entity_type': 'product',
      'entity_id': 'old-product',
      'operation': 'UPSERT',
      'payload': '{}',
      'state': 'PENDING',
      'attempts': 0,
      'created_at': '2026-01-01T00:00:00Z',
    });

    final api = ApiClient();
    api.mockHandler = (request) {
      expect(request.url.path, endsWith('/api/v4/sync/catalog-reset'));
      return const ApiResponse(
        statusCode: 200,
        headers: {},
        body: '{"success":true,"reset_revision":91}',
      );
    };
    var catalogSourceReset = false;
    final service = SyncV4Service(
      api,
      deviceActivationIdResolver: () async => 'activation-1',
      deviceIdResolver: () async => 'installation-1',
      productImageCleaner: () async {},
      catalogSourceResetter: () async => catalogSourceReset = true,
    );

    expect(await service.resetProductCatalog(), 91);
    final product = (await db.query('products')).single;
    expect(product['is_active'], 0);
    expect(product['is_deleted'], 1);
    expect(await db.query('sync_outbox_v4'), isEmpty);
    expect((await db.query('sync_cursor_v4')).single['cursor'], 91);
    expect(catalogSourceReset, isTrue);
  });

  test('remote catalog reset also detaches the mounted catalog source',
      () async {
    final db = await manager.getDatabase();
    await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 7});
    await db.insert('products', {
      'id': 'old-product',
      'name': 'Eski ürün',
      'price': 10,
      'quantity': 1,
      'category': 'Test',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });

    final api = ApiClient();
    api.mockHandler = (request) {
      if (request.url.path.endsWith('/api/v4/sync/pull')) {
        return const ApiResponse(
          statusCode: 200,
          headers: {},
          body: '''{"next_cursor":8,"changes":[
            {"entity_type":"system_reset","entity_id":"catalog-reset-1","operation":"UPSERT","payload":{"scope":"catalog"}}
          ]}''',
        );
      }
      throw StateError('Unexpected request: ${request.url}');
    };
    var catalogSourceReset = false;
    final result = await SyncV4Service(
      api,
      deviceActivationIdResolver: () async => 'activation-1',
      deviceIdResolver: () async => 'installation-1',
      productImageCleaner: () async {},
      catalogSourceResetter: () async => catalogSourceReset = true,
    ).sync();

    expect(result.success, isTrue);
    expect(catalogSourceReset, isTrue);
    final product = (await db.query('products')).single;
    expect(product['is_active'], 0);
    expect(product['is_deleted'], 1);
    expect((await db.query('sync_cursor_v4')).single['cursor'], 8);
  });

  test('full cleanup removes imported product image directory', () async {
    final support = await Directory.systemTemp.createTemp('serenut-reset-');
    addTearDown(() => support.delete(recursive: true));
    final images =
        Directory('${support.path}${Platform.pathSeparator}product_images');
    await images.create();
    await File('${images.path}${Platform.pathSeparator}123.jpg')
        .writeAsString('image');

    await DataResetService.clearProductImages(supportDirectory: support);

    expect(await images.exists(), isFalse);
  });
}
