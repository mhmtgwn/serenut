part of '../home_page.dart';

class _OperationsFeed extends StatelessWidget {
  const _OperationsFeed({
    required this.selectedTab,
    required this.onTabChanged,
    required this.recentOrders,
    required this.recentSales,
  });

  final int selectedTab;
  final ValueChanged<int> onTabChanged;
  final List<DashboardRecentOrder> recentOrders;
  final List<dynamic> recentSales;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return Container(
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Tab Switcher
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: POSColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: _FeedTabButton(
                    title: 'Canlı Siparişler (${recentOrders.length})',
                    icon: Icons.local_shipping_outlined,
                    isSelected: selectedTab == 0,
                    onTap: () => onTabChanged(0),
                  ),
                ),
                Expanded(
                  child: _FeedTabButton(
                    title: 'Son Satışlar (${recentSales.length})',
                    icon: Icons.receipt_long_outlined,
                    isSelected: selectedTab == 1,
                    onTap: () => onTabChanged(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Liste İçeriği
          if (selectedTab == 0) ...[
            if (recentOrders.isEmpty)
              const SizedBox(
                height: 120,
                child: Center(
                  child: Text('Henüz sipariş kaydı bulunmuyor.',
                      style: TextStyle(color: POSColors.textSecondary)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentOrders.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: POSColors.border, height: 16),
                itemBuilder: (context, index) {
                  final order = recentOrders[index];
                  final timeStr = DateFormat('HH:mm').format(order.createdAt);
                  return InkWell(
                    onTap: () =>
                        OrderDetailsPage.show(context, orderId: order.id),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: POSColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.shopping_bag_outlined,
                                color: POSColors.textSecondary, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        order.customerName,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: POSColors.text,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '#${order.orderNumber}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: POSColors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${order.itemCount} Kalem Ürün · $timeStr',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: POSColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currency.format(order.totalAmount),
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: POSColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              _OrderCompactBadge(status: order.status),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ] else ...[
            if (recentSales.isEmpty)
              const SizedBox(
                height: 120,
                child: Center(
                  child: Text('Henüz satış kaydı bulunmuyor.',
                      style: TextStyle(color: POSColors.textSecondary)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentSales.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: POSColors.border, height: 16),
                itemBuilder: (context, index) {
                  final sale = recentSales[index];
                  final timeStr = DateFormat('HH:mm').format(sale.createdAt);
                  return InkWell(
                    onTap: () => context.push('/sales/detail/${sale.id}'),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: POSColors.greenLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.receipt_rounded,
                                color: POSColors.greenDark, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currency.format(sale.totalAmount),
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: POSColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$timeStr · Fiş: ${sale.id.toString().substring(0, 8)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: POSColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: POSColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              sale.paymentMethod.toString().toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: POSColors.textSecondary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _FeedTabButton extends StatelessWidget {
  const _FeedTabButton({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? POSColors.greenDark : POSColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? POSColors.text : POSColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCompactBadge extends StatelessWidget {
  const _OrderCompactBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status.toLowerCase()) {
      'preparing' || 'hazirlaniyor' => (
          'Hazırlanıyor',
          const Color(0xFF2563EB),
          const Color(0xFFEFF6FF)
        ),
      'shipped' || 'yolda' => (
          'Yolda',
          const Color(0xFF7C3AED),
          const Color(0xFFF5F3FF)
        ),
      'ready' || 'hazir' => (
          'Hazır',
          const Color(0xFF16A34A),
          const Color(0xFFDCFCE7),
        ),
      'delivered' || 'completed' || 'teslim' => (
          'Teslim Edildi',
          const Color(0xFF475569),
          const Color(0xFFE2E8F0),
        ),
      'cancelled' || 'iptal' => (
          'İptal',
          POSColors.red,
          POSColors.redLight
        ),
      _ => ('Yeni', const Color(0xFFD97706), const Color(0xFFFFFBEB)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
      ),
    );
  }
}

// ── 7. En Çok Satanlar & Kategori Dağılımı Kartları ────────────────────────────
