// lib/presentation/pages/order_details_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/config/router.dart' show rootScaffoldMessengerKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart'
    show paymentServiceProvider;
import 'package:flutter/services.dart';
import 'package:serenutos/providers/payment_terminal_provider.dart';
import 'package:serenutos/providers/hardware_config_provider.dart';
import 'package:serenutos/domain/services/mixed_payment_calculator.dart';
import 'package:serenutos/presentation/widgets/karma_payment_summary_bar.dart';

import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

part 'order_details/cash_out_sheet.dart';
part 'order_details/order_status_stepper.dart';
part 'order_details/order_info_card.dart';
part 'order_details/order_items_card.dart';

// ── POS Tema Renkleri ──────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kOrange = POSColors.orange;
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kAmber = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kSurface = POSColors.surface;
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

/// Provider — build() dışında tanımlanıyor (kritik bug düzeltmesi)
final _orderDetailProvider = FutureProvider.autoDispose
    .family<OrderEntity?, String>((ref, orderId) async {
  final repo = await ref.watch(orderRepositoryProvider.future);
  return repo.findById(orderId);
});

class OrderDetailsPage extends ConsumerWidget {
  final String orderId;
  final bool isModal;

  const OrderDetailsPage({
    super.key,
    required this.orderId,
    this.isModal = false,
  });

