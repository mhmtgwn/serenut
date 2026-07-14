// lib/presentation/widgets/sales/cart_panel.dart
// Serenut POS — Sepet Paneli
// UX Redesign v3: 44×44 touch targets, swipe-to-delete, improved empty state
// Preserved: all callback signatures, no business logic changes

import 'package:flutter/material.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

class CartPanel extends StatelessWidget {
  final Map<String, int> cartQuantities;
  final Map<String, ProductEntity> cartProducts;
  final VoidCallback onClearCart;
  final Function(ProductEntity) onRemoveFromCart;
  final Function(ProductEntity) onAddToCart;
  final Function(ProductEntity) onDeleteFromCart;
  final Function(ProductEntity, int) onQuantityChanged;
  final Widget checkoutSectionWidget;

  const CartPanel({
    super.key,
    required this.cartQuantities,
    required this.cartProducts,
    required this.onClearCart,
    required this.onRemoveFromCart,
    required this.onAddToCart,
    required this.onDeleteFromCart,
    required this.onQuantityChanged,
    required this.checkoutSectionWidget,
  });

  @override
  Widget build(BuildContext context) {
    final cartCount = cartQuantities.values.fold(0, (a, b) => a + b);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // ── Sepet Başlığı ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _kGreenLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shopping_cart_rounded,
                          color: _kGreenDark, size: 17),
                    ),
                    const SizedBox(width: 6),
                    if (cartQuantities.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kGreenLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$cartCount ürün',
                          style: const TextStyle(
                              fontSize: 11,
                              color: _kGreenDark,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                if (cartQuantities.isNotEmpty)
                  InkWell(
                    onTap: onClearCart,
                    borderRadius: BorderRadius.circular(8),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _kRedLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_sweep_rounded,
                              color: _kRed, size: 15),
                          SizedBox(width: 4),
                          Text('Temizle',
                              style: TextStyle(
                                  color: _kRed,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Sepet Öğeleri ──────────────────────────────────────────────────
          Expanded(
            child: cartQuantities.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    itemCount: cartQuantities.length,
                    itemBuilder: (context, index) {
                      final entry = cartQuantities.entries.elementAt(index);
                      final prod = cartProducts[entry.key]!;
                      final qty = entry.value;
                      return _CartItem(
                        key: ValueKey(prod.id),
                        product: prod,
                        quantity: qty,
                        onAdd: () => onAddToCart(prod),
                        onRemove: () => onRemoveFromCart(prod),
                        onDelete: () => onDeleteFromCart(prod),
                        onQtyChanged: (newQty) =>
                            onQuantityChanged(prod, newQty),
                      );
                    },
                  ),
          ),

          // ── Ödeme Paneli ───────────────────────────────────────────────────
          checkoutSectionWidget,
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kSurface,
              shape: BoxShape.circle,
              border: Border.all(color: _kBorder, width: 2),
            ),
            child: Icon(
              Icons.shopping_basket_outlined,
              size: 38,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sepet boş',
            style: TextStyle(
                color: _kTextSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sol panelden ürün ekleyin',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ── Sepet Öğesi Widget ────────────────────────────────────────────────────────

class _CartItem extends StatefulWidget {
  final ProductEntity product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDelete;
  final Function(int) onQtyChanged;

  const _CartItem({
    super.key,
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onQtyChanged,
  });

  @override
  State<_CartItem> createState() => _CartItemState();
}

class _CartItemState extends State<_CartItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _colorAnimation = ColorTween(
      begin: const Color(0xFFDCFCE7), // Light green flash highlight
      end: _kSurface, // Normal surface color
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _CartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quantity != oldWidget.quantity) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${widget.product.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _kRed,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 24),
            SizedBox(height: 2),
            Text('Sil',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      onDismissed: (_) => widget.onDelete(),
      child: AnimatedBuilder(
        animation: _colorAnimation,
        builder: (context, child) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: _colorAnimation.value,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            // ── Ürün Adı + Fiyat ────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _kText,
                        height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '₺${widget.product.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: _kTextSecondary, fontSize: 11),
                      ),
                      const Text(' × ',
                          style:
                              TextStyle(color: _kTextSecondary, fontSize: 11)),
                      Text('${widget.quantity}',
                          style: const TextStyle(
                              color: _kTextSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                        '₺${(widget.product.price * widget.quantity).toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: _kGreenDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── Miktar Kontrolcüsü ───────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QtyButton(
                    icon: Icons.remove_rounded,
                    color: _kRed,
                    onTap: widget.onRemove,
                  ),
                  InkWell(
                    onTap: () => _showQtyEditDialog(context),
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 32,
                      child: Text(
                        '${widget.quantity}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ),
                  ),
                  _QtyButton(
                    icon: Icons.add_rounded,
                    color: _kGreen,
                    onTap: widget.onAdd,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQtyEditDialog(BuildContext context) {
    final controller = TextEditingController(text: '${widget.quantity}');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(widget.product.name,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stok Adedi: ${widget.product.quantity}',
                  style: const TextStyle(color: _kTextSecondary, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Miktar',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final newQty = int.tryParse(controller.text) ?? widget.quantity;
                widget.onQtyChanged(newQty);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
              child:
                  const Text('Güncelle', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

// ── Miktar Butonu (44×44 minimum touch target) ────────────────────────────────

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QtyButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}
