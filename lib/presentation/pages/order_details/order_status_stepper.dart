part of '../order_details_page.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Order Status Stepper (Durum akÄ±ÅŸÄ±, aksiyon satÄ±rÄ±, iptal/silme diyaloglarÄ±)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
            const Text('Durum AkÄ±ÅŸÄ±',
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
                    child: Text('Bu sipariÅŸ iptal edildi.',
                        style: TextStyle(
                            color: _kRed, fontWeight: FontWeight.bold))),
              ]),
            )
          else ...[
            _buildPillStepper(context, ref, order, currentIndex),
            const SizedBox(height: 16)
          ],

          // â”€â”€ Aksiyon ButonlarÄ± â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                onTap: () {
                  if (order.status != status) {
                    if (status == 'delivered') {
                      _handleDelivery(context, ref, order);
                    } else {
                      ref
                          .read(ordersControllerProvider.notifier)
                          .updateStatus(order.id, status);
                      ref.invalidate(_orderDetailProvider(order.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'ğŸ“± Durum gÃ¼ncellendi: ${OrderDetailsPage._statusLabels[status]} (SMS bildirimi tetiklendi)'),
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
      // VADELÄ° uyarÄ±sÄ± â€” teslim adÄ±mÄ±nda borÃ§lu mÃ¼ÅŸteriler iÃ§in
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
                'VADELÄ° sipariÅŸ â€” Teslimata izin verilir, borÃ§ cari hesapta kalÄ±r.',
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
                    'Durumu deÄŸiÅŸtirmek iÃ§in yukarÄ±daki adÄ±mlara dokunabilirsiniz.',
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
            label: const Text('Ä°ptal Et',
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
        title: const Text('SipariÅŸi Ä°ptal Et'),
        content:
            const Text('Bu sipariÅŸi iptal etmek istediÄŸinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('VazgeÃ§'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(ordersControllerProvider.notifier)
                  .updateStatus(order.id, 'cancelled');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('SipariÅŸ iptal edildi.'),
                    backgroundColor: Colors.red),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Ä°ptal Et'),
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
              Text('Teslim EdilmiÅŸ SipariÅŸ'),
            ],
          ),
          content: const Text(
            'Bu sipariÅŸ teslim edilmiÅŸtir. Teslim edilmiÅŸ sipariÅŸler doÄŸrudan silinemez; stok ve finansal kayÄ±tlarÄ±n tutarlÄ±lÄ±ÄŸÄ± iÃ§in iade alÄ±nmalÄ±dÄ±r.\n\nÄ°ade iÅŸlemi baÅŸlatmak ister misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('VazgeÃ§'),
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
              child: const Text('Ä°ade Ä°ÅŸlemi BaÅŸlat'),
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
        title: const Text('SipariÅŸi Sil'),
        content: const Text(
            'Bu sipariÅŸ kaydÄ±nÄ± tamamen silmek istediÄŸinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Ä°ptal')),
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
                  content: Text('SipariÅŸ siliniyor...'),
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
                    content: Text('SipariÅŸ baÅŸarÄ±yla silindi.'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e, st) {
                unawaited(TelemetryService()
                    .logError(e, st, context: 'order_delete'));
                rootScaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text('SipariÅŸ silinemedi: $e'),
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
                    'SipariÅŸ Teslim Edildi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  Text(
                    'MÃ¼ÅŸteri iade talebinde bulunduysa iade alabilirsiniz.',
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
              'Ä°ade Al',
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

    String refundMethod = 'balance';
    String reason = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final refundTotal = returnItems.fold<double>(
            0.0,
            (sum, item) =>
                sum +
                ((item['returnQty'] as double) *
                    (item['unitPrice'] as double)),
          );

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.undo_rounded, color: _kOrange),
                SizedBox(width: 8),
                Text('SipariÅŸ Ä°adesi'),
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
                      'Ä°ade edilecek Ã¼rÃ¼n ve miktarlarÄ± belirleyin:',
                      style: TextStyle(fontSize: 12, color: _kTextSecondary),
                    ),
                    const SizedBox(height: 10),
                    ...returnItems.map((item) {
                      final pId = item['productId'] as String;
                      final name = productNameMap[pId] ?? pId;
                      final maxQty = item['maxQty'] as double;
                      final currentQty = item['returnQty'] as double;
                      final price = item['unitPrice'] as double;

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
                                    'â‚º${price.toStringAsFixed(2)}',
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
                          'Toplam Ä°ade TutarÄ±:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'â‚º${refundTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: _kOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Ä°ade GerekÃ§esi',
                        hintText: 'Ã–rn: MÃ¼ÅŸteri vazgeÃ§ti / Kusurlu Ã¼rÃ¼n',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (val) =>
                          setDialog(() => reason = val.trim()),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: refundMethod,
                      decoration: InputDecoration(
                        labelText: 'Ä°ade YÃ¶ntemi',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'balance',
                          child: Text(
                              'MÃ¼ÅŸteri Bakiyesine Alacak Yaz (BorÃ§tan DÃ¼ÅŸ)'),
                        ),
                        DropdownMenuItem(
                          value: 'cash',
                          child: Text('Kasadan Nakit Olarak Ä°ade Et'),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialog(() => refundMethod = v ?? 'balance'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Ä°ptal'),
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
                              content: Text('Ä°ade iÅŸlemi yapÄ±lÄ±yor...'),
                              duration: Duration(milliseconds: 1500),
                            ),
                          );
                        }
                        try {
                          final itemsToRefund = returnItems
                              .where((ri) => (ri['returnQty'] as double) > 0)
                              .map((ri) {
                            final qty = ri['returnQty'] as double;
                            final intQty = qty < 1
                                ? (qty * 1000).round()
                                : qty.round();
                            return SaleItemInput(
                              productId: ri['productId'] as String,
                              quantity: intQty,
                              saleQuantity: qty,
                              unitPrice: ri['unitPrice'] as double,
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
                                  'SipariÅŸ baÅŸarÄ±yla iade alÄ±ndÄ±. â‚º${refundTotal.toStringAsFixed(2)} iade edildi.',
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
                                    Text('Ä°ade iÅŸlemi baÅŸarÄ±sÄ±z oldu: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                child: const Text('Ä°adeyi Onayla'),
              ),
            ],
          );
        },
      ),
    );
  }
}

