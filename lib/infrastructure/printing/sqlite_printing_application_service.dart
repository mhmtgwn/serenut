import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/printing/printing_application_service.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/printing/print_asset_encoder.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';

class SqlitePrintingApplicationService implements PrintingApplicationService {
  final PrintingRepository repository;
  final PrintingRuntime runtime;
  final PrintAssetEncoder assets;

  const SqlitePrintingApplicationService({
    required this.repository,
    required this.runtime,
    this.assets = const PrintAssetEncoder(),
  });

  @override
  Future<PrintJobRecord> queueSaleReceipt(
      SaleEntity sale,
      List<Map<String, dynamic>> items,
      CustomerEntity? customer,
      Settings settings) {
    return _receipt(
        settings,
        {
          'number': _short(sale.id),
          'date': _date(sale.createdAt),
          'payment': _payment(sale.paymentMethod),
          'cashier': sale.createdBy,
          'customerName': customer?.name,
          'customerBalance': customer?.balance,
          'total': sale.totalAmount,
          'paid': sale.paidAmount,
          'remaining': sale.remainingAmount,
          'openDrawer': sale.paymentMethod == 'cash',
          'qrData': 'sale|${sale.id}|${sale.totalAmount}',
        },
        items);
  }

  @override
  Future<PrintJobRecord> queueOrderReceipt(
      OrderEntity order,
      List<Map<String, dynamic>> items,
      CustomerEntity? customer,
      Settings settings,
      {double? paidAmount,
      String? notes,
      int copies = 1}) {
    return _receipt(
        settings,
        {
          'number': order.displayNumber,
          'date': _date(order.createdAt),
          'payment': 'Sipariş',
          'cashier': order.createdBy,
          'customerName': customer?.name ?? order.customerId,
          'customerBalance': customer?.balance,
          'total': order.totalAmount,
          'paid': paidAmount,
          'notes': notes ?? order.notes,
          'qrData': 'order|${order.id}|${order.totalAmount}',
          'barcode': order.displayNumber,
        },
        items,
        requestedCopies: copies);
  }

  @override
  Future<PrintJobRecord> queueCollectionReceipt(CustomerEntity customer,
      double amount, String paymentMethod, String? notes, Settings settings) {
    return _receipt(settings, {
      'number': 'TAH-${DateTime.now().millisecondsSinceEpoch}',
      'date': _date(DateTime.now()),
      'payment': _payment(paymentMethod),
      'customerName': customer.name,
      'customerBalance': customer.balance,
      'total': amount,
      'paid': amount,
      'notes': notes,
    }, const []);
  }

  @override
  Future<PrintJobRecord> queueReport(String reportType, ReportSummary summary,
      List<CategoryRevenue> categories, Settings settings) {
    return _receipt(
        settings,
        {
          'number': '$reportType RAPORU',
          'date': _date(DateTime.now()),
          'payment': summary.range.label,
          'total': summary.totalRevenue,
          'paid': summary.totalCollected,
          'notes':
              '${summary.totalSales} satış · Borç ${summary.totalDebt.toStringAsFixed(2)}',
        },
        categories
            .map((category) => {
                  'product_name': category.categoryName,
                  'quantity': category.saleCount,
                  'unit_price': category.saleCount == 0
                      ? 0
                      : category.totalAmount / category.saleCount,
                  'total': category.totalAmount,
                })
            .toList());
  }

  @override
  Future<PrintJobRecord> queueOrderLabel(
      OrderEntity order, List<Map<String, dynamic>> items, Settings settings,
      {CustomerEntity? customer,
      double? paidAmount,
      double? previousDebt,
      String? paymentStatusOverride,
      int copies = 1}) async {
    final first = items.firstOrNull;
    final logo = await assets.loadLogo(settings.businessLogo);
    // Derive a short customer identifier from the customer id
    final rawCustomerId = customer?.id ?? order.customerId;
    final shortCustomerId = rawCustomerId.length > 8
        ? rawCustomerId.substring(0, 8).toUpperCase()
        : rawCustomerId.toUpperCase();
    final resolvedPaymentStatus = paymentStatusOverride ??
        (paidAmount == null
            ? 'Bilinmiyor'
            : paidAmount >= order.totalAmount - 0.01
                ? 'Ödendi'
                : paidAmount <= 0.01
                    ? 'Ödenmedi'
                    : 'Kısmi ödendi');
    final double effectivePaid = paidAmount ??
        ((order.status == 'completed' || order.status == 'paid')
            ? order.totalAmount
            : 0.0);
    final orderUnpaid = math.max(0.0, order.totalAmount - effectivePaid);
    final currentDebt = (customer != null && customer.balance < 0)
        ? customer.balance.abs()
        : 0.0;
    // When re-printing an existing order whose unpaid amount has already been
    // ledgered into customer.balance, subtract this order's unpaid portion so we
    // only show genuine PREVIOUS debt that existed prior to this order.
    final calculatedPreviousDebt = math.max(0.0, currentDebt - orderUnpaid);

    return _enqueue(
        PrintDocumentKind.orderLabel,
        {
          'orderNo': order.displayNumber,
          'customerName': customer?.name ?? order.customerId,
          'customerPhone': customer?.phone ?? '',
          'customerNo': shortCustomerId,
          'previousDebt': previousDebt ?? calculatedPreviousDebt,
          'productName': items.length == 1
              ? _itemName(first ?? const {})
              : '${items.length} Ürün / Paket',
          'quantity': items.length == 1
              ? (first?['quantity'] as num?)?.toDouble() ?? 1
              : 1.0,
          'items': items,
          'note': first?['note']?.toString() ?? order.notes,
          'timestamp': order.createdAt.toIso8601String(),
          'totalAmount': order.totalAmount,
          'paymentStatus': resolvedPaymentStatus,
          'itemsCount': items.length,
          'businessName': settings.businessName,
          if (logo != null) 'logoBytesBase64': base64Encode(logo),
        },
        copies: copies);
  }

