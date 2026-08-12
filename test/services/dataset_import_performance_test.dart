// test/services/dataset_import_performance_test.dart
// Integration tests for DatasetImportService batch transactions and strategy algorithms.

import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as ex;
import 'package:path/path.dart' hide equals;
import 'package:serenutos/domain/models/import_strategy.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_product_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager dbManager;
  late SqliteProductRepository productRepo;
  late DatasetImportService importService;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('dataset_perf_test');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory' ||
            methodCall.method == 'getApplicationSupportDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    // Delete existing test DB to ensure clean start
    final dbPath =
        join(await databaseFactory.getDatabasesPath(), 'serenut_pos.db');
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }

    dbManager = DatabaseManager();
    final gateway = DbGatewayImpl(dbManager);
    productRepo = SqliteProductRepository(gateway);
    importService = DatasetImportService(productRepo);
  });

  tearDownAll(() async {
    await dbManager.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    final db = await dbManager.getDatabase();
    await db.execute('DELETE FROM products');
    await db.execute('DELETE FROM sync_outbox_v4');
  });

  Uint8List createMockZip(List<Map<String, dynamic>> rowsData) {
    final excel = ex.Excel.createExcel();
    final sheet = excel['market_data_catalog'];
    excel.delete('Sheet1');

    sheet.appendRow([
      ex.TextCellValue('Barkod'),
      ex.TextCellValue('Urun Adi'),
      ex.TextCellValue('Kategori'),
      ex.TextCellValue('Marka'),
      ex.TextCellValue('Fiyat (TL)'),
      ex.TextCellValue('KDV Orani (%)'),
      ex.TextCellValue('Gorsel Linki'),
      ex.TextCellValue('Stok Miktari'),
    ]);

    for (final row in rowsData) {
      sheet.appendRow([
        ex.TextCellValue(row['barcode']),
        ex.TextCellValue(row['name']),
        ex.TextCellValue(row['category']),
        ex.TextCellValue(row['brand']),
        ex.DoubleCellValue(row['price']),
        ex.IntCellValue(row['vat']),
        ex.TextCellValue(row['imageUrl']),
        ex.IntCellValue(row['quantity']),
      ]);
    }

    final excelBytes = excel.save();
    final archive = Archive();
    archive.addFile(ArchiveFile(
        'market_data_catalog.xlsx', excelBytes!.length, excelBytes));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  group('DatasetImportService Performance and Strategy Tests', () {
    test('catalog import explicitly reactivates a soft-deleted product',
        () async {
      const barcode = '8690001112299';
      await productRepo.create(ProductEntity(
        id: barcode,
        name: 'Silinmiş Ürün',
        description: 'Eski marka',
        price: 10,
        quantity: 1,
        category: 'Eski',
      ));
      await productRepo.delete(barcode);

      final result = await importService.importFromZip(
        createMockZip([
          {
            'barcode': barcode,
            'name': 'Yeniden Aktarılan Ürün',
            'category': 'Yeni',
            'brand': 'Test',
            'price': 25.0,
            'vat': 20,
            'imageUrl': '',
            'quantity': 4,
          },
        ]),
        (_, __) {},
      );

      expect(result['success'], 1);
      final db = await dbManager.getDatabase();
      final row = (await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [barcode],
      ))
          .single;
      expect(row['is_active'], 1);
      expect(row['is_deleted'], 0);
      expect(row['deleted_at'], isNull);
      expect(row['quantity'], 4,
          reason: 'Tekrar import mevcut stok üzerine ekleme yapmamalı');
      expect(
        await db.query('products', where: 'id = ?', whereArgs: [barcode]),
        hasLength(1),
        reason: 'Aynı barkod ikinci bir ürün satırı oluşturmamalı',
      );

      final outbox = (await db.query(
        'sync_outbox_v4',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['product', barcode],
      ))
          .single;
      expect(outbox['operation'], 'UPSERT');
      final payload = jsonDecode(outbox['payload'] as String) as Map;
      expect(payload['reactivate_deleted'], isTrue);
      expect(payload['is_deleted'], 0);
    });

    test('zero-prefixed EAN-13 updates the existing UPC-A product', () async {
      const upc = '123456789012';
      const ean = '0123456789012';
      await productRepo.create(ProductEntity(
        id: upc,
        name: 'Mevcut Ürün',
        description: 'Eski marka',
        price: 10,
        quantity: 1,
        category: 'Eski',
      ));

      final result = await importService.importFromZip(
        createMockZip([
          {
            'barcode': ean,
            'name': 'Güncel Ürün',
            'category': 'Yeni',
            'brand': 'Yeni marka',
            'price': 25.0,
            'vat': 20,
            'imageUrl': '',
            'quantity': 4,
          },
        ]),
        (_, __) {},
      );

      expect(result['success'], 1);
      final db = await dbManager.getDatabase();
      final rows = await db.query(
        'products',
        where: 'id = ? OR id = ?',
        whereArgs: [upc, ean],
      );
      expect(rows, hasLength(1),
          reason: 'UPC-A ve sıfır önekli EAN-13 çift ürün oluşturmamalı');
      expect(rows.single['id'], upc);
      expect(rows.single['quantity'], 4);
      expect(rows.single['price'], 25.0);
    });

    test('equivalent UPC-A and EAN-13 rows in one file are deduplicated',
        () async {
      final result = await importService.importFromZip(
        createMockZip([
          {
            'barcode': '123456789012',
            'name': 'İlk Satır',
            'category': 'Test',
            'brand': 'Test',
            'price': 10.0,
            'vat': 20,
            'imageUrl': '',
            'quantity': 1,
          },
          {
            'barcode': '0123456789012',
            'name': 'Son Satır',
            'category': 'Test',
            'brand': 'Test',
            'price': 20.0,
            'vat': 20,
            'imageUrl': '',
            'quantity': 2,
          },
        ]),
        (_, __) {},
      );

      expect(result['success'], 1);
      final db = await dbManager.getDatabase();
      final rows = await db.query(
        'products',
        where: 'id = ? OR id = ?',
        whereArgs: ['123456789012', '0123456789012'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['name'], 'Son Satır');
      expect(rows.single['quantity'], 2);
    });

    test('DuplicateResolution.skip preserves existing details', () async {
      // 1. Pre-seed database with a product
      final initial = ProductEntity(
        id: '8690001112223',
        name: 'Initial Product',
        description: 'Initial Brand',
        price: 10.0,
        quantity: 5,
        category: 'Initial Category',
        vat: 8,
      );
      await productRepo.create(initial);

      // 2. Mock ZIP containing duplicate with different details
      final zipBytes = createMockZip([
        {
          'barcode': '8690001112223',
          'name': 'Imported Product',
          'category': 'Imported Category',
          'brand': 'Imported Brand',
          'price': 20.0,
          'vat': 18,
          'imageUrl': '',
          'quantity': 100,
        }
      ]);

      // 3. Import with skip resolution strategy
      final result = await importService.importFromZip(
        zipBytes,
        (p, msg) {},
        const ImportStrategy(duplicateResolution: DuplicateResolution.skip),
      );

      expect(result['success'], equals(0)); // skipped, not inserted or updated

      final prod = await productRepo.findById('8690001112223');
      expect(prod, isNotNull);
      expect(prod!.name, equals('Initial Product'));
      expect(prod.price, equals(10.0));
      expect(prod.quantity, equals(5));
    });

    test('DuplicateResolution.update overwrites fields', () async {
      // 1. Pre-seed database with a product
      final initial = ProductEntity(
        id: '8690001112224',
        name: 'Initial Product 2',
        description: 'Initial Brand 2',
        price: 15.0,
        quantity: 10,
        category: 'Initial Category 2',
        vat: 8,
      );
      await productRepo.create(initial);

      // 2. Mock ZIP containing duplicate with different details
      final zipBytes = createMockZip([
        {
          'barcode': '8690001112224',
          'name': 'Updated Product 2',
          'category': 'Updated Category 2',
          'brand': 'Updated Brand 2',
          'price': 25.0,
          'vat': 18,
          'imageUrl': 'https://example.com/updated.jpg',
          'quantity': 50,
        }
      ]);

      // 3. Import with update strategy
      final result = await importService.importFromZip(
        zipBytes,
        (p, msg) {},
        const ImportStrategy(duplicateResolution: DuplicateResolution.update),
      );

      expect(result['success'], equals(1));

      final prod = await productRepo.findById('8690001112224');
      expect(prod, isNotNull);
      expect(prod!.price, equals(25.0));
      expect(prod.quantity, equals(50));
      expect(prod.description, equals('Updated Brand 2'));

      final db = await dbManager.getDatabase();
      final mutations = await db.query(
        'sync_outbox_v4',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['product', '8690001112224'],
      );
      expect(mutations, hasLength(1));
      expect(mutations.single['operation'], equals('UPSERT'));
    });

    test('DuplicateResolution.merge accumulates stock', () async {
      // 1. Pre-seed database with a product
      final initial = ProductEntity(
        id: '8690001112225',
        name: 'Initial Product 3',
        description: 'Initial Brand 3',
        price: 10.0,
        quantity: 20,
        category: 'Initial Category 3',
        vat: 8,
      );
      await productRepo.create(initial);

      // 2. Mock ZIP containing duplicate
      final zipBytes = createMockZip([
        {
          'barcode': '8690001112225',
          'name': 'Initial Product 3',
          'category': 'Initial Category 3',
          'brand': 'Initial Brand 3',
          'price': 10.0,
          'vat': 8,
          'imageUrl': '',
          'quantity': 30,
        }
      ]);

      // 3. Import with merge strategy (accumulates stock: 20 + 30 = 50)
      await importService.importFromZip(
        zipBytes,
        (p, msg) {},
        const ImportStrategy(duplicateResolution: DuplicateResolution.merge),
      );

      final prod = await productRepo.findById('8690001112225');
      expect(prod, isNotNull);
      expect(prod!.quantity, equals(50));
    });

    test('deactivateMissing deactivates omitted items', () async {
      // 1. Pre-seed database with two products
      final p1 = ProductEntity(
        id: '8690001112226',
        name: 'Active Product 1',
        description: 'Brand 1',
        price: 10.0,
        quantity: 10,
        category: 'Category 1',
        vat: 8,
      );
      final p2 = ProductEntity(
        id: '8690001112227',
        name: 'Active Product 2',
        description: 'Brand 2',
        price: 12.0,
        quantity: 15,
        category: 'Category 2',
        vat: 8,
      );
      await productRepo.create(p1);
      await productRepo.create(p2);

      // 2. Mock ZIP containing only p1
      final zipBytes = createMockZip([
        {
          'barcode': '8690001112226',
          'name': 'Active Product 1',
          'category': 'Category 1',
          'brand': 'Brand 1',
          'price': 10.0,
          'vat': 8,
          'imageUrl': '',
          'quantity': 10,
        }
      ]);

      // 3. Import with deactivateMissing enabled
      await importService.importFromZip(
        zipBytes,
        (p, msg) {},
        const ImportStrategy(
          deactivateMissing: true,
          duplicateResolution: DuplicateResolution.update,
        ),
      );

      // Verify p1 is still active
      final activeList = await productRepo.findAll();
      expect(activeList, hasLength(1));
      expect(activeList.first.id, equals('8690001112226'));

      // Verify p2 is deactivated (is_active = 0)
      final db = await dbManager.getDatabase();
      final rows = await db
          .query('products', where: 'id = ?', whereArgs: ['8690001112227']);
      expect(rows, isNotEmpty);
      expect(rows.first['is_active'], equals(0));
    });
  });
}
