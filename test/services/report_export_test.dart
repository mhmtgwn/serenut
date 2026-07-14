import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/document_export_service.dart';
import 'package:excel/excel.dart' as ex;

// Mock Path Provider Platform
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.current.absolute.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.current.absolute.path;
  }

  @override
  Future<String?> getLibraryPath() async {
    return Directory.current.absolute.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.current.absolute.path;
  }

  @override
  Future<String?> getExternalStoragePath() async {
    return Directory.current.absolute.path;
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    return [Directory.current.absolute.path];
  }

  @override
  Future<List<String>?> getExternalStoragePaths(
      {StorageDirectory? type}) async {
    return [Directory.current.absolute.path];
  }

  @override
  Future<String?> getDownloadsPath() async {
    return Directory.current.absolute.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  group('DocumentExportService Excel Reports Tests', () {
    late DocumentExportService exportService;

    setUp(() {
      exportService = DocumentExportService();
    });

    test(
        'exportEndOfDayReportExcel generates a valid file containing Z-report data',
        () async {
      final today = DateTime.now();
      final sales = [
        SaleEntity(
          id: 'sale-101',
          customerId: 'cust-1',
          totalAmount: 120.0,
          paidAmount: 100.0,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: today,
          items: [],
        ),
        SaleEntity(
          id: 'sale-102',
          customerId: 'cust-2',
          totalAmount: 250.0,
          paidAmount: 250.0,
          paymentMethod: 'card',
          status: 'completed',
          createdAt: today,
          items: [],
        ),
      ];

      final filePath = await exportService.exportEndOfDayReportExcel(
        date: today,
        totalRevenue: 370.0,
        totalCollected: 350.0,
        totalDebt: 20.0,
        salesCount: 2,
        sales: sales,
        currency: 'TL',
      );

      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      final excel = ex.Excel.decodeBytes(bytes);
      final sheet = excel['Gun Sonu Raporu'];
      expect(sheet, isNotNull);

      // Verify some cells contain the correct data
      final ciroRow = sheet.rows.firstWhere((row) => row.any(
          (cell) => cell?.value?.toString().contains('Toplam Ciro') ?? false));
      expect(ciroRow, isNotNull);
      expect(
          ciroRow
              .any((cell) => cell?.value?.toString().contains('370') ?? false),
          isTrue);

      final countRow = sheet.rows.firstWhere((row) => row.any((cell) =>
          cell?.value?.toString().contains('Toplam Satış Adedi') ?? false));
      expect(countRow, isNotNull);
      expect(
          countRow
              .any((cell) => cell?.value?.toString().contains('2') ?? false),
          isTrue);

      await file.delete();
    });

    test(
        'exportVatReportExcel generates a valid file containing VAT rates and sums',
        () async {
      final startDate = DateTime.now().subtract(const Duration(days: 7));
      final endDate = DateTime.now();
      final vatSummary = [
        {
          'vat_rate': 18,
          'taxable_amount': 1000.0,
          'vat_amount': 180.0,
        },
        {
          'vat_rate': 8,
          'taxable_amount': 500.0,
          'vat_amount': 40.0,
        }
      ];

      final filePath = await exportService.exportVatReportExcel(
        startDate: startDate,
        endDate: endDate,
        vatSummaryRows: vatSummary,
        currency: 'TL',
      );

      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      final excel = ex.Excel.decodeBytes(bytes);
      final sheet = excel['KDV Raporu'];
      expect(sheet, isNotNull);

      // Verify that KDV values are correctly written
      final vatRow18 = sheet.rows.firstWhere(
          (row) => row.any((cell) => cell?.value?.toString() == '18'));
      expect(vatRow18, isNotNull);
      expect(
          vatRow18.any((cell) =>
              cell?.value?.toString() == '1000.0' ||
              cell?.value?.toString() == '1000'),
          isTrue);
      expect(
          vatRow18.any((cell) =>
              cell?.value?.toString() == '180.0' ||
              cell?.value?.toString() == '180'),
          isTrue);

      final totalRow = sheet.rows.firstWhere((row) => row.any(
          (cell) => cell?.value?.toString().contains('GENEL TOPLAM') ?? false));
      expect(totalRow, isNotNull);
      expect(
          totalRow.any((cell) =>
              cell?.value?.toString() == '1500.0' ||
              cell?.value?.toString() == '1500'),
          isTrue); // Total matrah
      expect(
          totalRow.any((cell) =>
              cell?.value?.toString() == '220.0' ||
              cell?.value?.toString() == '220'),
          isTrue); // Total vat

      await file.delete();
    });
  });
}
