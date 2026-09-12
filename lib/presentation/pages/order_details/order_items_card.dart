part of '../order_details_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Order Items Card (Sipariş kalemleri, toplam, indirim gösterimi)
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildOrderItemsCard(
  OrderEntity order,
  Map<String, String> productNameMap,
) {
  final items = order.items;
  double subtotal = 0;
  for (final item in items) {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
    subtotal += qty * price;
  }
  final discount = order.discountAmount;
  final netTotal = (subtotal - discount).clamp(0.0, double.infinity);

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
            final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
            final itemTotal = qty * price;
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
          if (discount > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ara Toplam',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _kTextSecondary,
                  ),
                ),
                Text(
                  '${subtotal.toStringAsFixed(2)} TL',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _kText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'İndirim',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.red,
                  ),
                ),
                Text(
                  '-${discount.toStringAsFixed(2)} TL',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                discount > 0 ? 'Genel Toplam' : 'Toplam',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _kText,
                ),
              ),
              Text(
                '${netTotal.toStringAsFixed(2)} TL',
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

/// Stub kept for backward compat — action row now lives inside stepper
Widget _buildActionButtons(
    BuildContext context, WidgetRef ref, OrderEntity order) {
  return const SizedBox.shrink();
}

String _formatQuantity(double qty) {
  if (qty == qty.toInt()) {
    return qty.toInt().toString();
  }
  return qty.toString();
}
