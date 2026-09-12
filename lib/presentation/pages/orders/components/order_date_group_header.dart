part of '../../orders_page.dart';

/// Bir güne ait siparişleri ve günün toplam tutarını tutan veri sınıfı
class OrderDayGroup {
  final DateTime date;
  final String title;
  final List<OrderEntity> orders;
  final double totalAmount;

  const OrderDayGroup({
    required this.date,
    required this.title,
    required this.orders,
    required this.totalAmount,
  });

  int get count => orders.length;

  List<String> get selectableIds => orders
      .where((o) => o.status.toLowerCase() != 'delivered')
      .map((o) => o.id)
      .toList();
}

/// Siparişler listesinde gün gruplarını ayıran minimal ve sade başlık şeridi
class _OrderDateGroupHeader extends StatelessWidget {
  final OrderDayGroup group;
  final bool isSelecting;
  final bool isAllSelected;
  final VoidCallback onToggleSelectAll;

  const _OrderDateGroupHeader({
    required this.group,
    required this.isSelecting,
    required this.isAllSelected,
    required this.onToggleSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final selectableCount = group.selectableIds.length;
    final hasSelectable = selectableCount > 0;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // ── Sol Kısım: Checkbox + Kısa Tarih + Sipariş Adedi ──
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: hasSelectable ? onToggleSelectAll : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: isAllSelected,
                          activeColor: _kGreen,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: hasSelectable ? (_) => onToggleSelectAll() : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${group.title} (${group.count})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kText,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // ── Sağ Kısım: Günün Toplam Tutarı ──
              Text(
                '₺${group.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
        ],
      ),
    );
  }
}
