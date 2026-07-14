// lib/presentation/pages/order_details_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart'
    show paymentServiceProvider;
import 'package:flutter/services.dart';

// ── POS Tema Renkleri ──────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kAmber = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

/// Provider — build() dışında tanımlanıyor (kritik bug düzeltmesi)
final _orderDetailProvider = FutureProvider.autoDispose
    .family<OrderEntity?, String>((ref, orderId) async {
  ref.watch(ordersControllerProvider);
  final repo = await ref.watch(orderRepositoryProvider.future);
  return repo.findById(orderId);
});

class OrderDetailsPage extends ConsumerWidget {
  final String orderId;

  const OrderDetailsPage({super.key, required this.orderId});

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
    final customersVal = ref.watch(customersControllerProvider);
    final settingsAsync = ref.watch(settingsNotifierProvider);
    // UUID → ürün adı haritası
    final productsVal = ref.watch(productsControllerProvider);
    final productNameMap = productsVal.maybeWhen(
      data: (list) => {for (final p in list) p.id: p.name},
      orElse: () => <String, String>{},
    );

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        title: Text('Sipariş Detayı #${orderId.toShortId}'),
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
                      final hasPrinter = (settings.printerIp != null &&
                              settings.printerIp!.isNotEmpty) ||
                          (settings.printerName != null &&
                              settings.printerName!.isNotEmpty);
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
                        final customer = customersVal.maybeWhen(
                          data: (list) => list.firstWhere(
                            (c) => c.id == order.customerId,
                            orElse: () => CustomerEntity(
                                id: '',
                                name: 'Bilinmeyen Musteri',
                                email: '',
                                phone: '',
                                balance: 0,
                                createdAt: DateTime.now()),
                          ),
                          orElse: () => null,
                        );

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
                            'product_id': prod.name,
                            'quantity': item['quantity'],
                            'unit_price': item['unit_price'],
                          };
                        }).toList();

                        ref.read(printerServiceProvider).enqueue(
                              'Hazırlama Fişi #${order.id.toShortId}',
                              () => ref
                                  .read(printerServiceProvider)
                                  .printOrderReceipt(
                                    order,
                                    receiptItems,
                                    customer != null && customer.id.isNotEmpty
                                        ? customer
                                        : null,
                                    settings,
                                  ),
                            );

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Yazdırma işlemi sıraya eklendi.'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e) {
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
                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                    tooltip: 'Siparişi Düzenle',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              OrderCreationDialog(existingOrder: order),
                          fullscreenDialog: true,
                        ),
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
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Sipariş bulunamadı.'));
          }

          final customer = customersVal.maybeWhen(
            data: (list) {
              try {
                return list.firstWhere((c) => c.id == order.customerId);
              } catch (_) {
                return null;
              }
            },
            orElse: () => null,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Delivery Countdown Badge ───────────────────
                _buildDeliveryCountdown(order),

                // ── Status Flow Stepper ─────────────────────────
                _buildStatusStepper(context, ref, order),
                const SizedBox(height: 16),

                // ── Order Info Card ─────────────────────────────
                _buildOrderInfoCard(context, ref, order, customer),
                const SizedBox(height: 16),

                // ── Order Items ─────────────────────────────────
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
                  _buildOrderItemsCard(order.items, productNameMap),
                  const SizedBox(height: 16),
                ],

                // ── Actions ─────────────────────────────────────
                if (order.status != 'cancelled' && order.status != 'delivered')
                  _buildActionButtons(context, ref, order),
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

  Widget _buildStatusStepper(
      BuildContext context, WidgetRef ref, OrderEntity order) {
    final isCancelled = order.status == 'cancelled';
    final isDelivered = order.status == 'delivered';
    final currentIndex =
        isCancelled ? -1 : _statusFlow.indexOf(order.status.toLowerCase());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: isCancelled
                      ? _kRedLight
                      : isDelivered
                          ? _kGreenLight
                          : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(
                isCancelled
                    ? Icons.cancel_rounded
                    : isDelivered
                        ? Icons.check_circle_rounded
                        : Icons.local_shipping_rounded,
                size: 14,
                color: isCancelled
                    ? _kRed
                    : isDelivered
                        ? _kGreenDark
                        : _kTextSecondary,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Durum Akışı',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: _kText)),
          ]),
          const SizedBox(height: 16),

          if (isCancelled)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _kRedLight, borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.cancel_rounded, color: _kRed),
                SizedBox(width: 10),
                Expanded(
                    child: Text('Bu sipariş iptal edildi.',
                        style: TextStyle(
                            color: _kRed, fontWeight: FontWeight.bold))),
              ]),
            )
          else ...[
            _buildPillStepper(context, ref, order, currentIndex),
            const SizedBox(height: 16)
          ],

          // ── Aksiyon Butonları ──────────────────────────────────────────
          if (!isCancelled && order.status != 'delivered')
            ..._buildActionRow(context, ref, order),
        ],
      ),
    );
  }

  Widget _buildPillStepper(BuildContext context, WidgetRef ref,
      OrderEntity order, int currentIndex) {
    return Column(
      children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:
                currentIndex < 0 ? 0 : (currentIndex + 1) / _statusFlow.length,
            minHeight: 6,
            backgroundColor: _kBorder,
            valueColor: const AlwaysStoppedAnimation(_kGreen),
          ),
        ),
        const SizedBox(height: 12),
        // Steps row
        Row(
          children: _statusFlow.asMap().entries.map((entry) {
            final stepIndex = entry.key;
            final status = entry.value;
            final isDone = stepIndex <= currentIndex;
            final isCurrent = stepIndex == currentIndex;

            return Expanded(
              child: InkWell(
                onTap: () {
                  if (order.status != status) {
                    if (status == 'delivered') {
                      _handleDelivery(context, ref, order);
                    } else {
                      ref
                          .read(ordersControllerProvider.notifier)
                          .updateStatus(order.id, status);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Durum güncellendi: ${_statusLabels[status]}'),
                          backgroundColor: _kGreenDark,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone ? _kGreen : _kBorder,
                          border: isCurrent
                              ? Border.all(color: _kGreenDark, width: 2.5)
                              : null,
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: _kGreen.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    spreadRadius: 2,
                                  )
                                ]
                              : null,
                        ),
                        child: Icon(
                          _statusIcons[status] ?? Icons.circle,
                          size: 18,
                          color: isDone ? Colors.white : _kTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _statusLabels[status] ?? status,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isCurrent ? FontWeight.w800 : FontWeight.w500,
                          color: isDone ? _kGreenDark : _kTextSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  List<Widget> _buildActionRow(
      BuildContext context, WidgetRef ref, OrderEntity order) {
    final isDeliveryStep = order.status == 'ready';

    return [
      // VADELİ uyarısı — teslim adımında borçlu müşteriler için
      if (isDeliveryStep &&
          order.items.any((item) =>
              item['payment_method']?.toString() == 'vadeli' ||
              ((item['debt_amount'] as num?)?.toDouble() ?? 0) > 0))
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kAmberLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, size: 16, color: _kAmber),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'VADELİ sipariş — Teslimata izin verilir, borç cari hesapta kalır.',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Durumu değiştirmek için yukarıdaki adımlara dokunabilirsiniz.',
                    style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _confirmCancel(context, ref, order),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kRed,
              side: const BorderSide(color: _kRed),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.cancel_rounded, size: 16),
            label: const Text('İptal Et',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    ];
  }

  String _nextStepLabel(String status) {
    switch (status) {
      case 'created':
        return 'Hazırlamaya Başla';
      case 'preparing':
        return 'Hazır İşaretle';
      case 'ready':
        return 'Teslim Et';
      default:
        return 'Devam';
    }
  }

  String _nextStatus(String current) {
    final idx = _statusFlow.indexOf(current);
    if (idx < _statusFlow.length - 1) return _statusFlow[idx + 1];
    return current;
  }

  void _advanceStatus(BuildContext context, WidgetRef ref, OrderEntity order) {
    final next = _nextStatus(order.status);
    ref.read(ordersControllerProvider.notifier).updateStatus(order.id, next);

    // VADELİ teslim bilgilendirmesi
    final isVadeli = order.items.any((item) =>
        item['payment_method']?.toString() == 'vadeli' ||
        ((item['debt_amount'] as num?)?.toDouble() ?? 0) > 0);
    final msg = next == 'delivered' && isVadeli
        ? 'Teslim edildi ✓ — Borç cari hesapta kayıtlı.'
        : 'Durum güncellendi: ${_statusLabels[next]}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _kGreenDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, OrderEntity order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Siparişi İptal Et'),
        content:
            const Text('Bu siparişi iptal etmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(ordersControllerProvider.notifier)
                  .updateStatus(order.id, 'cancelled');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Sipariş iptal edildi.'),
                    backgroundColor: Colors.red),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
  }

  Future<void> _makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _sendSms(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, OrderEntity order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Siparişi Sil'),
        content: const Text(
            'Bu sipariş kaydını tamamen silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);

              final txRepo =
                  await ref.read(financialTransactionRepositoryProvider.future);
              final transactions =
                  await txRepo.getByCustomerId(order.customerId);
              FinancialTransactionEntity? orderTx;
              for (final t in transactions) {
                if (t.referenceId == order.id && t.type == 'sale') {
                  orderTx = t;
                  break;
                }
              }

              if (orderTx != null && orderTx.debtAmount > 0) {
                final customerRepo =
                    await ref.read(customerRepositoryProvider.future);
                await customerRepo.updateBalance(
                    order.customerId, orderTx.debtAmount);
              }

              if (orderTx != null) {
                await txRepo.delete(orderTx.id);
              }

              await ref
                  .read(ordersControllerProvider.notifier)
                  .deleteOrder(order.id);

              ref.invalidate(dashboardProvider);
              ref.invalidate(productsControllerProvider);
              ref.invalidate(customerTransactionsProvider(order.customerId));
              ref.invalidate(customerBalanceDetailsProvider(order.customerId));
              await ref.read(customersControllerProvider.notifier).refresh();

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Sipariş başarıyla silindi.'),
                      backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryCountdown(OrderEntity order) {
    if (order.status == 'delivered' ||
        order.status == 'cancelled' ||
        order.expectedDeliveryDate == null) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final deliveryDate = order.expectedDeliveryDate!;
    final diff = deliveryDate.difference(now);
    final isOverdue = diff.isNegative;

    String text;
    Color bgColor;
    Color textColor;
    IconData icon;

    if (isOverdue) {
      final days = diff.inDays.abs();
      if (days > 0) {
        text = 'Gecikmiş - $days gün';
      } else {
        final hours = diff.inHours.abs();
        text = 'Gecikmiş - $hours saat';
      }
      bgColor = _kRedLight;
      textColor = _kRed;
      icon = Icons.warning_amber_rounded;
    } else {
      final days = diff.inDays;
      if (days > 0) {
        text = 'Teslimata $days gün kaldı';
      } else {
        final hours = diff.inHours;
        if (hours > 0) {
          text = 'Teslimata $hours saat kaldı';
        } else {
          final minutes = diff.inMinutes;
          text = 'Teslimata $minutes dakika kaldı';
        }
      }
      bgColor = _kGreenLight;
      textColor = _kGreenDark;
      icon = Icons.timer_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodRow(WidgetRef ref, OrderEntity order) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref
          .read(financialTransactionRepositoryProvider.future)
          .then((repo) async {
        final txs = await repo.getByCustomerId(order.customerId);
        FinancialTransactionEntity? saleTx;
        double totalPaid = 0.0;
        for (final t in txs) {
          if (t.referenceId == order.id) {
            if (t.type == 'sale') {
              saleTx = t;
              totalPaid += t.paidAmount;
            } else if (t.type == 'payment') {
              totalPaid += t.paidAmount;
            }
          }
        }
        return {
          'saleTx': saleTx,
          'totalPaid': totalPaid,
        };
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _infoRow(
              'Ödeme Yöntemi', 'Yükleniyor...', Icons.payment_rounded);
        }
        final data = snapshot.data;
        final saleTx = data?['saleTx'] as FinancialTransactionEntity?;
        final totalPaid = data?['totalPaid'] as double? ?? 0.0;

        if (saleTx == null) {
          return _infoRow('Ödeme Yöntemi', 'Bilinmiyor', Icons.payment_rounded);
        }

        final double totalAmount = saleTx.amount;
        final double remainingDebt =
            (totalAmount - totalPaid).clamp(0.0, double.infinity);

        String display = '';
        if (remainingDebt <= 0.01) {
          display = 'Ödendi';
        } else if (totalPaid <= 0.01) {
          display = 'Vadeli';
        } else {
          display = 'Kısmi Ödeme';
        }

        return Column(
          children: [
            _infoRow(
              'Ödeme Yöntemi',
              display,
              Icons.payment_rounded,
              positive: remainingDebt <= 0.01,
              isRed: remainingDebt > 0.01,
            ),
            const Divider(height: 20),
            _infoRow(
              'Ödenen Miktar',
              '₺${totalPaid.toStringAsFixed(2)}',
              Icons.check_circle_outline_rounded,
              positive: totalPaid > 0,
            ),
            const Divider(height: 20),
            _infoRow(
              'Kalan Borç',
              '₺${remainingDebt.toStringAsFixed(2)}',
              Icons.account_balance_wallet_outlined,
              isRed: remainingDebt > 0.01,
              positive: remainingDebt <= 0.01,
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrderInfoCard(BuildContext context, WidgetRef ref,
      OrderEntity order, CustomerEntity? customer) {
    final customerName = customer?.name ?? 'Bilinmeyen Müşteri';
    final hasPhone = customer != null && customer.phone.isNotEmpty;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Müşteri',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ),
                Text(customerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontSize: 14)),
                if (hasPhone) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _makeCall(customer.phone),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: _kGreenLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone_rounded,
                          color: _kGreen, size: 14),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _sendSms(customer.phone),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.sms_rounded,
                          color: Colors.blue[700], size: 14),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 20),
            _buildPaymentMethodRow(ref, order),
            const Divider(height: 20),
            _infoRow(
                'Oluşturma',
                DateFormat('dd.MM.yyyy HH:mm').format(order.createdAt),
                Icons.calendar_today_outlined),
            if (order.expectedDeliveryDate != null) ...[
              const Divider(height: 20),
              _infoRow(
                  'Teslim Tarihi',
                  DateFormat('dd.MM.yyyy').format(order.expectedDeliveryDate!),
                  Icons.local_shipping_outlined,
                  isOverdue: order.isOverdue),
            ],
            if (order.actualDeliveryDate != null) ...[
              const Divider(height: 20),
              _infoRow(
                  'Teslim Edildi',
                  DateFormat('dd.MM.yyyy HH:mm')
                      .format(order.actualDeliveryDate!),
                  Icons.check_circle_outline,
                  positive: true),
            ],
            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const Divider(height: 20),
              _infoRow('Notlar', order.notes!, Icons.notes_rounded),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon,
      {bool isOverdue = false, bool positive = false, bool isRed = false}) {
    final color = isOverdue || isRed
        ? Colors.red[700]!
        : positive
            ? _kGreen
            : Colors.black87;
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: color, fontSize: 14)),
        if (isOverdue) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.red[50], borderRadius: BorderRadius.circular(4)),
            child: const Text('GECİKMİŞ',
                style: TextStyle(
                    color: Color(0xFFC2410C),
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  Future<void> _handleDelivery(
      BuildContext context, WidgetRef ref, OrderEntity order) async {
    final txRepo =
        await ref.read(financialTransactionRepositoryProvider.future);
    final txs = await txRepo.getByCustomerId(order.customerId);
    FinancialTransactionEntity? saleTx;
    double totalPaid = 0.0;
    for (final t in txs) {
      if (t.referenceId == order.id) {
        if (t.type == 'sale') {
          saleTx = t;
          totalPaid += t.paidAmount;
        } else if (t.type == 'payment') {
          totalPaid += t.paidAmount;
        }
      }
    }

    if (saleTx == null) {
      await ref
          .read(ordersControllerProvider.notifier)
          .updateStatus(order.id, 'delivered');
      _triggerPrint(ref, order);
      return;
    }

    final double remainingDebt =
        (saleTx.amount - totalPaid).clamp(0.0, double.infinity);

    if (remainingDebt <= 0.01) {
      await ref
          .read(ordersControllerProvider.notifier)
          .updateStatus(order.id, 'delivered');
      _triggerPrint(ref, order);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Sipariş teslim edildi ve fiş yazdırıldı.'),
              backgroundColor: _kGreen),
        );
      }
      return;
    }

    if (context.mounted) {
      _showCashOutBottomSheet(context, ref, order, saleTx, totalPaid);
    }
  }

  void _showCashOutBottomSheet(
    BuildContext context,
    WidgetRef ref,
    OrderEntity order,
    FinancialTransactionEntity saleTx,
    double totalPaid,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CashOutSheet(
          order: order,
          saleTx: saleTx,
          totalPaid: totalPaid,
        ),
        fullscreenDialog: true,
      ),
    );
  }
}

// ── Top-Level Helper For Printing ───────────────────────────────────────────
Future<void> _triggerPrint(WidgetRef ref, OrderEntity order) async {
  final settingsAsync = ref.read(settingsNotifierProvider);
  final settings = settingsAsync.value;
  if (settings == null) return;
  final hasPrinter =
      (settings.printerIp != null && settings.printerIp!.isNotEmpty) ||
          (settings.printerName != null && settings.printerName!.isNotEmpty);
  if (!hasPrinter) return;

  try {
    final customersVal = ref.read(customersControllerProvider);
    final customer = customersVal.maybeWhen(
      data: (list) => list.firstWhere(
        (c) => c.id == order.customerId,
        orElse: () => CustomerEntity(
            id: '',
            name: 'Bilinmeyen Musteri',
            email: '',
            phone: '',
            balance: 0,
            createdAt: DateTime.now()),
      ),
      orElse: () => null,
    );

    final products = ref.read(productsControllerProvider).value ?? [];
    final receiptItems = order.items.map((item) {
      final prod = products.firstWhere(
        (p) => p.id == item['product_id'],
        orElse: () => ProductEntity(
          id: item['product_id'] ?? '',
          name: item['product_id'] ?? 'Urun',
          description: '',
          price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          quantity: 0,
          category: '',
        ),
      );
      return {
        'product_id': prod.name,
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
      };
    }).toList();

    ref.read(printerServiceProvider).enqueue(
          'Hazırlama Fişi #${order.id.toShortId}',
          () => ref.read(printerServiceProvider).printOrderReceipt(
                order,
                receiptItems,
                customer != null && customer.id.isNotEmpty ? customer : null,
                settings,
              ),
        );
  } catch (e) {
    debugPrint('Printing error in delivery: $e');
  }
}

// ── Cash Out Bottom Sheet Widget ─────────────────────────────────────────────
class _CashOutSheet extends ConsumerStatefulWidget {
  final OrderEntity order;
  final FinancialTransactionEntity saleTx;
  final double totalPaid;

  const _CashOutSheet({
    required this.order,
    required this.saleTx,
    required this.totalPaid,
  });

  @override
  ConsumerState<_CashOutSheet> createState() => _CashOutSheetState();
}

class _CashOutSheetState extends ConsumerState<_CashOutSheet> {
  String _selectedMethod = 'cash'; // 'cash', 'card', 'debt', 'karma'

  final TextEditingController _karmaCashController = TextEditingController();
  final TextEditingController _karmaCardController = TextEditingController();
  final TextEditingController _karmaDebtController = TextEditingController();

  bool _isSubmitting = false;
  bool _printReceipt = true;
  int _printCopies = 1;
  bool _printLabel = false;
  int _labelCopies = 1;

  @override
  void initState() {
    super.initState();
    _loadLabelPrinterSettings();
  }

  Future<void> _loadLabelPrinterSettings() async {
    try {
      // Read label_printer_enabled from SQLite settings (single source of truth)
      final settings = ref.read(settingsNotifierProvider).valueOrNull;
      if (settings != null && mounted) {
        setState(() {
          _printLabel = settings.labelPrinterEnabled;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLabelPrinterSettings() async {
    try {
      // Write label_printer_enabled to SQLite settings (single source of truth)
      final current = ref.read(settingsNotifierProvider).valueOrNull;
      if (current != null) {
        await ref
            .read(settingsNotifierProvider.notifier)
            .updateSettings(current.copyWith(labelPrinterEnabled: _printLabel));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _karmaCashController.dispose();
    _karmaCardController.dispose();
    _karmaDebtController.dispose();
    super.dispose();
  }

  double get _remainingAmount =>
      (widget.saleTx.amount - widget.totalPaid).clamp(0.0, double.infinity);

  double get _karmaCash =>
      double.tryParse(_karmaCashController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaCard =>
      double.tryParse(_karmaCardController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaDebt =>
      double.tryParse(_karmaDebtController.text.replaceAll(',', '.')) ?? 0.0;

  double get _karmaTotal => _karmaCash + _karmaCard + _karmaDebt;
  double get _karmaRemainder =>
      (_remainingAmount - _karmaTotal).clamp(0.0, double.infinity);
  bool get _karmaValid =>
      _remainingAmount > 0 && (_karmaTotal - _remainingAmount).abs() < 0.01;

  Future<void> _submitPayment() async {
    setState(() {
      _isSubmitting = true;
    });

    final remaining = _remainingAmount;

    try {
      final paymentService = await ref.read(paymentServiceProvider.future);

      if (_selectedMethod == 'cash') {
        if (remaining > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: remaining,
            method: 'cash',
            currentPaidAmount: widget.totalPaid,
            totalAmount: widget.saleTx.amount,
          );
        }
      } else if (_selectedMethod == 'card') {
        if (remaining > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: remaining,
            method: 'card',
            currentPaidAmount: widget.totalPaid,
            totalAmount: widget.saleTx.amount,
          );
        }
      } else if (_selectedMethod == 'karma') {
        double currentPaid = widget.totalPaid;
        final kCash = _karmaCash;
        final kCard = _karmaCard;

        if (kCash > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: kCash,
            method: 'cash',
            currentPaidAmount: currentPaid,
            totalAmount: widget.saleTx.amount,
          );
          currentPaid += kCash;
        }
        if (kCard > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: kCard,
            method: 'card',
            currentPaidAmount: currentPaid,
            totalAmount: widget.saleTx.amount,
          );
        }
      }

      await ref
          .read(ordersControllerProvider.notifier)
          .updateStatus(widget.order.id, 'delivered');

      await ref.read(customersControllerProvider.notifier).refresh();
      ref.invalidate(customerTransactionsProvider(widget.order.customerId));
      ref.invalidate(customerBalanceDetailsProvider(widget.order.customerId));
      ref.invalidate(_orderDetailProvider(widget.order.id));

      // Print Fiş (Receipt)
      if (_printReceipt) {
        final settingsAsync = ref.read(settingsNotifierProvider);
        final settings = settingsAsync.value;
        if (settings != null) {
          final hasPrinter =
              (settings.printerIp != null && settings.printerIp!.isNotEmpty) ||
                  (settings.printerName != null &&
                      settings.printerName!.isNotEmpty);
          if (hasPrinter) {
            final customersVal = ref.read(customersControllerProvider);
            final customer = customersVal.maybeWhen(
              data: (list) => list.firstWhere(
                (c) => c.id == widget.order.customerId,
                orElse: () => CustomerEntity(
                    id: '',
                    name: 'Bilinmeyen Musteri',
                    email: '',
                    phone: '',
                    balance: 0,
                    createdAt: DateTime.now()),
              ),
              orElse: () => null,
            );

            final products = ref.read(productsControllerProvider).value ?? [];
            final receiptItems = widget.order.items.map((item) {
              final prod = products.firstWhere(
                (p) => p.id == item['product_id'],
                orElse: () => ProductEntity(
                  id: item['product_id'] ?? '',
                  name: item['product_id'] ?? 'Urun',
                  description: '',
                  price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
                  quantity: 0,
                  category: '',
                ),
              );
              return {
                'product_id': prod.name,
                'quantity': item['quantity'],
                'unit_price': item['unit_price'],
              };
            }).toList();

            final double currentFinalPaid = widget.totalPaid +
                (_selectedMethod == 'cash'
                    ? remaining
                    : (_selectedMethod == 'card'
                        ? remaining
                        : (_selectedMethod == 'karma'
                            ? _karmaCash + _karmaCard
                            : 0.0)));

            for (int i = 0; i < _printCopies; i++) {
              final suffix = _printCopies > 1 ? ' (Kopya ${i + 1})' : '';
              ref.read(printerServiceProvider).enqueue(
                    'Sipariş Fişi #${widget.order.id.toShortId}$suffix',
                    () => ref.read(printerServiceProvider).printOrderReceipt(
                          widget.order,
                          receiptItems,
                          customer != null && customer.id.isNotEmpty
                              ? customer
                              : null,
                          settings,
                          paidAmount: currentFinalPaid,
                          notes: widget.order.notes?.trim(),
                        ),
                  );
            }
          }
        }
      }

      // Print Label stickers
      if (_printLabel) {
        final settingsAsync = ref.read(settingsNotifierProvider);
        final settings = settingsAsync.value;
        if (settings != null) {
          // Read label printer config from SQLite settings (single source of truth)
          final labelIp = settings.labelPrinterIp ?? '';
          final labelPort = settings.labelPrinterPort ?? 9100;
          final labelSettings = settings.copyWith(
            printerName: 'network',
            printerIp: labelIp.isNotEmpty ? labelIp : settings.printerIp,
            printerPort: labelPort,
          );

          final products = ref.read(productsControllerProvider).value ?? [];
          final receiptItems = widget.order.items.map((item) {
            final prod = products.firstWhere(
              (p) => p.id == item['product_id'],
              orElse: () => ProductEntity(
                id: item['product_id'] ?? '',
                name: item['product_id'] ?? 'Urun',
                description: '',
                price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
                quantity: 0,
                category: '',
              ),
            );
            return {
              'product_id': prod.name,
              'quantity': item['quantity'],
              'unit_price': item['unit_price'],
            };
          }).toList();

          for (int i = 0; i < _labelCopies; i++) {
            final suffix = _labelCopies > 1 ? ' (Kopya ${i + 1})' : '';
            ref.read(printerServiceProvider).enqueue(
                  'Sipariş Etiketleri #${widget.order.id.toShortId}$suffix',
                  () => ref.read(printerServiceProvider).printOrderLabels(
                        widget.order,
                        receiptItems,
                        labelSettings,
                      ),
                );
          }
        }
      }

      if (mounted) {
        Navigator.pop(context);

        String msg = '';
        if (_selectedMethod == 'debt') {
          msg = 'Sipariş vadeli olarak teslim edildi.';
        } else {
          msg = 'Ödeme alındı ve sipariş teslim edildi.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: _kGreenDark,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingAmount;
    final isKarma = _selectedMethod == 'karma';
    final karmaTotal = _karmaTotal;
    final karmaValid = _karmaValid;
    final karmaRemaining = _karmaRemainder;

    final bool isActionDisabled = _selectedMethod == 'karma' && !karmaValid;

    // Load reactive customer details
    final customersVal = ref.watch(customersControllerProvider);
    final customer = customersVal.maybeWhen(
      data: (list) => list.firstWhere(
        (c) => c.id == widget.order.customerId,
        orElse: () => CustomerEntity(
            id: '',
            name: 'Bilinmeyen Musteri',
            email: '',
            phone: '',
            balance: 0.0,
            createdAt: DateTime.now()),
      ),
      orElse: () => null,
    );

    // Left column (Summary Info)
    final leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Sipariş Bilgileri',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        _buildSummaryRow(
          icon: Icons.person_outline_rounded,
          label: 'Seçilen Müşteri',
          value: customer?.name ?? 'Yükleniyor...',
        ),
        if (customer != null)
          _buildSummaryRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Müşteri Bakiyesi',
            value:
                '₺${customer.balance.abs().toStringAsFixed(2)} ${customer.balance < 0 ? "(Borçlu)" : "(Alacaklı)"}',
            valueColor: customer.balance < 0 ? _kRed : _kGreenDark,
          ),
        _buildSummaryRow(
          icon: Icons.calendar_month_outlined,
          label: 'Teslimat Tarihi',
          value: widget.order.expectedDeliveryDate != null
              ? DateFormat('dd.MM.yyyy')
                  .format(widget.order.expectedDeliveryDate!)
              : 'Belirtilmedi',
        ),
        if (widget.order.notes != null && widget.order.notes!.trim().isNotEmpty)
          _buildSummaryRow(
            icon: Icons.notes_rounded,
            label: 'Not',
            value: widget.order.notes!.trim(),
          ),
      ],
    );

    // Right column (Payment Grid + Dynamic Inputs + Printer Settings)
    final rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Ödeme Yöntemi Seçin',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        // Totals box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isKarma && karmaTotal > 0)
                Text(
                  'Kalan: ₺${karmaRemaining.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: karmaValid ? _kGreenDark : _kRed,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                const SizedBox.shrink(),
              Text(
                '₺${remaining.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: _kGreenDark,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Karma Split Input Fields
        if (isKarma) ...[
          _buildKarmaFields(remaining, karmaValid, karmaRemaining),
          const SizedBox(height: 12),
        ],
        // Payment Button Grid
        _buildMethodsGrid(remaining),
        const SizedBox(height: 16),
        // Receipt & Label Printer Controls
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(() => _printReceipt = !_printReceipt),
                icon: Icon(
                  _printReceipt
                      ? Icons.print_rounded
                      : Icons.print_disabled_rounded,
                  color: _printReceipt ? _kGreen : _kTextSecondary,
                  size: 20,
                ),
                tooltip:
                    _printReceipt ? 'Fiş Yazdırma Açık' : 'Fiş Yazdırma Kapalı',
                style: IconButton.styleFrom(
                  backgroundColor: _printReceipt ? _kGreenLight : Colors.white,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _printReceipt
                          ? _kGreen.withValues(alpha: 0.3)
                          : _kBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _InlineCopyCountField(
                value: _printCopies,
                isEnabled: _printReceipt,
                onChanged: (val) {
                  setState(() => _printCopies = val);
                },
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: () {
                  setState(() => _printLabel = !_printLabel);
                  _saveLabelPrinterSettings();
                },
                icon: Icon(
                  _printLabel
                      ? Icons.label_rounded
                      : Icons.label_outline_rounded,
                  color: _printLabel ? _kGreen : _kTextSecondary,
                  size: 20,
                ),
                tooltip:
                    _printLabel ? 'Etiket Yazıcı Açık' : 'Etiket Yazıcı Kapalı',
                style: IconButton.styleFrom(
                  backgroundColor: _printLabel ? _kGreenLight : Colors.white,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _printLabel
                          ? _kGreen.withValues(alpha: 0.3)
                          : _kBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _InlineCopyCountField(
                value: _labelCopies,
                isEnabled: _printLabel,
                onChanged: (val) {
                  setState(() => _labelCopies = val);
                  _saveLabelPrinterSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Teslim Et & Ödeme Al',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
            Text(
              'Sipariş #${widget.order.id.toShortId}',
              style: const TextStyle(
                fontSize: 11,
                color: _kTextSecondary,
              ),
            ),
          ],
        ),
        backgroundColor: _kSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _kText),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, color: _kBorder),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isWide = constraints.maxWidth >= 600;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: leftCol,
                        ),
                      ),
                      const VerticalDivider(width: 1, color: _kBorder),
                      Expanded(
                        flex: 5,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: rightCol,
                        ),
                      ),
                    ],
                  );
                } else {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leftCol,
                        const Divider(height: 32, color: _kBorder),
                        rightCol,
                      ],
                    ),
                  );
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_isSubmitting || isActionDisabled)
                      ? null
                      : _submitPayment,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded,
                          size: 20),
                  label: Text(
                    _isSubmitting
                        ? 'Ödeme Kaydediliyor...'
                        : 'Ödemeyi Tamamla & Teslim Et',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
      {required IconData icon,
      required String label,
      required String value,
      Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _kTextSecondary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: _kTextSecondary, fontSize: 12))),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: valueColor ?? _kText)),
        ],
      ),
    );
  }

  Widget _buildMethodsGrid(double remaining) {
    final methods = [
      {
        'id': 'cash',
        'label': 'Nakit',
        'icon': Icons.payments_rounded,
        'color': _kGreen
      },
      {
        'id': 'card',
        'label': 'Kart',
        'icon': Icons.credit_card_rounded,
        'color': Colors.blue
      },
      {
        'id': 'debt',
        'label': 'Vadeli (Borç)',
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.orange
      },
      {
        'id': 'karma',
        'label': 'Karma (Split)',
        'icon': Icons.call_split_rounded,
        'color': Colors.purple
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double aspectRatio = constraints.maxWidth > 400 ? 2.4 : 3.0;

        return GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: aspectRatio,
          physics: const NeverScrollableScrollPhysics(),
          children: methods.map((m) {
            final isSel = _selectedMethod == m['id'];
            final color = m['color'] as Color;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedMethod = m['id'] as String;
                  if (_selectedMethod == 'karma') {
                    _karmaCashController.text = remaining.toStringAsFixed(2);
                    _karmaCardController.text = '0.00';
                    _karmaDebtController.text = '0.00';
                  }
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: isSel ? color : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSel ? color : _kBorder),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      m['icon'] as IconData,
                      color: isSel ? Colors.white : color,
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m['label'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isSel ? Colors.white : _kText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _onSplitFieldChanged(
      String field, String valStr, double remaining, bool hasCustomer) {
    final val = double.tryParse(valStr.replaceAll(',', '.')) ?? 0.0;

    if (!hasCustomer) {
      _karmaDebtController.text = '0.00';
      if (field == 'cash') {
        final cardVal = (remaining - val).clamp(0.0, remaining);
        _karmaCardController.text = cardVal.toStringAsFixed(2);
      } else if (field == 'card') {
        final cashVal = (remaining - val).clamp(0.0, remaining);
        _karmaCashController.text = cashVal.toStringAsFixed(2);
      }
    } else {
      if (field == 'cash') {
        final currentCard =
            double.tryParse(_karmaCardController.text.replaceAll(',', '.')) ??
                0.0;
        final debtVal = (remaining - (val + currentCard)).clamp(0.0, remaining);
        _karmaDebtController.text = debtVal.toStringAsFixed(2);
      } else if (field == 'card') {
        final currentCash =
            double.tryParse(_karmaCashController.text.replaceAll(',', '.')) ??
                0.0;
        final debtVal = (remaining - (currentCash + val)).clamp(0.0, remaining);
        _karmaDebtController.text = debtVal.toStringAsFixed(2);
      } else if (field == 'debt') {
        final currentCash =
            double.tryParse(_karmaCashController.text.replaceAll(',', '.')) ??
                0.0;
        final cardVal = (remaining - (currentCash + val)).clamp(0.0, remaining);
        _karmaCardController.text = cardVal.toStringAsFixed(2);
      }
    }
    setState(() {});
  }

  Widget _buildSplitField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    required String fieldId,
    required double remaining,
    required bool hasCustomer,
    bool isEnabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: isEnabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: isEnabled ? color : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 11),
        prefixIcon:
            Icon(icon, color: isEnabled ? color : Colors.grey, size: 16),
        prefixText: '₺',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        isDense: true,
      ),
      onChanged: (val) =>
          _onSplitFieldChanged(fieldId, val, remaining, hasCustomer),
    );
  }

  Widget _buildKarmaFields(
      double remaining, bool karmaValid, double karmaRemaining) {
    final customerId = widget.order.customerId;
    final bool hasCustomer = customerId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: karmaValid ? _kGreen.withValues(alpha: 0.4) : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split_rounded,
                  size: 14, color: _kTextSecondary),
              const SizedBox(width: 6),
              const Text('Karma Ödeme Dağılımı',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (karmaValid)
                const Text('✓ Tamam',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kGreenDark,
                        fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildSplitField(
                  controller: _karmaCashController,
                  label: 'Nakit',
                  icon: Icons.payments_rounded,
                  color: _kGreen,
                  fieldId: 'cash',
                  remaining: remaining,
                  hasCustomer: hasCustomer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSplitField(
                  controller: _karmaCardController,
                  label: 'Kart',
                  icon: Icons.credit_card_rounded,
                  color: Colors.blue,
                  fieldId: 'card',
                  remaining: remaining,
                  hasCustomer: hasCustomer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSplitField(
                  controller: _karmaDebtController,
                  label: 'Vadeli',
                  icon: Icons.account_balance_wallet_rounded,
                  color: Colors.orange,
                  fieldId: 'debt',
                  remaining: remaining,
                  hasCustomer: hasCustomer,
                  isEnabled: hasCustomer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Copy Count Field For Bottom Sheet ────────────────────────────────────────
class _InlineCopyCountField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool isEnabled;

  const _InlineCopyCountField({
    required this.value,
    required this.onChanged,
    this.isEnabled = true,
  });

  @override
  State<_InlineCopyCountField> createState() => _InlineCopyCountFieldState();
}

class _InlineCopyCountFieldState extends State<_InlineCopyCountField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_InlineCopyCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value.toString();
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _submitValue();
    }
  }

  void _submitValue() {
    final val = int.tryParse(_controller.text);
    if (val != null && val >= 1) {
      widget.onChanged(val);
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = widget.isEnabled
        ? Colors.white
        : (isDark ? Colors.black26 : Colors.grey.shade100);

    final Color borderColor = widget.isEnabled
        ? _kBorder
        : (isDark ? Colors.white24 : Colors.grey.shade300);

    final Color textColor =
        widget.isEnabled ? _kText : _kTextSecondary.withValues(alpha: 0.5);

    return Container(
      width: 36,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.isEnabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onSubmitted: (_) {
          _submitValue();
          _focusNode.unfocus();
        },
      ),
    );
  }
}

Widget _buildOrderItemsCard(
  List<Map<String, dynamic>> items,
  Map<String, String> productNameMap,
) {
  double total = 0;
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
            final price = item['unit_price'] as double? ?? 0.0;
            final itemTotal = qty * price;
            total += itemTotal;
            final productId = item['product_id']?.toString() ?? '';
            final productName = productNameMap[productId] ??
                item['product_name']?.toString() ??
                productId;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _kGreenLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            _formatQuantity(qty),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _kGreen,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _kText,
                              ),
                            ),
                            Text(
                              '${price.toStringAsFixed(2)} TL x $qty',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _kTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${itemTotal.toStringAsFixed(2)} TL',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < items.length - 1) const Divider(height: 1, indent: 42),
              ],
            );
          }),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Toplam',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _kText,
                ),
              ),
              Text(
                '${total.toStringAsFixed(2)} TL',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: _kGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _buildActionButtons(
    BuildContext context, WidgetRef ref, OrderEntity order) {
  return const SizedBox.shrink(); // Action row now lives inside stepper
}

String _formatQuantity(double qty) {
  if (qty == qty.toInt()) {
    return qty.toInt().toString();
  }
  return qty.toString();
}
