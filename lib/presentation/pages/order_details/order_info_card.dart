part of '../order_details_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Order Info Card (Müşteri bilgisi, ödeme durumu, tarihler, teslim countdown)
// ─────────────────────────────────────────────────────────────────────────────

extension _OrderInfoCardMixin on OrderDetailsPage {
  Widget buildDeliveryCountdown(OrderEntity order) {
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
        final totalPaid = (data?['totalPaid'] as num?)?.toDouble() ?? 0.0;

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

  Widget buildOrderInfoCard(BuildContext context, WidgetRef ref,
      OrderEntity order, CustomerEntity? customer,
      [String? fallbackName]) {
    final customerName = customer?.name ??
        fallbackName ??
        (order.customerName != null && order.customerName!.trim().isNotEmpty
            ? order.customerName!.trim()
            : (order.customerId.isEmpty
                ? 'Genel Müşteri'
                : 'Bilinmeyen Müşteri'));
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
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 13)),
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
            if (order.createdBy != null && order.createdBy!.isNotEmpty) ...[
              const Divider(height: 20),
              _infoRow(
                'İşlemi Yapan',
                order.createdBy!,
                Icons.badge_outlined,
              ),
            ],
            if (order.expectedDeliveryDate != null) ...[
              const Divider(height: 20),
              _infoRow(
                  'Teslim Tarihi',
                  DateFormat('dd.MM.yyyy')
                      .format(order.expectedDeliveryDate!),
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
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(4)),
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
      if (order.totalAmount > 0.01 && context.mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Mali Kayıt Bulunamadı'),
            content: Text(
              'Bu siparişe (${order.id}) ait mali tahsilat/satış kaydı bulunamadı (Tutar: ₺${order.totalAmount.toStringAsFixed(2)}).\n\n'
              'Siparişi ödeme alınmadan doğrudan teslim edildi olarak işaretlemek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Teslim Edildi İşaretle'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      await ref
          .read(ordersControllerProvider.notifier)
          .updateStatus(order.id, 'delivered');
      ref.invalidate(_orderDetailProvider(order.id));
      _triggerPrint(ref, order);
      return;
    }

    final double remainingDebt =
        (saleTx.amount - totalPaid).clamp(0.0, double.infinity);

    if (remainingDebt <= 0.01) {
      await ref
          .read(ordersControllerProvider.notifier)
          .updateStatus(order.id, 'delivered');
      ref.invalidate(_orderDetailProvider(order.id));
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
    _CashOutSheet.show(
      context,
      order: order,
      saleTx: saleTx,
      totalPaid: totalPaid,
    );
  }
}
