part of '../order_details_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Order Status Stepper (Durum akışı, aksiyon satırı, iptal/silme diyalogları)
// ─────────────────────────────────────────────────────────────────────────────

extension _StatusStepperMixin on OrderDetailsPage {
  Widget buildStatusStepper(
      BuildContext context, WidgetRef ref, OrderEntity order) {
    final isCancelled = order.status == 'cancelled';
    final isDelivered = order.status == 'delivered';
    final currentIndex =
        isCancelled ? -1 : OrderDetailsPage._statusFlow.indexOf(order.status.toLowerCase());

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
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(
                isCancelled
                    ? Icons.cancel_rounded
                    : isDelivered
                        ? Icons.task_alt_rounded
                        : Icons.local_shipping_rounded,
                size: 14,
                color: isCancelled
                    ? _kRed
                    : isDelivered
                        ? const Color(0xFF475569)
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
                currentIndex < 0 ? 0 : (currentIndex + 1) / OrderDetailsPage._statusFlow.length,
            minHeight: 6,
            backgroundColor: _kBorder,
            valueColor: const AlwaysStoppedAnimation(_kGreen),
          ),
        ),
        const SizedBox(height: 12),
        // Steps row
        Row(
          children: OrderDetailsPage._statusFlow.asMap().entries.map((entry) {
            final stepIndex = entry.key;
            final status = entry.value;
            final isDone = stepIndex <= currentIndex;
            final isCurrent = stepIndex == currentIndex;

            return Expanded(
              child: InkWell(
                onTap: () async {
                  if (order.status != status) {
                    if (status == 'delivered') {
                      _handleDelivery(context, ref, order);
                    } else {
                      try {
                        await ref
                            .read(ordersControllerProvider.notifier)
                            .updateStatus(order.id, status);
                        ref.invalidate(_orderDetailProvider(order.id));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '📱 Durum güncellendi: ${OrderDetailsPage._statusLabels[status]} (SMS bildirimi tetiklendi)'),
                              backgroundColor: _kGreenDark,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Durum güncellenemedi: $e'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
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
                          OrderDetailsPage._statusIcons[status] ?? Icons.circle,
                          size: 18,
                          color: isDone ? Colors.white : _kTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        OrderDetailsPage._statusLabels[status] ?? status,
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

  void _confirmCancel(
      BuildContext context, WidgetRef ref, OrderEntity order) {
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
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(ordersControllerProvider.notifier)
                    .updateStatus(order.id, 'cancelled');
                ref.invalidate(_orderDetailProvider(order.id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Sipariş iptal edildi.'),
                        backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Sipariş iptal edilemedi: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, OrderEntity order) {
    if (order.status == 'delivered') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Teslim Edilmiş Sipariş'),
            ],
          ),
          content: const Text(
            'Bu sipariş teslim edilmiştir. Teslim edilmiş siparişler doğrudan silinemez; stok ve finansal kayıtların tutarlılığı için iade alınmalıdır.\n\nİade işlemi başlatmak ister misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(context);
                _showOrderRefundDialog(context, ref, order);
              },
              child: const Text('İade İşlemi Başlat'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Siparişi Sil'),
        content: const Text(
            'Bu sipariş kaydını tamamen silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              // 1. Close confirmation dialog
              Navigator.pop(dialogCtx);

              // 2. Immediately pop OrderDetailsPage so it doesn't rebuild in invalid state
              if (context.mounted) {
                Navigator.pop(context);
              }

              rootScaffoldMessengerKey.currentState?.showSnackBar(
                const SnackBar(
                  content: Text('Sipariş siliniyor...'),
                  duration: Duration(milliseconds: 1500),
                  behavior: SnackBarBehavior.floating,
                ),
              );

              try {
                final controller = ref.read(ordersControllerProvider.notifier);
                if (order.status != 'cancelled' &&
                    order.status != 'delivered') {
                  try {
                    await controller.updateStatus(order.id, 'cancelled');
                  } catch (err) {
                    debugPrint('Pre-delete cancellation skipped: $err');
                  }
                }
                await controller.deleteOrder(order.id);

                ref.invalidate(dashboardProvider);
                ref.invalidate(productsControllerProvider);
                if (order.customerId.isNotEmpty) {
                  ref.invalidate(
                      customerTransactionsProvider(order.customerId));
                  ref.invalidate(
                      customerBalanceDetailsProvider(order.customerId));
                }
                unawaited(
                    ref.read(customersControllerProvider.notifier).refresh());

                rootScaffoldMessengerKey.currentState?.showSnackBar(
                  const SnackBar(
                    content: Text('Sipariş başarıyla silindi.'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e, st) {
                unawaited(TelemetryService()
                    .logError(e, st, context: 'order_delete'));
                rootScaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text('Sipariş silinemedi: $e'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveredActions(
      BuildContext context, WidgetRef ref, OrderEntity order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: _kGreenLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: _kGreenDark, size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sipariş Teslim Edildi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  Text(
                    'Müşteri iade talebinde bulunduysa iade alabilirsiniz.',
                    style: TextStyle(
                      fontSize: 11,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => _showOrderRefundDialog(context, ref, order),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: const Text(
              'İade Al',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderRefundDialog(
      BuildContext context, WidgetRef ref, OrderEntity order) {
    final products = ref.read(productsControllerProvider).value ?? [];
    final productNameMap = {for (final p in products) p.id: p.name};

    final returnItems = order.items.map((item) {
      final productId =
          item['product_id'] as String? ?? item['productId'] as String? ?? '';
      final double qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final double unitPrice = (item['unit_price'] as num?)?.toDouble() ??
          (item['price'] as num?)?.toDouble() ??
          0.0;
      return {
        'productId': productId,
        'maxQty': qty,
        'returnQty': qty,
        'unitPrice': unitPrice,
      };
    }).toList();

    final hasCustomer = order.customerId.trim().isNotEmpty;
    String refundMethod = 'cash';
    String reason = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final refundTotal = returnItems.fold<double>(
            0.0,
            (sum, item) =>
                sum +
                (((item['returnQty'] as num?)?.toDouble() ?? 0.0) *
                    ((item['unitPrice'] as num?)?.toDouble() ?? 0.0)),
          );

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.undo_rounded, color: _kOrange),
                SizedBox(width: 8),
                Text('Sipariş İadesi'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'İade edilecek ürün ve miktarları belirleyin:',
                      style: TextStyle(fontSize: 12, color: _kTextSecondary),
                    ),
                    const SizedBox(height: 10),
                    ...returnItems.map((item) {
                      final pId = item['productId'] as String;
                      final name = productNameMap[pId] ?? pId;
                      final maxQty = (item['maxQty'] as num?)?.toDouble() ?? 0.0;
                      final currentQty = (item['returnQty'] as num?)?.toDouble() ?? 0.0;
                      final price = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '₺${price.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 18),
                              color: _kTextSecondary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 26, minHeight: 26),
                              onPressed: currentQty > 0
                                  ? () => setDialog(() {
                                        final step = maxQty < 2 ? 0.1 : 1.0;
                                        item['returnQty'] = (currentQty - step)
                                            .clamp(0.0, maxQty);
                                      })
                                  : null,
                            ),
                            Text(
                              '${currentQty % 1 == 0 ? currentQty.toInt() : currentQty.toStringAsFixed(2)} / ${maxQty % 1 == 0 ? maxQty.toInt() : maxQty.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 18),
                              color: _kGreen,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 26, minHeight: 26),
                              onPressed: currentQty < maxQty
                                  ? () => setDialog(() {
                                        final step = maxQty < 2 ? 0.1 : 1.0;
                                        item['returnQty'] = (currentQty + step)
                                            .clamp(0.0, maxQty);
                                      })
                                  : null,
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Toplam İade Tutarı:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₺${refundTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'İade Gerekçesi (zorunlu)',
                        hintText: 'Örn: Müşteri vazgeçti / Kusurlu ürün',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (val) =>
                          setDialog(() => reason = val.trim()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: refundMethod,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'İade Ödeme Yolu',
                        helperText: refundMethod == 'cash'
                            ? 'Müşteriye elden nakit verildi (Cari bakiye değişmez)'
                            : 'Müşteriye para verilmedi, cari hesabına artı/alacak yazılır',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'cash',
                          child: Text('💵 Kasadan Nakit İade (Elden Para Verildi)'),
                        ),
                        if (hasCustomer)
                          const DropdownMenuItem(
                            value: 'balance',
                            child: Text(
                                '📋 Cari Hesaba Yaz (Borçtan Düş / Alacak Bırak)'),
                          ),
                      ],
                      onChanged: (v) =>
                          setDialog(() => refundMethod = v ?? 'cash'),
                    ),
                    if (refundMethod == 'balance' && hasCustomer) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: Color(0xFFB45309)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Dikkat: Müşterinin borcu yoksa bu tutar müşteriyi alacaklı yapacaktır.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: refundTotal > 0 && reason.isNotEmpty
                    ? () async {
                        Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('İade işlemi yapılıyor...'),
                              duration: Duration(milliseconds: 1500),
                            ),
                          );
                        }
                        try {
                          final itemsToRefund = returnItems
                              .where((ri) => ((ri['returnQty'] as num?)?.toDouble() ?? 0.0) > 0)
                              .map((ri) {
                            final qty = (ri['returnQty'] as num?)?.toDouble() ?? 0.0;
                            final intQty = qty < 1
                                ? (qty * 1000).round()
                                : qty.round();
                            return SaleItemInput(
                              productId: ri['productId'] as String,
                              quantity: intQty,
                              saleQuantity: qty,
                              unitPrice: (ri['unitPrice'] as num?)?.toDouble() ?? 0.0,
                            );
                          }).toList();

                          await ref
                              .read(ordersControllerProvider.notifier)
                              .refundOrder(
                                orderId: order.id,
                                refundMethod: refundMethod,
                                reason: reason,
                                itemsToRefund: itemsToRefund,
                              );

                          ref.invalidate(_orderDetailProvider(order.id));

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Sipariş başarıyla iade alındı. ₺${refundTotal.toStringAsFixed(2)} iade edildi.',
                                ),
                                backgroundColor: _kOrange,
                              ),
                            );
                          }
                        } catch (e, st) {
                          unawaited(TelemetryService()
                              .logError(e, st, context: 'order_refund'));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('İade işlemi başarısız oldu: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                child: const Text('İadeyi Onayla'),
              ),
            ],
          );
        },
      ),
    );
  }
}

