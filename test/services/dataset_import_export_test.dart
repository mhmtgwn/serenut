// test/services/dataset_import_export_test.dart
// Unit and integration tests for DatasetImportService import and export pipelines.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as ex;
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('dataset_import_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('DatasetImportService Tests', () {
    late InMemoryProductRepository productRepo;
    late DatasetImportService importService;

    setUp(() {
      productRepo = InMemoryProductRepository();
      importService = DatasetImportService(productRepo);
      // Clear in-memory db before each test
      InMemoryDb.products.clear();
    });

    test('Export and Import End-to-End Pipeline', () async {
      // 1. Seed repository with some products
      final p1 = ProductEntity(
        id: '8690504090106',
        name: 'Test Product 1',
        description: 'Test Brand 1',
        price: 15.5,
        quantity: 42,
        category: 'Test Category 1',
        vat: 8,
        imageUrl: 'https://example.com/test1.jpg',
      );
      final p2 = ProductEntity(
        id: '8692562041205',
        name: 'Test Product 2',
        description: 'Test Brand 2',
        price: 45.0,
        quantity: 0,
        category: 'Test Category 2',
        vat: 18,
        imageUrl: 'https://example.com/test2.jpg',
      );

      await productRepo.create(p1);
      await productRepo.create(p2);

      // 2. Export catalog to ZIP
      final zipProgress = <double>[];
      final zipBytes =
          await importService.exportToZip((p) => zipProgress.add(p));

      expect(zipProgress, isNotEmpty);
      expect(zipProgress.last, equals(1.0));
      expect(zipBytes, isNotEmpty);

      // 3. Verify ZIP contents structure
      final archive = ZipDecoder().decodeBytes(zipBytes);
      ArchiveFile? excelFile;
      for (final file in archive) {
        if (file.name == 'market_data_catalog.xlsx') {
          excelFile = file;
        }
      }
      expect(excelFile, isNotNull);

      // 4. Clear repository to test import
      InMemoryDb.products.clear();
      expect(await productRepo.findAll(), isEmpty);

      // 5. Import from the generated ZIP
      final importProgress = <double>[];
      final importResult = await importService.importFromZip(
        zipBytes,
        (p, msg) => importProgress.add(p),
      );

      expect(importProgress, isNotEmpty);
      expect(importProgress.last, equals(1.0));
      expect(importResult['success'], equals(2));
      expect(importResult['error'], equals(0));

      // 6. Verify imported repository products
      final importedProducts = await productRepo.findAll();
      expect(importedProducts, hasLength(2));

      final imp1 = importedProducts.firstWhere((p) => p.id == p1.id);
      expect(imp1.name, equals(p1.name));
      expect(imp1.description, equals(p1.description));
      expect(imp1.price, equals(p1.price));
      expect(imp1.quantity, equals(p1.quantity));
      expect(imp1.category, equals(p1.category));
      expect(imp1.vat, equals(p1.vat));
      expect(imp1.imageUrl, equals(p1.imageUrl)); // remote URL preserved

      final imp2 = importedProducts.firstWhere((p) => p.id == p2.id);
      expect(imp2.quantity, equals(p2.quantity));
    });

    test('Import defaults missing quantity to 0', () async {
      // 1. Create a minimal Excel with no quantity column
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
        ex.TextCellValue('Gorsel Linki'), // NO STOK COLUMN
      ]);

      sheet.appendRow([
        ex.TextCellValue('8690504090106'),
        ex.TextCellValue('Test Product 1'),
        ex.TextCellValue('Category 1'),
        ex.TextCellValue('Brand 1'),
        const ex.DoubleCellValue(10.0),
        const ex.IntCellValue(18),
        ex.TextCellValue(''),
      ]);

      final excelBytes = excel.save();
      expect(excelBytes, isNotNull);

      final archive = Archive();
      archive.addFile(ArchiveFile(
          'market_data_catalog.xlsx', excelBytes!.length, excelBytes));
      final zipBytes = ZipEncoder().encode(archive);
      expect(zipBytes, isNotNull);

      // 2. Import
      final result = await importService.importFromZip(
        Uint8List.fromList(zipBytes!),
        (p, msg) {},
      );

      expect(result['success'], equals(1));
      final importedProducts = await productRepo.findAll();
      expect(importedProducts, hasLength(1));
      expect(importedProducts.first.quantity, equals(0));
    });

    test('native file import streams ZIP images to disk and links by barcode',
        () async {
      final excel = ex.Excel.createExcel();
      final sheet = excel['market_data_catalog'];
      excel.delete('Sheet1');
      sheet.appendRow([
        ex.TextCellValue('Barkod'),
        ex.TextCellValue('Urun Adi'),
        ex.TextCellValue('Kategori'),
        ex.TextCellValue('Marka'),
        ex.TextCellValue('Fiyat'),
        ex.TextCellValue('KDV'),
        ex.TextCellValue('Gorsel Linki'),
        ex.TextCellValue('Stok'),
      ]);
      sheet.appendRow([
        ex.TextCellValue('8690000000001'),
        ex.TextCellValue('Dosyadan Ürün'),
        ex.TextCellValue('Test'),
        ex.TextCellValue('Serenut'),
        const ex.DoubleCellValue(25),
        const ex.IntCellValue(20),
        ex.TextCellValue(''),
        const ex.IntCellValue(3),
      ]);
      final excelBytes = excel.save()!;
      final sourceImage = img.Image(width: 1200, height: 600);
      img.fill(sourceImage, color: img.ColorRgb8(25, 120, 210));
      final sourceImageBytes = img.encodePng(sourceImage);
      final archive = Archive()
        ..addFile(ArchiveFile(
          'urunler.xlsx',
          excelBytes.length,
          excelBytes,
        ))
        ..addFile(ArchiveFile(
          '8690000000001.jpg',
          sourceImageBytes.length,
          sourceImageBytes,
        ));
      final zipFile = File('${tempDir.path}/native_catalog.zip');
      await zipFile.writeAsBytes(ZipEncoder().encode(archive)!);

      final analysis = await importService.analyzeFile(
        zipFile.path,
        (_, __) {},
      );
      expect(analysis.products, hasLength(1));
      expect(analysis.images.keys, contains('8690000000001'));

      final result = await importService.importFromFile(
        zipFile.path,
        (_, __) {},
      );
      expect(result['success'], 1);
      final product = await productRepo.findById('8690000000001');
      expect(product, isNotNull);
      expect(product!.imageUrl, isNotNull);
      final optimized =
          img.decodeJpg(await File(product.imageUrl!).readAsBytes());
      expect(optimized, isNotNull);
      expect(optimized!.width, 320);
      expect(optimized.height, 320);
    });

    test('native file analysis accepts catalog archives above 10,000 files',
        () async {
      final excel = ex.Excel.createExcel();
      final sheet = excel['market_data_catalog'];
      excel.delete('Sheet1');
      sheet.appendRow([
        ex.TextCellValue('Barkod'),
        ex.TextCellValue('Urun Adi'),
        ex.TextCellValue('Kategori'),
        ex.TextCellValue('Marka'),
        ex.TextCellValue('Fiyat'),
        ex.TextCellValue('KDV'),
        ex.TextCellValue('Gorsel Linki'),
        ex.TextCellValue('Stok'),
      ]);
      sheet.appendRow([
        ex.TextCellValue('8690000009999'),
        ex.TextCellValue('Büyük Katalog Ürünü'),
        ex.TextCellValue('Test'),
        ex.TextCellValue('Serenut'),
        const ex.DoubleCellValue(10),
        const ex.IntCellValue(20),
        ex.TextCellValue(''),
        const ex.IntCellValue(1),
      ]);

      final excelBytes = excel.save()!;
      final archive = Archive()
        ..addFile(ArchiveFile('urunler.xlsx', excelBytes.length, excelBytes));
      for (var index = 0; index < 10005; index++) {
        archive.addFile(ArchiveFile('metadata/$index.txt', 0, const <int>[]));
      }
      final zipFile = File('${tempDir.path}/large_file_count_catalog.zip');
      await zipFile.writeAsBytes(ZipEncoder().encode(archive)!);

      final analysis = await importService.analyzeFile(
        zipFile.path,
        (_, __) {},
      );
      expect(analysis.products, hasLength(1));
      expect(analysis.products.single['barcode'], '8690000009999');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
