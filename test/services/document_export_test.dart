import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:serenutos/domain/services/document_export_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

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
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async {
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

  group('DocumentExportService Tests', () {
    late DocumentExportService exportService;
    late CustomerEntity testCustomer;
    late List<FinancialTransactionEntity> testTxns;

    setUp(() {
      exportService = DocumentExportService();
      testCustomer = CustomerEntity(
        id: 'cust-test-123',
        name: 'Test Musteri',
        email: 'test@customer.com',
        phone: '1234567890',
        balance: -250.0, // 250 TL borçlu
        createdAt: DateTime.now(),
      );

      testTxns = [
        FinancialTransactionEntity(
          id: 'ft-1',
          type: 'sale',
          customerId: 'cust-test-123',
          amount: 500.0,
          paidAmount: 250.0,
          debtAmount: 250.0,
          date: DateTime.now().subtract(const Duration(days: 2)),
        ),
        FinancialTransactionEntity(
          id: 'ft-2',
          type: 'collection',
          customerId: 'cust-test-123',
          amount: 150.0,
          paidAmount: 150.0,
          debtAmount: 0.0,
          date: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];
    });

    test('exportCustomerStatementPdf generates a valid PDF file on disk', () async {
      final path = await exportService.exportCustomerStatementPdf(
        testCustomer,
        testTxns,
        'TL',
      );

      expect(path, isNotEmpty);
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(file.lengthSync(), isPositive);

      // Clean up
      await file.delete();
    });

    test('exportCustomerStatementExcel generates a valid Excel workbook file on disk', () async {
      final path = await exportService.exportCustomerStatementExcel(
        testCustomer,
        testTxns,
        'TL',
      );

      expect(path, isNotEmpty);
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(file.lengthSync(), isPositive);

      // Clean up
      await file.delete();
    });

    test('exportSalesReportExcel generates workbook for sales history list', () async {
      final sales = [
        SaleEntity(
          id: 'sale-1',
          customerId: 'cust-test-123',
          totalAmount: 500.0,
          paidAmount: 250.0,
          paymentMethod: 'mixed',
          status: 'completed',
          createdAt: DateTime.now(),
          items: const [],
        ),
      ];

      final path = await exportService.exportSalesReportExcel(sales, 'Bu Ay', 'TL');

      expect(path, isNotEmpty);
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(file.lengthSync(), isPositive);

      await file.delete();
    });

    test('exportStockReportExcel generates workbook for product envanter', () async {
      final products = [
        ProductEntity(
          id: 'prod-1',
          name: 'Laptop',
          description: 'Gaming',
          price: 1500.0,
          quantity: 5,
          category: 'Electronics',
          vat: 18,
        ),
      ];

      final path = await exportService.exportStockReportExcel(products);

      expect(path, isNotEmpty);
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(file.lengthSync(), isPositive);

      await file.delete();
    });
  });
}