  @override
  Future<List<PrintJobRecord>> queueProductLabels(
      List<ProductEntity> products, Settings settings,
      {int copies = 1}) async {
    final logo = await assets.loadLogo(settings.businessLogo);
    final jobs = <PrintJobRecord>[];
    for (final product in products) {
      final label = LabelModel(
        productName: product.name,
        brand: product.brand,
        unit: product.unit,
        shelfCode: product.shelfCode,
        businessName: settings.businessName,
        weight: 1,
        price: product.price,
        barcode: product.id,
        qrData: 'product|${product.id}',
        timestamp: DateTime.now(),
      );
      jobs.add(await _enqueue(
          PrintDocumentKind.productLabel,
          {
            'labels': [label.toMap()],
            if (logo != null) 'logoBytesBase64': base64Encode(logo),
          },
          copies: copies));
    }
    return jobs;
  }

  Future<PrintJobRecord> _receipt(Settings settings,
      Map<String, Object?> document, List<Map<String, dynamic>> items,
      {int? requestedCopies}) async {
    final route = await repository.getRoute(PrintDocumentKind.receipt);
    final device =
        route == null ? null : await repository.getDevice(route.deviceId);
    final paperWidth =
        (device?.capabilities['paperWidthMm'] as num?)?.toInt() ?? 58;
    final copies = requestedCopies ??
        (device?.transportConfig['copies'] as num?)?.toInt().clamp(1, 20) ??
        1;
    final source = await assets.loadLogo(settings.businessLogo);
    final logo = source == null
        ? null
        : assets.toEscPosRaster(source, maxWidth: paperWidth <= 58 ? 320 : 448);
    return _enqueue(
        PrintDocumentKind.receipt,
        {
          'business': {
            'name': settings.businessName,
            'subtitle': settings.businessType.trim().isNotEmpty
                ? settings.businessType.trim()
                : null,
            'address': settings.businessAddress,
            'phone': settings.businessPhone,
            'taxId': settings.businessTaxId,
            'email': settings.businessEmail?.trim().isNotEmpty == true
                ? settings.businessEmail!.trim()
                : null,
            'receiptFooterText': settings.receiptFooterText,
          },
          'document': document,
          'items': items.map(_normalizeItem).toList(),
          'currency': settings.currency == '₺' ? 'TL' : settings.currency,
          if (logo != null) 'logoEscPosBase64': base64Encode(logo),
        },
        copies: copies);
  }

  Future<PrintJobRecord> _enqueue(
      PrintDocumentKind kind, Map<String, Object?> payload,
      {int copies = 1}) async {
    final job = await repository.enqueue(
        kind: kind, payloadJson: jsonEncode(payload), copies: copies);
    if (runtime.isRunning) unawaited(runtime.processNow());
    return job;
  }

  static Map<String, Object?> _normalizeItem(Map<String, dynamic> item) {
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
    final unitPrice = (item['unit_price'] as num?)?.toDouble() ??
        (item['price'] as num?)?.toDouble() ??
        0;
    return {
      'name': _itemName(item),
      'quantity': quantity,
      'unitPrice': unitPrice,
      'total': (item['total'] as num?)?.toDouble() ?? quantity * unitPrice,
    };
  }

  static String _itemName(Map<String, dynamic> item) =>
      item['product_name']?.toString().trim().isNotEmpty == true
          ? item['product_name'].toString()
          : item['product_id']?.toString() ?? 'Ürün';
  static String _short(String value) =>
      value.length > 8 ? value.substring(0, 8) : value;
  static String _date(DateTime value) => value.toString().substring(0, 16);
  static String _payment(String value) => switch (value) {
        'cash' || 'nakit' => 'Nakit',
        'card' || 'kart' => 'Kart',
        'debt' || 'vadeli' => 'Vadeli',
        _ => value,
      };
}
