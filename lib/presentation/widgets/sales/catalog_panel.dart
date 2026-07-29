// lib/presentation/widgets/sales/catalog_panel.dart
// Serenut OS — Ürün Kataloğu Paneli
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

part 'catalog/catalog_product_card.dart';

// ── Mevcut POS Tema Renkleri (korundu) ───────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kCardBg = Colors.white;
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
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

  Widget _buildCategoryChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? _kGreen : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: isSelected ? _kGreen : _kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 17, color: isSelected ? Colors.white : _kTextSecondary),
              const SizedBox(width: 7),
              Text(label,
                  maxLines: 1,
                  style: TextStyle(
                    color: isSelected ? Colors.white : _kText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProductsVal = ref.watch(salesProductsControllerProvider);
    final categoriesVal = ref.watch(productCategoriesProvider);
    final selectedCategory = ref.watch(salesProductCategoryFilterProvider);
    final stockFilter = ref.watch(salesProductStockFilterProvider);
    final sortBy = ref.watch(salesProductSortProvider);

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
            Badge(
              isLabelVisible: stockFilter != null || sortBy != null,
              child: IconButton(
                tooltip: 'Ürün filtreleri',
                onPressed: _showProductFilters,
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
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
              icon: const Icon(Icons.photo_camera_rounded,
                  color: _kGreen, size: 22),
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
          filterWidget: SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: categoriesVal.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final isAll = index == 0;
                final category = isAll ? 'Tümü' : categoriesVal[index - 1];
                final isSelected = isAll
                    ? selectedCategory == null
                    : selectedCategory == category;
                return _buildCategoryChip(
                  label: category,
                  icon: isAll
                      ? Icons.grid_view_rounded
                      : _getCategoryIcon(category),
                  isSelected: isSelected,
                  onTap: () {
                    ref
                        .read(salesProductCategoryFilterProvider.notifier)
                        .state = isAll ? null : category;
                  },
                );
              },
            ),
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
                    Icon(Icons.error_outline_rounded,
                        size: 36, color: _kRed.withValues(alpha: 0.6)),
                    const SizedBox(height: 8),
                    const Text(
                      'Ürünler yüklenirken hata oluştu',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _kRed,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      err.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: _kTextSecondary, fontSize: 11),
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
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.grey[300]),
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

  Future<void> _showProductFilters() async {
    var stock = ref.read(salesProductStockFilterProvider);
    var sort = ref.read(salesProductSortProvider);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ürünleri filtrele',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tüm stoklar'),
                    selected: stock == null,
                    onSelected: (_) => setSheetState(() => stock = null),
                  ),
                  ChoiceChip(
                    label: const Text('Stokta'),
                    selected: stock == 'in_stock',
                    onSelected: (_) =>
                        setSheetState(() => stock = 'in_stock'),
                  ),
                  ChoiceChip(
                    label: const Text('Kritik stok'),
                    selected: stock == 'critical',
                    onSelected: (_) =>
                        setSheetState(() => stock = 'critical'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: sort,
                decoration: const InputDecoration(labelText: 'Sıralama'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Ürün adına göre')),
                  DropdownMenuItem(
                      value: 'best_selling', child: Text('En çok satanlar')),
                  DropdownMenuItem(
                      value: 'price_asc', child: Text('Fiyat: düşükten yükseğe')),
                  DropdownMenuItem(
                      value: 'price_desc', child: Text('Fiyat: yüksekten düşüğe')),
                ],
                onChanged: (value) => setSheetState(() => sort = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.read(salesProductStockFilterProvider.notifier).state = stock;
                  ref.read(salesProductSortProvider.notifier).state = sort;
                  Navigator.pop(context);
                },
                child: const Text('Uygula'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Arama Alanı Bileşeni ─────────────────────────────────────────────────────
