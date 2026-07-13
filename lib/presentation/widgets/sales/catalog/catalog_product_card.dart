part of '../catalog_panel.dart';

class _CatalogProductCard extends StatelessWidget {
  final ProductEntity product;
  final Function(ProductEntity) onAddToCart;

  const _CatalogProductCard({
    required this.product,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.quantity <= 0;
    final isLowStock = product.quantity > 0 && product.quantity <= 5;

    // Stok durumuna göre renkler (mevcut mantık korundu)
    final Color badgeBgColor = outOfStock
        ? _kRedLight
        : (isLowStock ? _kAmberLight : _kGreenLight);
    final Color badgeTextColor = outOfStock
        ? _kRed
        : (isLowStock ? const Color(0xFF854D0E) : _kGreenDark);
    // Border rengi stok durumuna göre belirlenir
    final Color borderColor = outOfStock
        ? _kRed.withValues(alpha: 0.25)
        : (isLowStock ? _kAmber.withValues(alpha: 0.35) : _kBorder);

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: (outOfStock || isLowStock) ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => onAddToCart(product),
            borderRadius: BorderRadius.circular(14),
            splashColor: _kGreenLight,
            highlightColor: _kGreenLight.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Üst satır: Kategori + Stok Rozeti
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            color: _kTextSecondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Stok rozeti
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          outOfStock
                              ? 'Tükendi'
                              : (isLowStock ? '${product.quantity} adet' : '${product.quantity}'),
                          style: TextStyle(
                            fontSize: 9,
                            color: badgeTextColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ProductImage(
                        imageUrl: product.imageUrl,
                        barcode: product.id,
                        size: 72.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Ürün Adı
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _kText,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Alt satır: Fiyat + Sepet ikonu
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Fiyat — POS için büyük ve belirgin
                      Text(
                        '₺${product.price % 1 == 0 ? product.price.toInt() : product.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: _kGreenDark,
                          letterSpacing: -0.3,
                        ),
                      ),

                      // Sepete Ekle butonu
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: outOfStock ? Colors.grey[100] : _kGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          outOfStock ? Icons.block_rounded : Icons.add_rounded,
                          color: outOfStock ? Colors.grey[400] : Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
