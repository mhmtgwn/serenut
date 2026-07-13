// lib/domain/services/dataset_import_service.dart
// Product Catalog & Images Import Service
// Decodes ZIP archives, extracts images to local directories (native), parses Excel files, and inserts into IProductRepository.

import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as ex;
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/import_strategy.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

class ParsedCatalogData {
  final List<Map<String, dynamic>> products;
  final Map<String, List<int>> images;

  ParsedCatalogData({required this.products, required this.images});
}

/// Top-level helper function to execute ZIP decoding and Excel parsing in Isolate.
/// Being top-level prevents the closure from capturing instance scope (like 'this' or 'onProgress').
Future<ParsedCatalogData> _parseZipInSeparateIsolate(Uint8List bytes) {
  return Isolate.run(() => DatasetImportService._parseZipInIsolate(bytes));
}

class DatasetImportService {
  final IProductRepository _productRepository;

  DatasetImportService(this._productRepository);

  /// Helper to convert cell value to String safely
  static String _staticParseString(dynamic cell) {
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    return val.toString().trim();
  }

  /// Helper to convert cell value to double safely
  static double _staticParseDouble(dynamic cell) {
    if (cell == null) return 0.0;
    final val = cell.value;
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  /// Helper to convert cell value to int safely
  static int _staticParseInt(dynamic cell) {
    if (cell == null) return 0;
    final val = cell.value;
    if (val == null) return 0;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  /// CPU-heavy ZIP decoding and Excel parsing executed in a background Isolate.
  static ParsedCatalogData _parseZipInIsolate(Uint8List zipBytes) {
    // 1. Pre-decompression limit checks via ZipDirectory (Zip Bomb Mitigation)
    final inputStream = InputStream(zipBytes);
    final zipDirectory = ZipDirectory.read(inputStream);

    int totalUncompressedSize = 0;
    int fileCount = 0;
    for (final header in zipDirectory.fileHeaders) {
      fileCount++;
      if (fileCount > 10000) {
        throw Exception('Dosya sayısı çok fazla (Maks 10.000).');
      }
      
      final filename = header.filename.toLowerCase();
      if (filename.endsWith('.zip') || filename.endsWith('.tar') || filename.endsWith('.gz')) {
        throw Exception('İç içe arşiv dosyaları desteklenmiyor.');
      }

      final uncompressed = header.uncompressedSize ?? 0;
      totalUncompressedSize += uncompressed;
      
      if (header.compressedSize != null && header.compressedSize! > 0) {
        final ratio = uncompressed / header.compressedSize!;
        if (ratio > 100) {
          throw Exception('Yüksek sıkıştırma oranı tespit edildi. Geçersiz arşiv.');
        }
      }
    }

    if (totalUncompressedSize > 100 * 1024 * 1024) {
      throw Exception('Sıkıştırılmamış toplam dosya boyutu sınırı aşıldı (Maks 100MB).');
    }

    // Decode ZIP archive after checks
    final archive = ZipDecoder().decodeBuffer(InputStream(zipBytes));


    // 2. Identify Excel file and images
    bool isRawExcel = true;
    ArchiveFile? excelFile;
    final Map<String, List<int>> imageMap = {};

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name.endsWith('.xlsx') && !file.name.startsWith('__MACOSX/')) {
        isRawExcel = false;
        excelFile = file;
      } else if (file.name.startsWith('images/')) {
        // Extract barcode from filename (e.g., 'images/8690504090106.jpg' -> '8690504090106')
        final filename = p.basename(file.name);
        final dotIndex = filename.lastIndexOf('.');
        final barcode = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
        if (barcode.isNotEmpty && file.content != null) {
          imageMap[barcode] = Uint8List.fromList(file.content as List<int>);
        }
      }
    }

    Uint8List excelBytes;
    if (isRawExcel) {
      excelBytes = zipBytes;
    } else {
      if (excelFile == null) {
        throw Exception('ZIP arşivi içerisinde Excel (.xlsx) dosyası bulunamadı.');
      }
      excelBytes = Uint8List.fromList(excelFile.content as List<int>);
    }

    // 3. Fix Excel relationships XML in-memory (reuse archive if isRawExcel to avoid double decoding)
    final innerArchive = isRawExcel ? archive : ZipDecoder().decodeBytes(excelBytes);
    final newInnerArchive = Archive();

    for (final file in innerArchive) {
      if (file.name == 'xl/_rels/workbook.xml.rels') {
        final rawContent = file.content;
        if (rawContent != null) {
          var content = String.fromCharCodes(rawContent as List<int>);
          // Replace Target="/xl/ with Target=" to resolve internal parsing bugs in excel package
          final fixedContent = content.replaceAll('Target="/xl/', 'Target="');
          final fixedBytes = Uint8List.fromList(fixedContent.codeUnits);
          newInnerArchive.addFile(ArchiveFile(file.name, fixedBytes.length, fixedBytes));
        }
      } else {
        newInnerArchive.addFile(file);
      }
    }

    final zipEncoder = ZipEncoder();
    final encodedExcelBytes = zipEncoder.encode(newInnerArchive);
    if (encodedExcelBytes == null) {
      throw Exception('Excel ilişkileri düzeltilemedi.');
    }

    // 4. Decode Excel sheet
    final excel = ex.Excel.decodeBytes(Uint8List.fromList(encodedExcelBytes));
    if (excel.tables.isEmpty) {
      throw Exception('Excel dosyası okunamadı veya boş.');
    }
    
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.maxRows <= 1) {
      throw Exception('Excel sayfası boş.');
    }

