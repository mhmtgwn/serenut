part of '../../orders_page.dart';

class _OrderCard extends StatelessWidget {
  final OrderEntity order;
  final String customerName;
  final VoidCallback onDetail;
  final bool isGrid;
  final bool isSelecting;
  final bool isSelected;
  final bool isSelectable;
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback? onLongPress;

  const _OrderCard({
    required this.order,
    required this.customerName,
    required this.onDetail,
    this.isGrid = false,
    this.isSelecting = false,
    this.isSelected = false,
    this.isSelectable = true,
    this.onSelectChanged,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(order.status);
    final dateStr = DateFormat('dd.MM.yy HH:mm').format(order.createdAt);
    final timeStr = DateFormat('HH:mm').format(order.createdAt);
    final phoneStr = (order.customerPhone ?? '').trim();
    final subtotal = (order.items.fold<double>(0.0, (sum, item) {
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      return sum + price * qty;
    }));
    final totalAmount = order.totalAmount > 0 || order.discountAmount > 0
        ? order.totalAmount
        : subtotal;
    final itemCount = order.items.length;

    final cardBg = _statusCardBg(order.status, isSelected);
    final cardBorder = _statusCardBorder(order.status, isSelected);

    final card = Container(
      margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cardBorder,
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          splashColor: meta.color.withValues(alpha: 0.08),
          highlightColor: meta.color.withValues(alpha: 0.04),
          onTap: isSelecting
              ? () {
                  if (isSelectable) {
                    onSelectChanged?.call(!isSelected);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Teslim edilmiş siparişler toplu işlemden etkilenmez.'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                }
              : onDetail,
          onLongPress: !isSelecting ? onLongPress : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // ── Çoklu Seçim Durumu ─────────────────────────────────────
                if (isSelecting) ...[
                  if (!isSelectable)
                    const Tooltip(
                      message:
                          'Teslim edilmiş siparişler toplu işleme kapalıdır',
                      child: Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: isSelected,
                        activeColor: _kGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: onSelectChanged,
                      ),
                    ),
                ],

                // ── Sol Dikey Renk Vurgusu ──────────────────────────────────
                Container(
                  width: 5,
                  height: 48,
                  decoration: BoxDecoration(
                    color: meta.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),

                // ── Sol Kısım: Durum Avatarı ─────────────────────────────────
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: meta.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    meta.icon,
                    color: meta.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),

                // ── Orta Kısım: Müşteri Bilgisi & Durum ────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: _kText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _StatusBadge(status: order.status),
                          const SizedBox(width: 8),
                          Text(
                            '$itemCount kalem • $dateStr',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _kTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // ── Sağ Kısım: Sipariş No & Saat (Üstte), Müşteri No (Altında), Fiyat ──
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#${order.displayNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (phoneStr.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 11.5, color: _kTextSecondary),
                          const SizedBox(width: 3),
                          Text(
                            phoneStr,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _kTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (order.discountAmount > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '₺${subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough,
                                color: _kTextSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: meta.amountBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: meta.borderColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '₺${totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: meta.amountColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: _kTextSecondary,
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isSelecting && !isSelectable) {
      return Opacity(
        opacity: 0.6,
        child: card,
      );
    }
    return card;
  }
}

// ── Durum Badge ───────────────────────────────────────────────────────────────
