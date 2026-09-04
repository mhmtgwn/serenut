// lib/domain/services/i_printer_service.dart
// PHASE 0 — Printer Service Domain Contract

import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart'; // Will be updated to domain-level later

/// Printer purpose distinguishing between receipt and label printing
enum PrinterPurpose { receipt, label }

/// Semantic job type. Unlike [PrinterPurpose], this survives persistence and
/// identifies which renderer/device route produced the bytes.
enum PrintJobKind { receipt, productLabel, orderLabel }

extension PrintJobKindRouting on PrintJobKind {
  PrinterPurpose get purpose => this == PrintJobKind.receipt
      ? PrinterPurpose.receipt
      : PrinterPurpose.label;
}

/// Print Queue Job Model
class PrintJob {
  final String id;
  final String title;
  final Future<void> Function() printFn;
  final DateTime createdAt;
  String status; // 'pending', 'printing', 'success', 'failed'
  String? error;

  PrintJob({
    required this.id,
    required this.title,
    required this.printFn,
    required this.createdAt,
    this.status = 'pending',
    this.error,
  });
}

/// Legacy v1 printing contract.
///
/// Production code must use [PrintingApplicationService]. This contract is
/// retained temporarily only so older integrations can be identified and
/// migrated without silently changing their behavior.
@Deprecated('Use PrintingApplicationService and PrintingRepository.')
abstract class IPrinterService implements Listenable {
  List<PrintJob> get queue;
  bool get isProcessing;

  void enqueue(String title, Future<void> Function() printFn);
  void retryJob(String id);
  void clearQueue();

  Future<void> testConnection(String ip, int port);
  Future<void> testPrinterConnection(Settings settings);
  Future<void> testLabelPrinterConnection(Settings settings);

  Future<void> printSaleReceipt(
    SaleEntity sale,
    List<Map<String, dynamic>> items,
    CustomerEntity? customer,
    Settings settings,
  );

  Future<void> printOrderReceipt(
    OrderEntity order,
    List<Map<String, dynamic>> items,
    CustomerEntity? customer,
    Settings settings, {
    double? paidAmount,
    String? notes,
  });

  Future<void> printCollectionReceipt(
    CustomerEntity customer,
    double amount,
    String paymentMethod,
    String? notes,
    Settings settings,
  );

  Future<void> printXReport(
    ReportSummary summary,
    List<CategoryRevenue> categories,
    Settings settings,
  );

  Future<void> printZReport(
    ReportSummary summary,
    List<CategoryRevenue> categories,
    Settings settings,
  );

  Future<void> printOrderLabels(
    OrderEntity order,
    List<Map<String, dynamic>> items,
    Settings settings, {
    CustomerEntity? customer,
    bool useCanvas = false,
  });

  Future<void> printShelfLabels(
    List<ProductEntity> products,
    Settings settings, {
    int copies = 1,
  });

  /// Prints a diagnostics self-test receipt
  Future<void> printDiagnosticsTest(Settings settings, int paperWidth);

  /// Retries a persisted print job by sending it back to the active failover chain
  Future<void> retryPersistedJob(dynamic job, Settings settings);

  /// Automatically scans and retries all pending jobs in the persistent queue
  Future<void> processPendingQueue(Settings settings);
}