    // 5. Parse sheet rows into transfer maps
    final rows = sheet.rows;
    final totalRows = rows.length;
    final List<Map<String, dynamic>> parsedProducts = [];

    for (int i = 1; i < totalRows; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      final barcode = row.isNotEmpty ? _staticParseString(row[0]) : '';
      final name = row.length > 1 ? _staticParseString(row[1]) : '';
      
      if (barcode.isEmpty || name.isEmpty) {
        continue;
      }

      final category = row.length > 2 ? _staticParseString(row[2]) : 'Diğer';
      final brand = row.length > 3 ? _staticParseString(row[3]) : 'Bilinmiyor';
      final price = row.length > 4 ? _staticParseDouble(row[4]) : 0.0;
      final vat = row.length > 5 ? _staticParseInt(row[5]) : 18;
      final remoteUrl = row.length > 6 ? _staticParseString(row[6]) : '';
      final quantity = row.length > 7 ? _staticParseInt(row[7]) : 0;

      parsedProducts.add({
        'barcode': barcode,
        'name': name,
        'category': category,
        'brand': brand,
        'price': price,
        'vat': vat,
        'remoteUrl': remoteUrl,
        'quantity': quantity,
      });
    }

    return ParsedCatalogData(products: parsedProducts, images: imageMap);
  }

  /// Asynchronous ZIP decoding and Excel parsing for Flutter Web execution.
  /// Yields execution to let browser draw frames between major CPU-heavy tasks.
  static Future<ParsedCatalogData> _parseZipAsync(
    Uint8List zipBytes, 
    void Function(double progress, String status) onProgress,
  ) async {
    // Step 1: Pre-decompression checks & Decode ZIP
    onProgress(0.06, 'Dosya açılıyor...');
    await Future.delayed(const Duration(milliseconds: 50));
    
    final inputStream = InputStream(zipBytes);
    final zipDirectory = ZipDirectory.read(inputStream);

    int totalUncompressedSize = 0;
    int fileCount = 0;
    for (final header in zipDirectory.fileHeaders) {
      fileCount++;
      if (fileCount > 10000) {
        throw Exception('Dosya sayısı çok fazla (Maks 10.000).');
      }
      
      final filename = header.filename.toLowerCase();
      if (filename.endsWith('.zip') || filename.endsWith('.tar') || filename.endsWith('.gz')) {
        throw Exception('İç içe arşiv dosyaları desteklenmiyor.');
      }

      final uncompressed = header.uncompressedSize ?? 0;
      totalUncompressedSize += uncompressed;
      
      if (header.compressedSize != null && header.compressedSize! > 0) {
        final ratio = uncompressed / header.compressedSize!;
        if (ratio > 100) {
          throw Exception('Yüksek sıkıştırma oranı tespit edildi. Geçersiz arşiv.');
        }
      }
    }

    if (totalUncompressedSize > 100 * 1024 * 1024) {
      throw Exception('Sıkıştırılmamış toplam dosya boyutu sınırı aşıldı (Maks 100MB).');
    }

    final archive = ZipDecoder().decodeBuffer(InputStream(zipBytes));


    // Step 2: Identify files & images
    onProgress(0.12, 'Katalog dosyaları ve görseller ayrıştırılıyor...');
    await Future.delayed(const Duration(milliseconds: 50));
    
    bool isRawExcel = true;
    ArchiveFile? excelFile;
    final Map<String, List<int>> imageMap = {};

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name.endsWith('.xlsx') && !file.name.startsWith('__MACOSX/')) {
        isRawExcel = false;
        excelFile = file;
      } else if (file.name.startsWith('images/')) {
        final filename = p.basename(file.name);
        final dotIndex = filename.lastIndexOf('.');
        final barcode = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
        if (barcode.isNotEmpty && file.content != null) {
          imageMap[barcode] = Uint8List.fromList(file.content as List<int>);
        }
      }
    }

    Uint8List excelBytes;
    if (isRawExcel) {
      excelBytes = zipBytes;
    } else {
      if (excelFile == null) {
        throw Exception('ZIP arşivi içerisinde Excel (.xlsx) dosyası bulunamadı.');
      }
      excelBytes = Uint8List.fromList(excelFile.content as List<int>);
    }

    // Step 3: Fix Excel relations XML (reuse archive if isRawExcel to avoid double decoding)
    onProgress(0.18, 'Excel ilişkileri optimize ediliyor...');
    await Future.delayed(const Duration(milliseconds: 50));
    final innerArchive = isRawExcel ? archive : ZipDecoder().decodeBytes(excelBytes);
    final newInnerArchive = Archive();

    for (final file in innerArchive) {
      if (file.name == 'xl/_rels/workbook.xml.rels') {
        final rawContent = file.content;
        if (rawContent != null) {
          var content = String.fromCharCodes(rawContent as List<int>);
          final fixedContent = content.replaceAll('Target="/xl/', 'Target="');
          final fixedBytes = Uint8List.fromList(fixedContent.codeUnits);
          newInnerArchive.addFile(ArchiveFile(file.name, fixedBytes.length, fixedBytes));
        }
      } else {
        newInnerArchive.addFile(file);
      }
    }

    final zipEncoder = ZipEncoder();
    final encodedExcelBytes = zipEncoder.encode(newInnerArchive);
    if (encodedExcelBytes == null) {
      throw Exception('Excel ilişkileri düzeltilemedi.');
    }

    // Step 4: Decode Excel
    onProgress(0.24, 'Excel tablosu çözümleniyor (Bu işlem birkaç saniye sürebilir)...');
    await Future.delayed(const Duration(milliseconds: 100));
    final excel = ex.Excel.decodeBytes(Uint8List.fromList(encodedExcelBytes));
    if (excel.tables.isEmpty) {
      throw Exception('Excel dosyası okunamadı veya boş.');
    }
    
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.maxRows <= 1) {
      throw Exception('Excel sayfası boş.');
    }

    // Step 5: Parse sheet rows
    onProgress(0.28, 'Excel satırları okunuyor...');
    await Future.delayed(const Duration(milliseconds: 50));
    final rows = sheet.rows;
    final totalRows = rows.length;
    final List<Map<String, dynamic>> parsedProducts = [];

    for (int i = 1; i < totalRows; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      final barcode = row.isNotEmpty ? _staticParseString(row[0]) : '';
      final name = row.length > 1 ? _staticParseString(row[1]) : '';
      
      if (barcode.isEmpty || name.isEmpty) {
        continue;
      }

      final category = row.length > 2 ? _staticParseString(row[2]) : 'Diğer';
      final brand = row.length > 3 ? _staticParseString(row[3]) : 'Bilinmiyor';
      final price = row.length > 4 ? _staticParseDouble(row[4]) : 0.0;
      final vat = row.length > 5 ? _staticParseInt(row[5]) : 18;
      final remoteUrl = row.length > 6 ? _staticParseString(row[6]) : '';
      final quantity = row.length > 7 ? _staticParseInt(row[7]) : 0;

      parsedProducts.add({
        'barcode': barcode,
        'name': name,
        'category': category,
        'brand': brand,
        'price': price,
        'vat': vat,
        'remoteUrl': remoteUrl,
        'quantity': quantity,
      });

      // Periodically yield to prevent browser from completely locking up during Excel row looping
      if (i % 200 == 0) {
        onProgress(
          0.28 + (i / totalRows) * 0.12,
          'Excel satırları okunuyor: $i / $totalRows ürün...',
        );
        await Future.delayed(Duration.zero);
      }
    }

    return ParsedCatalogData(products: parsedProducts, images: imageMap);
  }

  /// Decodes and parses ZIP/Excel catalog without inserting into DB (for wizard preview).
  Future<ParsedCatalogData> analyzeZip(
    Uint8List zipBytes, 
    void Function(double progress, String status) onProgress,
  ) async {
    if (zipBytes.length > 100 * 1024 * 1024) {
      throw Exception('Dosya boyutu sınırlandırılmıştır (Maks 100MB).');
    }
    return kIsWeb
        ? await _parseZipAsync(zipBytes, onProgress)
        : await _parseZipInSeparateIsolate(zipBytes);
  }

  /// Imports product catalog and images from a ZIP archive bytes.
  /// 
  /// Calls [onProgress] with progress fraction and informative status messages.
  /// Returns a map with summary info (total imported, errors).
  Future<Map<String, int>> importFromZip(
    Uint8List zipBytes, 
    void Function(double progress, String status) onProgress, [
    ImportStrategy strategy = const ImportStrategy(),
  ]) async {
    if (zipBytes.length > 100 * 1024 * 1024) {
      throw Exception('Dosya boyutu sınırlandırılmıştır (Maks 100MB).');
    }
    int importedCount = 0;
    int errorCount = 0;
    final stopwatch = Stopwatch()..start();
    final startRss = kIsWeb ? 0 : ProcessInfo.currentRss;
    int peakRss = startRss;

    void updatePeakRss() {
      if (kIsWeb) return;
      final current = ProcessInfo.currentRss;
      if (current > peakRss) {
        peakRss = current;
      }
    }

    final List<String> writtenImagePaths = [];

    try {
      onProgress(0.05, 'Katalog ayrıştırılması başlatılıyor...');

      // Execute parsing asynchronously on web, or in a background Isolate on native platforms
      final parsedData = kIsWeb
          ? await _parseZipAsync(zipBytes, onProgress)
          : await _parseZipInSeparateIsolate(zipBytes);
      onProgress(0.30, 'Katalog dosyaları çözümlendi.');

      final imageMap = parsedData.images;
      final products = parsedData.products;

      // Save extracted images
      String? localImagesDirPath;
      if (!kIsWeb) {
        final docsDir = await getApplicationDocumentsDirectory();
        final localImagesDir = Directory(p.join(docsDir.path, 'product_images'));
        if (!await localImagesDir.exists()) {
          await localImagesDir.create(recursive: true);
        }
        localImagesDirPath = localImagesDir.path;

        int savedImages = 0;
        final totalImages = imageMap.length;
        for (final entry in imageMap.entries) {
          final barcode = entry.key;
          final bytes = entry.value;
          final imagePath = p.join(localImagesDirPath, '$barcode.jpg');
          final imageFile = File(imagePath);
          await imageFile.writeAsBytes(bytes);
          writtenImagePaths.add(imagePath);
          
          savedImages++;
          if (savedImages % 50 == 0 && totalImages > 0) {
            onProgress(
              0.30 + (savedImages / totalImages) * 0.15,
              'Görseller kaydediliyor: $savedImages / $totalImages...',
            );
          }
        }
      }
      onProgress(0.45, 'Veritabanı kayıt işlemi hazırlanıyor...');

      final isSqlite = _productRepository.runtimeType.toString().contains('SqliteProductRepository');

      if (isSqlite) {
        final db = await DatabaseManager().getDatabase();
        final totalProducts = products.length;
        const int chunkLimit = 200;

        await db.transaction((txn) async {
          for (int i = 0; i < totalProducts; i += chunkLimit) {
            final chunk = products.sublist(i, min(i + chunkLimit, totalProducts));
            final batch = txn.batch();

            for (final prodMap in chunk) {
              final barcode = prodMap['barcode'] as String;
              final name = prodMap['name'] as String;
              final category = prodMap['category'] as String;
              final brand = prodMap['brand'] as String;
              final price = prodMap['price'] as double;
              final vat = prodMap['vat'] as int;
              final remoteUrl = prodMap['remoteUrl'] as String;
              final quantity = prodMap['quantity'] as int? ?? 0;

              // Resolve image URL
              String? finalImageUrl;
              if (kIsWeb) {
                if (imageMap.containsKey(barcode)) {
                  finalImageUrl = 'data:image/jpeg;base64,${base64Encode(imageMap[barcode]!)}';
                } else if (remoteUrl.isNotEmpty) {
                  finalImageUrl = remoteUrl;
                }
              } else if (localImagesDirPath != null && imageMap.containsKey(barcode)) {
                finalImageUrl = p.join(localImagesDirPath, '$barcode.jpg');
              } else if (remoteUrl.isNotEmpty) {
                finalImageUrl = remoteUrl;
              }

              // Query existing product using txn
              final existingRows = await txn.query(
                'products',
                columns: ['id', 'quantity', 'price', 'description', 'image_url', 'is_active'],
                where: 'id = ?',
                whereArgs: [barcode],
              );

              if (existingRows.isEmpty) {
                if (strategy.insertNew) {
                  batch.insert('products', {
                    'id': barcode,
                    'name': name,
                    'description': brand,
                    'price': price,
                    'quantity': quantity,
                    'category': category,
                    'vat': vat,
                    'is_active': 1,
                    'created_at': DateTime.now().toIso8601String(),
                    'updated_at': DateTime.now().toIso8601String(),
                    'image_url': finalImageUrl,
                  });
                  importedCount++;
                }
              } else {
                final existing = existingRows.first;

                if (strategy.duplicateResolution == DuplicateResolution.skip) {
                  continue;
                }

                if (strategy.updateExisting) {
                  final updateFields = <String, dynamic>{
                    'updated_at': DateTime.now().toIso8601String(),
                  };

                  if (strategy.reactivatePassive && existing['is_active'] == 0) {
                    updateFields['is_active'] = 1;
                  }

                  if (strategy.syncPrices) {
                    updateFields['price'] = price;
                  }
                  if (strategy.syncDescriptions) {
                    updateFields['description'] = brand;
                  }
                  if (strategy.syncImages && finalImageUrl != null) {
                    updateFields['image_url'] = finalImageUrl;
                  }

                  if (strategy.duplicateResolution == DuplicateResolution.merge) {
                    final existingQty = existing['quantity'] as int? ?? 0;
                    updateFields['quantity'] = existingQty + quantity;
                  } else if (strategy.syncStocks) {
                    updateFields['quantity'] = quantity;
                  }

                  batch.update(
                    'products',
                    updateFields,
                    where: 'id = ?',
                    whereArgs: [barcode],
                  );
                  importedCount++;
                }
              }
            }

            await batch.commit(noResult: true);
            updatePeakRss();

            // Yield to let the UI refresh
            await Future.delayed(kIsWeb ? const Duration(milliseconds: 15) : Duration.zero);

            // Update progress (from 0.45 to 1.0)
            final currentCompleted = min(i + chunkLimit, totalProducts);
            final progressFraction = 0.45 + ((currentCompleted / totalProducts) * 0.55);
            onProgress(
              progressFraction,
              'Veritabanına kaydediliyor: $currentCompleted / $totalProducts ürün...',
            );
          }

          // Deactivate missing products if enabled
          if (strategy.deactivateMissing) {
            final excelBarcodes = products.map((p) => p['barcode'] as String).toList();
            if (excelBarcodes.isNotEmpty) {
              const int sqliteParamLimit = 999;
              for (int k = 0; k < excelBarcodes.length; k += sqliteParamLimit) {
                final subList = excelBarcodes.sublist(k, min(k + sqliteParamLimit, excelBarcodes.length));
                final placeholders = List.filled(subList.length, '?').join(',');
                await txn.update(
                  'products',
                  {
                    'is_active': 0,
                    'updated_at': DateTime.now().toIso8601String(),
                  },
                  where: 'id NOT IN ($placeholders) AND is_active = 1',
                  whereArgs: subList,
                );
              }
            }
          }
        });
      } else {
        // Fallback loop using IProductRepository APIs for test mocks (InMemoryProductRepository)
        final totalProducts = products.length;
        for (int i = 0; i < totalProducts; i++) {
          final prodMap = products[i];
          final barcode = prodMap['barcode'] as String;
          final name = prodMap['name'] as String;
          final category = prodMap['category'] as String;
          final brand = prodMap['brand'] as String;
          final price = prodMap['price'] as double;
          final vat = prodMap['vat'] as int;
          final remoteUrl = prodMap['remoteUrl'] as String;
          final quantity = prodMap['quantity'] as int? ?? 0;

          String? finalImageUrl;
          if (kIsWeb) {
            if (imageMap.containsKey(barcode)) {
              finalImageUrl = 'data:image/jpeg;base64,${base64Encode(imageMap[barcode]!)}';
            } else if (remoteUrl.isNotEmpty) {
              finalImageUrl = remoteUrl;
            }
          } else if (localImagesDirPath != null && imageMap.containsKey(barcode)) {
            finalImageUrl = p.join(localImagesDirPath, '$barcode.jpg');
          } else if (remoteUrl.isNotEmpty) {
            finalImageUrl = remoteUrl;
          }

          final existing = await _productRepository.findById(barcode);

          if (existing == null) {
            if (strategy.insertNew) {
              final prod = ProductEntity(
                id: barcode,
                name: name,
                description: brand,
                price: price,
                quantity: quantity,
                category: category,
                vat: vat,
                imageUrl: finalImageUrl,
              );
              await _productRepository.create(prod);
              importedCount++;
            }
          } else {
            if (strategy.duplicateResolution == DuplicateResolution.skip) {
              continue;
            }

            if (strategy.updateExisting) {
              int finalQty = existing.quantity;
              if (strategy.duplicateResolution == DuplicateResolution.merge) {
                finalQty = existing.quantity + quantity;
              } else if (strategy.syncStocks) {
                finalQty = quantity;
              }

              final updatedProd = ProductEntity(
                id: barcode,
                name: name,
                description: strategy.syncDescriptions ? brand : existing.description,
                price: strategy.syncPrices ? price : existing.price,
                quantity: finalQty,
                category: category,
                imageUrl: strategy.syncImages && finalImageUrl != null ? finalImageUrl : existing.imageUrl,
              );
              await _productRepository.update(updatedProd);
              importedCount++;
            }
          }

          if (i % 20 == 0 || i == totalProducts - 1) {
            updatePeakRss();
            await Future.delayed(kIsWeb ? const Duration(milliseconds: 15) : Duration.zero);
            final progressFraction = 0.45 + (((i + 1) / totalProducts) * 0.55);
            onProgress(
              progressFraction,
              'Veritabanına kaydediliyor: ${i + 1} / $totalProducts ürün...',
            );
          }
        }
      }

      onProgress(1.0, 'İçe aktarma başarıyla tamamlandı.');

      await TelemetryService().logEvent('import', {
        'rows': products.length,
        'time_ms': stopwatch.elapsedMilliseconds,
        'start_rss_mb': kIsWeb ? '0.00' : (startRss / (1024 * 1024)).toStringAsFixed(2),
        'peak_rss_mb': kIsWeb ? '0.00' : (peakRss / (1024 * 1024)).toStringAsFixed(2),
        'end_rss_mb': kIsWeb ? '0.00' : (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(2),
        'status': 'success',
      });
    } catch (e) {
      for (final path in writtenImagePaths) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
      await TelemetryService().logEvent('import', {
        'time_ms': stopwatch.elapsedMilliseconds,
        'start_rss_mb': kIsWeb ? '0.00' : (startRss / (1024 * 1024)).toStringAsFixed(2),
        'peak_rss_mb': kIsWeb ? '0.00' : (peakRss / (1024 * 1024)).toStringAsFixed(2),
        'end_rss_mb': kIsWeb ? '0.00' : (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(2),
        'status': 'failed',
        'error': e.toString(),
      });
      rethrow;
    }

    return {
      'success': importedCount,
      'error': errorCount,
    };
  }

  /// Exports the entire product database and local images into a ZIP archive bytes.
  Future<Uint8List> exportToZip(void Function(double progress) onProgress) async {
    try {
      onProgress(0.05);
      final products = await _productRepository.findAll();
      onProgress(0.10);

      final excel = ex.Excel.createExcel();
      final sheet = excel['market_data_catalog'];
      excel.delete('Sheet1'); // remove default sheet

      // Header row
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

      final archive = Archive();
      final total = products.length;
      int index = 0;

      for (final p in products) {
        String remoteUrl = '';
        if (p.imageUrl != null) {
          if (p.imageUrl!.startsWith('http')) {
            remoteUrl = p.imageUrl!;
          } else if (!kIsWeb) {
            // Read native local file path
            final file = File(p.imageUrl!);
            if (file.existsSync()) {
              final imageBytes = file.readAsBytesSync();
              archive.addFile(ArchiveFile('images/${p.id}.jpg', imageBytes.length, imageBytes));
            }
          }
        }

        sheet.appendRow([
          ex.TextCellValue(p.id),
          ex.TextCellValue(p.name),
          ex.TextCellValue(p.category),
          ex.TextCellValue(p.description),
          ex.DoubleCellValue(p.price),
          ex.IntCellValue(p.vat ?? 18),
          ex.TextCellValue(remoteUrl),
          ex.IntCellValue(p.quantity),
        ]);

        index++;
        
        // Yield control every 50 iterations to keep UI responsive
        if (index % 50 == 0) {
          await Future.delayed(Duration.zero);
        }

        if (total > 0) {
          onProgress(0.10 + (index / total) * 0.70); // 10% to 80% progress
        }
      }

      onProgress(0.85);
      final excelBytes = excel.save();
      if (excelBytes != null) {
        archive.addFile(ArchiveFile('market_data_catalog.xlsx', excelBytes.length, excelBytes));
      }
      
      onProgress(0.90);
      final zipBytes = ZipEncoder().encode(archive);
      onProgress(1.0);

      if (zipBytes == null) {
        throw Exception('ZIP arşivi oluşturulamadı.');
      }
      return Uint8List.fromList(zipBytes);
    } catch (e) {
      rethrow;
    }
  }
}
