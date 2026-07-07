// lib/presentation/widgets/sales/catalog_panel.dart
// Serenut POS — Ürün Kataloğu Paneli
// Design Evolution v2: Büyük dokunmatik hedefler, geliştirilmiş kart hiyerarşisi
// Revized: 22 Jun 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/product_image.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/widgets/sales/barcode_scanner_dialog.dart';
import 'package:serenutos/presentation/widgets/auth/pin_gate_dialog.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';

// ── Mevcut POS Tema Renkleri (korundu) ───────────────────────────────────────
const _kGreen      = Color(0xFF16A34A);
const _kGreenDark  = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber      = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kRed        = Color(0xFFDC2626);
const _kRedLight   = Color(0xFFFEE2E2);
const _kSurface    = Color(0xFFF8FAFC);
const _kCardBg     = Colors.white;
const _kText       = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder     = Color(0xFFE2E8F0);

class CatalogPanel extends ConsumerStatefulWidget {
  final AsyncValue<List<ProductEntity>> filteredProductsVal;
  final List<String> categories;
  final String? selectedCategory;
  final TextEditingController searchController;
  final TextEditingController barcodeController;
  final FocusNode? barcodeFocusNode;
  final Function(ProductEntity) onAddToCart;
  final Function(String, List<ProductEntity>) onBarcodeSubmit;

  const CatalogPanel({
    super.key,
    required this.filteredProductsVal,
    required this.categories,
    required this.selectedCategory,
    required this.searchController,
    required this.barcodeController,
    this.barcodeFocusNode,
    required this.onAddToCart,
    required this.onBarcodeSubmit,
  });

  @override
  ConsumerState<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends ConsumerState<CatalogPanel> {
  bool _isSearching = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(salesProductsControllerProvider.notifier).loadNextPage();
    }
  }

  void _showCategoryBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kategori Filtrele',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildModalChip(
                        ctx,
                        label: 'Tümü',
                        isSelected: widget.selectedCategory == null,
                        onTap: () {
                          ref.read(salesProductCategoryFilterProvider.notifier).state = null;
                          Navigator.pop(ctx);
                        },
                      ),
                      ...widget.categories.map((cat) {
                        return _buildModalChip(
                          ctx,
                          label: cat,
                          isSelected: widget.selectedCategory == cat,
                          onTap: () {
                            ref.read(salesProductCategoryFilterProvider.notifier).state = cat;
                            Navigator.pop(ctx);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _kGreen : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kGreen : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF475569),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PosHeader(
          title: 'Kasa (Satış)',
          isSearching: _isSearching,
          onSearchToggled: (val) => setState(() => _isSearching = val),
          searchController: widget.searchController,
          searchHint: 'Ürün ara...',
          onSearchChanged: (val) {
            ref.read(salesProductSearchQueryProvider.notifier).state = val;
            setState(() {});
          },
          actions: [
            // Barkod tarama ikonu - Kamera
            IconButton(
              onPressed: () {
                BarcodeScannerDialog.show(
                  context,
                  onBarcodeScanned: (code) {
                    widget.filteredProductsVal.whenData((list) {
                      widget.onBarcodeSubmit(code, list);
                    });
                  },
                );
              },
              icon: const Icon(Icons.photo_camera_rounded, color: _kGreen),
              tooltip: 'Kamera Tarayıcı',
            ),
            // Satış geçmişi ikonu
            IconButton(
              onPressed: () => context.push('/sales/history'),
              icon: const Icon(Icons.history_rounded, color: _kGreen),
              tooltip: 'Satış Geçmişi',
            ),
          ],
          filterWidget: InkWell(
            onTap: () => _showCategoryBottomSheet(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_list_rounded, size: 16, color: _kGreenDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.selectedCategory == null ? 'Kategori: Tümü' : 'Kategori: ${widget.selectedCategory}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kText,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _kTextSecondary),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: _kBorder),

        // ── ÜRÜN GRİDİ ───────────────────────────────────────────────────
        Expanded(
          child: widget.filteredProductsVal.when(
            loading: () => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_kGreen),
              ),
            ),
            error: (err, _) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 36, color: _kRed.withValues(alpha: 0.6)),
                    const SizedBox(height: 8),
                    const Text(
                      'Ürünler yüklenirken hata oluştu',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _kRed, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      err.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            data: (products) {
              if (products.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 14),
                      const Text(
                        'Ürün bulunamadı',
                        style: TextStyle(
                          color: _kTextSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Arama kriterlerini değiştirmeyi deneyin',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(14),
                // Tablet/Desktop: daha büyük kartlar, daha iyi dokunmatik hedef
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final prod = products[index];
                  return _CatalogProductCard(
                    product: prod,
                    onAddToCart: widget.onAddToCart,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Arama Alanı Bileşeni ─────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
        prefixIcon: Icon(prefixIcon, color: _kTextSecondary, size: 20),
        suffixIcon: onClear != null
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: _kTextSecondary,
                onPressed: onClear,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kGreen, width: 2),
        ),
        filled: true,
        fillColor: _kSurface,
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

// ── Barkod Alanı Bileşeni ─────────────────────────────────────────────────────



// ── Ürün Kartı ────────────────────────────────────────────────────────────────

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