  /// Opens the OrderDetailsPage as a centered modal dialog on desktop
  /// or full-screen dialog on mobile devices.
  static Future<T?> show<T>(BuildContext context, {required String orderId}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    if (isDesktop) {
      return showDialog<T>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 960,
              maxHeight: 860,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: OrderDetailsPage(orderId: orderId, isModal: true),
            ),
          ),
        ),
      );
    } else {
      return Navigator.push<T>(
        context,
        MaterialPageRoute(
          builder: (routeCtx) => OrderDetailsPage(orderId: orderId, isModal: true),
          fullscreenDialog: true,
        ),
      );
    }
  }

  // Status flow
  static const _statusFlow = ['created', 'preparing', 'ready', 'delivered'];
  static const _statusLabels = {
    'created': 'Beklemede',
    'preparing': 'Hazırlanıyor',
    'ready': 'Hazır',
    'delivered': 'Teslim Edildi',
    'cancelled': 'İptal Edildi',
  };
  static const _statusIcons = {
    'created': Icons.hourglass_empty,
    'preparing': Icons.construction,
    'ready': Icons.inventory_2_outlined,
    'delivered': Icons.check_circle_outline,
    'cancelled': Icons.cancel_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Provider artık build() dışında ──
    final orderVal = ref.watch(_orderDetailProvider(orderId));
    final order = orderVal.valueOrNull;
    final customerId = order?.customerId ?? '';
    final customerAsync = customerId.isNotEmpty
        ? ref.watch(customerDetailProvider(customerId))
        : null;
    final customerLookupMap = ref.watch(customerLookupMapProvider).valueOrNull;
    final customer = customerAsync?.valueOrNull;
    final customerFallbackName =
        (customerId.isNotEmpty && customerLookupMap != null)
            ? customerLookupMap[customerId]
            : null;
    final settingsAsync = ref.watch(settingsNotifierProvider);
    // UUID â†’ ürün adı haritası
    final productsVal = ref.watch(productsControllerProvider);
    final productNameMap = productsVal.maybeWhen(
      data: (list) => {for (final p in list) p.id: p.name},
      orElse: () => <String, String>{},
    );

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        leading: isModal
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Kapat',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
            'Sipariş Detayı #${orderVal.valueOrNull?.displayNumber ?? orderId.toShortId}'),
        backgroundColor: Colors.white,
        foregroundColor: _kText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kGreen),
        actions: [
          orderVal.maybeWhen(
            data: (order) {
              if (order == null) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.print, color: _kGreen),
                    tooltip: 'Sipariş Fişi Yazdır',
                    onPressed: () async {
                      final settings = settingsAsync.value;
                      if (settings == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ayarlar yüklenemedi.')),
                        );
                        return;
                      }
                      final hasPrinter = await ref
                              .read(printingRepositoryProvider)
                              .getRoute(PrintDocumentKind.receipt) !=
                          null;
                      if (!context.mounted) return;
                      if (!hasPrinter) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Lütfen Ayarlar sayfasından bir yazıcı tanımlayın.'),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      try {
                        // Load customer
                        CustomerEntity? customerToUse = customer;
                        if (customerToUse == null &&
                            order.customerId.isNotEmpty) {
                          try {
                            final custRepo = await ref
                                .read(customerRepositoryProvider.future);
                            customerToUse =
                                await custRepo.findById(order.customerId);
                          } catch (_) {}
                        }

                        // Load products to map IDs to names
                        final products =
                            ref.read(productsControllerProvider).value ?? [];
                        final receiptItems = order.items.map((item) {
                          final prod = products.firstWhere(
                            (p) => p.id == item['product_id'],
                            orElse: () => ProductEntity(
                              id: item['product_id'] ?? '',
                              name: item['product_id'] ?? 'Urun',
                              description: '',
                              price: (item['unit_price'] as num?)?.toDouble() ??
                                  0.0,
                              quantity: 0,
                              category: '',
                            ),
                          );
                          return {
                            'product_id': item['product_id'],
                            'product_name': item['product_name'] ?? prod.name,
                            'barcode': prod.id,
                            'quantity': item['quantity'],
                            'unit_price': item['unit_price'],
                          };
                        }).toList();

                        await ref
                            .read(printingApplicationServiceProvider)
                            .queueOrderReceipt(
                              order,
                              receiptItems,
                              customerToUse != null && customerToUse.id.isNotEmpty
                                  ? customerToUse
                                  : (customer != null && customer.id.isNotEmpty
                                      ? customer
                                      : null),
                              settings,
                            );

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Yazdırma işlemi sıraya eklendi.'),
                            backgroundColor: POSColors.green,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e, st) {
                        unawaited(TelemetryService().logError(e, st, context: 'order_receipt_print'));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Yazdirma hatası: $e'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.local_offer_outlined, color: _kGreen),
                    tooltip: 'Sipariş Etiketi Yazdır',
                    onPressed: () async {
                      final settings = settingsAsync.valueOrNull;
                      if (settings == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ayarlar yüklenemedi.')),
                        );
                        return;
                      }
                      final route = await ref
                          .read(printingRepositoryProvider)
                          .getRoute(PrintDocumentKind.orderLabel);
                      if (!context.mounted) return;
                      if (route == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Sipariş etiketi için aktif yazıcı rotası seçilmedi.',
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      CustomerEntity? customerToUse = customer;
                      if (customerToUse == null &&
                          order.customerId.isNotEmpty) {
                        try {
                          final customerRepo =
                              await ref.read(customerRepositoryProvider.future);
                          customerToUse =
                              await customerRepo.findById(order.customerId);
                        } catch (_) {}
                      }
                      double totalPaid = 0.0;
                      try {
                        final txRepo = await ref
                            .read(financialTransactionRepositoryProvider.future);
                        final txs =
                            await txRepo.getByCustomerId(order.customerId);
                        for (final t in txs) {
                          if (t.referenceId == order.id) {
                            if (t.type == 'sale' || t.type == 'payment') {
                              totalPaid += t.paidAmount;
                            }
                          }
                        }
                      } catch (_) {}
                      final items = order.items.map((item) {
                        final normalized = Map<String, dynamic>.from(item);
                        final productId = item['product_id']?.toString() ?? '';
                        normalized['product_name'] = item['product_name'] ??
                            productNameMap[productId] ??
                            productId;
                        return normalized;
                      }).toList(growable: false);
                      try {
                        await ref
                            .read(printingApplicationServiceProvider)
                            .queueOrderLabel(
                              order,
                              items,
                              settings,
                              customer: customerToUse,
                              paidAmount: totalPaid,
                            );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Sipariş etiketi yazdırma kuyruğuna alındı.',
                            ),
                            backgroundColor: POSColors.green,
                          ),
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Sipariş etiketi hatası: $error'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                    tooltip: 'Siparişi Düzenle',
                    onPressed: () {
                      OrderCreationDialog.show(
                        context,
                        existingOrder: order,
                      ).then((_) {
                        ref.invalidate(_orderDetailProvider(orderId));
                      });
                    },
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.delete_outline_rounded, color: _kRed),
                    tooltip: 'Siparişi Sil',
                    onPressed: () => _confirmDelete(context, ref, order),
                  ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: orderVal.when(
        skipLoadingOnReload: true,
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Sipariş bulunamadı.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Delivery Countdown Badge ───────────────────────────────
                buildDeliveryCountdown(order),

                // ── Status Flow Stepper ────────────────────────────────────
                buildStatusStepper(context, ref, order),
                const SizedBox(height: 16),

                // ── Order Info Card ────────────────────────────────────────
                buildOrderInfoCard(
                    context, ref, order, customer, customerFallbackName),
                const SizedBox(height: 16),

                // ── Order Items ────────────────────────────────────────────
                if (order.items.isNotEmpty) ...[
                  const Text(
                    'Sipariş Kalemleri',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildOrderItemsCard(order, productNameMap),
                  const SizedBox(height: 16),
                ],

                // ── Actions ────────────────────────────────────────────────
                if (order.status != 'cancelled' && order.status != 'delivered')
                  _buildActionButtons(context, ref, order)
                else if (order.status == 'delivered')
                  _buildDeliveredActions(context, ref, order),

              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen),
          ),
        ),
        error: (e, _) => Center(child: Text('Hata: $e')),
      ),
    );
  }
}
