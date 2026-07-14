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
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';

part 'catalog/catalog_search_field.dart';
part 'catalog/catalog_product_card.dart';

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

  final TextEditingController searchController;
  final TextEditingController barcodeController;
  final FocusNode? barcodeFocusNode;
  final Function(ProductEntity) onAddToCart;
  final Function(String, List<ProductEntity>) onBarcodeSubmit;

  const CatalogPanel({
    super.key,
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
  bool _showFilters = false;

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

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase().trim()) {
      case 'içecek':
      case 'icecek':
      case 'meşrubat':
      case 'su':
      case 'gazoz':
        return Icons.local_drink_rounded;
      case 'tatlı':
      case 'tatli':
      case 'pasta':
        return Icons.cake_rounded;
      case 'kahve':
      case 'çay':
      case 'cay':
      case 'sıcak içecek':
        return Icons.coffee_rounded;
      case 'yiyecek':
      case 'yemek':
      case 'fastfood':
      case 'burger':
      case 'pizza':
        return Icons.restaurant_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Widget _buildCategoryListRow(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? _kGreen : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? _kGreen : const Color(0xFF64748B),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? _kGreenDark : const Color(0xFF334155),
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: _kGreen,
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProductsVal = ref.watch(salesProductsControllerProvider);
    final categoriesVal       = ref.watch(productCategoriesProvider);
    final selectedCategory    = ref.watch(salesProductCategoryFilterProvider);

    return Column(
      children: [
        PosHeader(
          title: 'Satış',
          isSearching: _isSearching,
          onSearchToggled: (val) => setState(() => _isSearching = val),
          searchController: widget.searchController,
          searchHint: 'Ürün ara...',
          onSearchChanged: (val) {
            ref.read(salesProductSearchQueryProvider.notifier).state = val;
            setState(() {});
          },
          showSettings: false,
          showStatusIndicator: false,
          actions: [
            // Barkod tarama ikonu - Kamera
            IconButton(
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: () {
                BarcodeScannerDialog.show(
                  context,
                  onBarcodeScanned: (code) {
                    filteredProductsVal.whenData((list) {
                      widget.onBarcodeSubmit(code, list);
                    });
                  },
                );
              },
              icon: const Icon(Icons.photo_camera_rounded, color: _kGreen, size: 22),
              tooltip: 'Kamera Tarayıcı',
            ),
            const SizedBox(width: 4),
            // Satış geçmişi ikonu
            IconButton(
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: () => context.push('/sales/history'),
              icon: const Icon(Icons.history_rounded, color: _kGreen, size: 22),
              tooltip: 'Satış Geçmişi',
            ),
            const SizedBox(width: 4),
          ],
          filterWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _showFilters = !_showFilters),
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
                          selectedCategory == null ? 'Kategori: Tümü' : 'Kategori: $selectedCategory',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kText,
                          ),
                        ),
                      ),
                      Icon(
                        _showFilters
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: _kTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              'Kategori Seçin',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _kText,
                              ),
                            ),
                          ),
                          if (selectedCategory != null)
                            TextButton(
                              onPressed: () {
                                ref.read(salesProductCategoryFilterProvider.notifier).state = null;
                                setState(() => _showFilters = false);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: _kGreen,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Temizle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Column(
                        children: List.generate(categoriesVal.length + 1, (index) {
                          final isAll = index == 0;
                          final catName = isAll ? 'Tümü' : categoriesVal[index - 1];
                          final isSelected = isAll ? selectedCategory == null : selectedCategory == catName;
                          final icon = isAll ? Icons.grid_view_rounded : _getCategoryIcon(catName);

                          return _buildCategoryListRow(
                            context,
                            label: catName,
                            icon: icon,
                            isSelected: isSelected,
                            onTap: () {
                              ref.read(salesProductCategoryFilterProvider.notifier).state = isAll ? null : catName;
                              setState(() => _showFilters = false);
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                crossFadeState: _showFilters ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _kBorder),

        // ── ÜRÜN GRİDİ ───────────────────────────────────────────────────
        Expanded(
          child: filteredProductsVal.when(

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

