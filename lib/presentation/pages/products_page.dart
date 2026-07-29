// lib/presentation/pages/products_page.dart
// Serenut OS — Ürünler Sayfası
// Yeşil + Sarı + Premium POS Teması
// Generated: 21 Jun 2026 (v2)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/widgets/app_shell.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/widgets/product_image.dart';

// ── POS Tema Renkleri ──────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kAmber = POSColors.amber;
const _kAmberLight = POSColors.amberLight;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;

  String _barcodeBuffer = '';
  DateTime? _lastBufferTime;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final activeIndex = ref.read(activeShellIndexProvider);
    if (activeIndex != 4) return false;

    final now = DateTime.now();
    if (_lastBufferTime != null) {
      final diff = now.difference(_lastBufferTime!).inMilliseconds;
      if (diff > 80) {
        _barcodeBuffer = '';
      }
    }
    _lastBufferTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_barcodeBuffer.length >= 3) {
        final code = _barcodeBuffer;
        _barcodeBuffer = '';
        _onBarcodeScanned(code);
        return true;
      }
      _barcodeBuffer = '';
    } else {
      String? char = event.character;
      if (char == null) {
        final label = event.logicalKey.keyLabel;
        if (label.length == 1 && RegExp(r'[a-zA-Z0-9-]').hasMatch(label)) {
          char = label;
        }
      }
      if (char != null && char.length == 1) {
        _barcodeBuffer += char;
      }
    }
    return false;
  }

  void _onBarcodeScanned(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return;

    // 1. Update UI search bar
    _searchController.text = cleanBarcode;
    ref.read(productSearchQueryProvider.notifier).state = cleanBarcode;
    setState(() {
      _isSearching = true;
    });

    // 2. Fetch from DB directly to open details page
    try {
      final repository = await ref.read(productRepositoryProvider.future);
      var matched = await repository.findById(cleanBarcode);

      if (matched == null) {
        // Try searching by name/exact matches
        final results = await repository.searchByName(cleanBarcode);
        if (results.isNotEmpty) {
          matched = results.first;
        }
      }

      if (matched != null && mounted) {
        context.push('/products/edit/${matched.id}', extra: matched);
      }
    } catch (e, st) {
      debugPrint(
          '[ProductsPage] ⚠️ Barcode lookup failed for "$cleanBarcode": $e');
      TelemetryService()
          .logError(e, st, context: 'products_page_barcode_lookup');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(productsControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProductsVal = ref.watch(filteredProductsProvider);
    final hasMore = ref.watch(productsControllerProvider.notifier).hasMoreData;
    final categoriesVal = ref.watch(productCategoriesProvider);
    final selectedCategory = ref.watch(productCategoryFilterProvider);
    final inventorySummary = ref.watch(productInventorySummaryProvider);

    return PosPageLayout(
      title: 'Ürünler',
      isSearching: _isSearching,
      onSearchToggled: (val) => setState(() => _isSearching = val),
      searchController: _searchController,
      searchHint: 'Ürün adı veya açıklama ara...',
      onSearchChanged: (val) {
        ref.read(productSearchQueryProvider.notifier).state = val;
        setState(() {});
      },
      actions: [
        Semantics(
          label: selectedCategory == null
              ? 'Kategori filtresi'
              : 'Kategori filtresi: $selectedCategory',
          button: true,
          child: Badge(
            isLabelVisible: selectedCategory != null,
            backgroundColor: _kAmber,
            smallSize: 8,
            child: IconButton(
              tooltip: selectedCategory == null
                  ? 'Kategori filtresi'
                  : 'Kategori: $selectedCategory',
              onPressed: () => _showCategoryFilterSheet(
                categoriesVal,
                selectedCategory,
              ),
              icon: Icon(
                Icons.filter_list_rounded,
                color: selectedCategory == null ? _kTextSecondary : _kGreen,
              ),
            ),
          ),
        ),
      ],
      body: filteredProductsVal.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(_kGreen)),
        ),
        error: (err, _) => Center(
          child: Text('Ürünler yüklenirken hata oluştu: $err',
              style: const TextStyle(color: _kRed)),
        ),
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text('Kayıtlı ürün bulunamadı.',
                      style: TextStyle(color: _kTextSecondary)),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildSummaryBar(inventorySummary, products),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () =>
                      ref.read(productsControllerProvider.notifier).refresh(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: products.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == products.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(_kGreen),
                            ),
                          ),
                        );
                      }
                      final product = products[index];
                      final isLowStock = product.quantity <= product.minStock;
                      final isOutOfStock = product.quantity <= 0;

                      final stockColor = isOutOfStock
                          ? _kRed
                          : (isLowStock ? Colors.orange[700]! : _kGreen);
                      final stockBg = isOutOfStock
                          ? _kRedLight
                          : (isLowStock ? _kAmberLight : _kGreenLight);
                      final stockText = isOutOfStock
                          ? 'Tükendi'
                          : (isLowStock ? 'Kritik Stok' : 'Stokta Var');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
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
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => context.push(
                                '/products/edit/${product.id}',
                                extra: product),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  // Sol: Ürün görseli/kategori ikonu çerçevesi (Premium square design)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ProductImage(
                                      imageUrl: product.imageUrl,
                                      barcode: product.id,
                                      size: 48,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Orta Kısım: Ürün Adı, Açıklama, Kategori Tagı ve ID
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: _kText,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          product.brand.isNotEmpty
                                              ? product.brand
                                              : product.category,
                                          style: const TextStyle(
                                              color: _kTextSecondary,
                                              fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        if (product.brand.isNotEmpty)
                                          Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border:
                                                    Border.all(color: _kBorder),
                                              ),
                                              child: Text(
                                                product.category,
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kTextSecondary,
                                                ),
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Sağ Kısım: Satış Fiyatı ve Stok Miktarı
                                  SizedBox(
                                    width: 88,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _kGreenLight,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '₺${product.price.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              color: _kGreenDark,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: stockBg,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            stockText,
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: stockColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${product.quantity} ${product.unit}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                isOutOfStock ? _kRed : _kText,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_products',
        onPressed: () => context.push('/products/add'),
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_box_rounded),
        label: const Text('Yeni Ürün',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSummaryBar(
    AsyncValue<ProductInventorySummary> summaryValue,
    List<ProductEntity> visibleProducts,
  ) {
    final summary = summaryValue.valueOrNull;
    final productCount = summary?.productCount ?? visibleProducts.length;
    final totalStockQuantity = summary?.totalQuantity ??
        visibleProducts.fold<int>(0, (sum, p) => sum + p.quantity);
    final totalStockValue = summary?.stockValue ??
        visibleProducts.fold<double>(
          0,
          (sum, p) =>
              sum +
              ((p.purchasePrice > 0 ? p.purchasePrice : p.price) * p.quantity),
        );
    final criticalStockCount = summary?.criticalCount ??
        visibleProducts.where((p) => p.quantity <= p.minStock).length;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _SummaryChip(
              label: 'Toplam Envanter',
              value: '$productCount Çeşit',
              count: '$totalStockQuantity Adet',
              color: _kGreenDark,
              bg: _kGreenLight,
              icon: Icons.inventory_2_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryChip(
              label: 'Stok Değeri',
              value: '₺${totalStockValue.toStringAsFixed(2)}',
              count: '$criticalStockCount Kritik',
              color: _kAmber,
              bg: _kAmberLight,
              icon: Icons.payments_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryFilterSheet(
    List<String> categories,
    String? selectedCategory,
  ) async {
    const allCategories = '__all_categories__';
    var pendingCategory = selectedCategory ?? allCategories;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: .68,
          minChildSize: .42,
          maxChildSize: .92,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return Material(
                  color: POSColors.card,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadii.lg),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.sm,
                          AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Kategori Filtresi',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Kapat',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          itemCount: categories.length + 1,
                          itemBuilder: (context, index) {
                            final isAll = index == 0;
                            final category =
                                isAll ? allCategories : categories[index - 1];
                            return RadioListTile<String>(
                              value: category,
                              groupValue: pendingCategory,
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() => pendingCategory = value);
                              },
                              secondary: Icon(
                                isAll
                                    ? Icons.grid_view_rounded
                                    : _getCategoryIcon(category),
                                color: pendingCategory == category
                                    ? POSColors.green
                                    : POSColors.textSecondary,
                              ),
                              title: Text(isAll ? 'Tüm Kategoriler' : category),
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: const BoxDecoration(
                          color: POSColors.card,
                          border: Border(
                            top: BorderSide(color: POSColors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(context, allCategories),
                                child: const Text('Temizle'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(
                                  context,
                                  pendingCategory,
                                ),
                                child: const Text('Uygula'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    ref.read(productCategoryFilterProvider.notifier).state =
        result == allCategories ? null : result;
  }

  void _confirmDelete(BuildContext context, ProductEntity product) {
    requireAdminAccess(
      context,
      title: 'Ürün Silme Yetkisi',
      onGranted: (approvedByUserId, approvedByUserName) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Ürünü Sil'),
              content: Text(
                  '"${product.name}" ürününü silmek istediğinize emin misiniz?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    ref.read(productsControllerProvider.notifier).deleteProduct(
                          product.id,
                          approvedByUserId: approvedByUserId,
                          approvedByUserName: approvedByUserName,
                        );
                    Navigator.pop(context);
                  },
                  child: const Text('Sil'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase().trim()) {
      case 'içecek':
      case 'icecek':
      case 'meşrubat':
      case 'su':
      case 'gazoz':
      case 'soda':
        return Icons.local_drink_rounded;
      case 'gıda':
      case 'gida':
      case 'yiyecek':
      case 'ekmek':
      case 'bakliyat':
      case 'makarna':
        return Icons.restaurant_rounded;
      case 'atıştırmalık':
      case 'atistirmalik':
      case 'bisküvi':
      case 'çikolata':
      case 'cips':
      case 'tatlı':
      case 'dondurma':
        return Icons.cookie_rounded;
      case 'temizlik':
      case 'deterjan':
      case 'sabun':
        return Icons.clean_hands_rounded;
      case 'manav':
      case 'meyve':
      case 'sebze':
        return Icons.eco_rounded;
      case 'şarküteri':
      case 'sarkuteri':
      case 'peynir':
      case 'süt':
      case 'yoğurt':
        return Icons.bakery_dining_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }
}

// ── Özet Chip Widget ─────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final String count;
  final Color color;
  final Color bg;
  final IconData icon;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
    required this.bg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600)),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        color: color,
                        fontWeight: FontWeight.w900)),
                Text(count,
                    style: TextStyle(
                        fontSize: 10, color: color.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
