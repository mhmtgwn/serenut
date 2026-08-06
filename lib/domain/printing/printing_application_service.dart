import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';

abstract interface class PrintingApplicationService {
  Future<PrintJobRecord> queueSaleReceipt(
      SaleEntity sale,
      List<Map<String, dynamic>> items,
      CustomerEntity? customer,
      Settings settings);
  Future<PrintJobRecord> queueOrderReceipt(
      OrderEntity order,
      List<Map<String, dynamic>> items,
      CustomerEntity? customer,
      Settings settings,
      {double? paidAmount,
      String? notes,
      int copies = 1});
  Future<PrintJobRecord> queueCollectionReceipt(CustomerEntity customer,
      double amount, String paymentMethod, String? notes, Settings settings);
  Future<PrintJobRecord> queueReport(String reportType, ReportSummary summary,
      List<CategoryRevenue> categories, Settings settings);
  Future<PrintJobRecord> queueOrderLabel(
      OrderEntity order, List<Map<String, dynamic>> items, Settings settings,
      {CustomerEntity? customer, int copies = 1});
  Future<List<PrintJobRecord>> queueProductLabels(
      List<ProductEntity> products, Settings settings,
      {int copies = 1});
}
