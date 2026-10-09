// lib/presentation/pages/products_page.dart
// Serenut OS — Ürünler Sayfası
// Yeşil + Sarı + Premium POS Teması
// Generated: 21 Jun 2026 (v2)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/presentation/mixins/barcode_scanner_mixin.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/presentation/widgets/app_shell.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/widgets/product_image.dart';

import 'package:serenutos/presentation/widgets/app_notification_host.dart';

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

class _ProductsPageState extends ConsumerState<ProductsPage>
    with BarcodeScannerMixin<ProductsPage> {
  static final NumberFormat _stockFormat = NumberFormat.decimalPattern('tr_TR');
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  bool _isSearching = false;
  bool _isLabelSelectionMode = false;
  bool _isSelectingAllLabels = false;
  final Set<String> _selectedLabelProductIds = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    initBarcodeScanner();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    disposeBarcodeScanner();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool canHandleBarcodeScan() {
    if (!super.canHandleBarcodeScan()) return false;
    final activeIndex = ref.read(activeShellIndexProvider);
    return activeIndex == 4;
  }

  @override
  void onBarcodeScanned(String barcode) async {
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
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      final hasMore = ref.read(productsControllerProvider.notifier).hasMoreData;
      final loadingMore = ref.read(productLoadingMoreProvider);
      if (hasMore && !loadingMore) {
        ref.read(productsControllerProvider.notifier).loadNextPage();
      }
    }
  }

  void _toggleLabelSelection(ProductEntity product) {
    setState(() {
      if (!_selectedLabelProductIds.add(product.id)) {
        _selectedLabelProductIds.remove(product.id);
      }
    });
  }

  void _closeLabelSelection() {
    setState(() {
      _isLabelSelectionMode = false;
      _selectedLabelProductIds.clear();
    });
  }

  Future<void> _toggleAllMatchingLabels() async {
    if (_isSelectingAllLabels) return;
    setState(() => _isSelectingAllLabels = true);
    try {
      final ids = await ref
          .read(productsControllerProvider.notifier)
          .findAllMatchingIds();
      if (!mounted) return;
      setState(() {
        final allSelected =
            ids.isNotEmpty && ids.every(_selectedLabelProductIds.contains);
        if (allSelected) {
          _selectedLabelProductIds.removeAll(ids);
        } else {
          _selectedLabelProductIds.addAll(ids);
        }
      });
    } catch (_) {
      if (mounted) {
        AppNotificationHost.show(
          const SnackBar(
              content: Text('Ürünler toplu seçilemedi. Tekrar deneyin.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSelectingAllLabels = false);
    }
  }

  Future<void> _queueShelfLabels() async {
    var settings = ref.read(settingsNotifierProvider).valueOrNull ??
        ref.read(settingsNotifierProvider).value;
    if (settings == null) {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        settings = await repo.getSettings();
      } catch (_) {}
    }
    if (settings == null) {
      if (!mounted) return;
      AppNotificationHost.show(
        const SnackBar(content: Text('Yazıcı ayarları henüz hazır değil.')),
      );
      return;
    }
    final controller = ref.read(productsControllerProvider.notifier);
    final selectedIds = Set<String>.of(_selectedLabelProductIds);
    if (selectedIds.isEmpty) {
      AppNotificationHost.show(
        const SnackBar(content: Text('Etiket basılacak ürünleri seçin.')),
      );
      return;
    }
    var offset = 0;
    var queuedCount = 0;
    const pageSize = 500;
    while (true) {
      final page = await controller.findAllMatching(
        limit: pageSize,
        offset: offset,
      );
      if (!mounted) return;
      final selectedPage = page
          .where((product) => selectedIds.contains(product.id))
          .toList(growable: false);
      if (selectedPage.isNotEmpty) {
        await ref
            .read(printingApplicationServiceProvider)
            .queueProductLabels(selectedPage, settings);
        queuedCount += selectedPage.length;
      }
      if (page.length < pageSize) break;
      offset += page.length;
    }
    if (!mounted) return;
    if (queuedCount == 0) {
      AppNotificationHost.show(
        const SnackBar(
          content:
              Text('Seçilen ürünler mevcut arama ve filtrelerle eşleşmiyor.'),
        ),
      );
      return;
    }
    AppNotificationHost.show(
      SnackBar(content: Text('$queuedCount etiket yazdırma kuyruğuna alındı.')),
    );
    _closeLabelSelection();
  }

  @override
  Widget build(BuildContext context) {
    final filteredProductsVal = ref.watch(filteredProductsProvider);
    final loadingMore = ref.watch(productLoadingMoreProvider);
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
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            ref.read(productSearchQueryProvider.notifier).state = val;
            setState(() {});
          }
        });
      },
      actions: [
        if (_isLabelSelectionMode)
          IconButton(
            tooltip: 'Filtreye uyan tüm ürünleri seç / temizle',
            onPressed: _isSelectingAllLabels ? null : _toggleAllMatchingLabels,
            icon: _isSelectingAllLabels
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.select_all_rounded, color: _kGreen),
          ),
        IconButton(
          tooltip: _isLabelSelectionMode
              ? 'Etiket seçimini kapat'
              : 'Raf etiketi bas',
          onPressed: _isLabelSelectionMode
              ? _closeLabelSelection
              : () => setState(() => _isLabelSelectionMode = true),
          icon: Icon(
            _isLabelSelectionMode
                ? Icons.close_rounded
                : Icons.label_outline_rounded,
            color: _isLabelSelectionMode ? _kRed : _kTextSecondary,
          ),
        ),
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
      body: Builder(
        builder: (context) {
          final cachedProducts = filteredProductsVal.valueOrNull ??
              (ref.watch(productSearchQueryProvider).isEmpty &&
                      ref.watch(productCategoryFilterProvider) == null
                  ? ref.watch(salesProductsControllerProvider).valueOrNull
                  : null);
          if (cachedProducts == null && filteredProductsVal.isLoading) {
            return Column(
              children: [
                _buildSummaryBar(inventorySummary, const []),
                const LinearProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_kGreen),
                  backgroundColor: _kGreenLight,
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: 6,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, __) => Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _kBorder),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 140,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: 80,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          if (filteredProductsVal.hasError && cachedProducts == null) {
            return Center(
              child: Text(
                'Ürünler yüklenirken hata oluştu: ${filteredProductsVal.error}',
                style: const TextStyle(color: _kRed),
              ),
            );
          }
          final products = cachedProducts ?? const <ProductEntity>[];
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

          return NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 400) {
                if (hasMore && !loadingMore) {
                  ref.read(productsControllerProvider.notifier).loadNextPage();
                }
              }
              return false;
            },
            child: Column(
              children: [
                _buildSummaryBar(inventorySummary, products),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        ref.read(productsControllerProvider.notifier).refresh(),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;
                        if (isWide) {
                          return GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 440,
                              mainAxisExtent: 96,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: products.length + (loadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == products.length) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation(_kGreen),
                                  ),
                                );
                              }
                              final product = products[index];
                              final isSelected =
                                  _selectedLabelProductIds.contains(product.id);
                              return _buildProductCard(product, isSelected);
                            },
                          );
                        }

                        return ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: products.length + (loadingMore ? 1 : 0),
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
                            final isSelected =
                                _selectedLabelProductIds.contains(product.id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildProductCard(product, isSelected),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = MediaQuery.of(context).size.width >= 900;
          if (isDesktop) {
            return FloatingActionButton.extended(
              heroTag: 'fab_products',
              tooltip: _isLabelSelectionMode
                  ? '${_selectedLabelProductIds.length} etiketi yazdır'
                  : 'Yeni ürün ekle',
              onPressed: _isLabelSelectionMode
                  ? _queueShelfLabels
                  : () => context.push('/products/add'),
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              icon: Icon(_isLabelSelectionMode
                  ? Icons.print_rounded
                  : Icons.add_box_rounded),
              label: Text(
                _isLabelSelectionMode
                    ? '${_selectedLabelProductIds.length} Etiketi Yazdır'
                    : 'Yeni Ürün',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            );
          }
          return FloatingActionButton(
            heroTag: 'fab_products',
            tooltip: _isLabelSelectionMode
                ? '${_selectedLabelProductIds.length} etiketi yazdır'
                : 'Yeni ürün',
            onPressed: _isLabelSelectionMode
                ? _queueShelfLabels
                : () => context.push('/products/add'),
            backgroundColor: _kGreen,
            foregroundColor: Colors.white,
            child: Icon(_isLabelSelectionMode
                ? Icons.print_rounded
                : Icons.add_box_rounded),
          );
        },
      ),
    );
  }

  Future<void> _showQuickPriceDialog(ProductEntity product) async {
    final priceCtrl = TextEditingController(
      text: product.price.toStringAsFixed(2),
    );
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kGreenLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.price_change_rounded,
                      color: _kGreenDark, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Hızlı Fiyat Düzenle',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kText,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'Mevcut Fiyat: ₺${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Yeni Satış Fiyatı',
                    prefixText: '₺ ',
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kGreen, width: 2),
                    ),
                  ),
                  onChanged: (val) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç',
                    style: TextStyle(color: _kTextSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  final text = priceCtrl.text.replaceAll(',', '.').trim();
                  final newPrice = double.tryParse(text);
                  if (newPrice == null || newPrice < 0) {
                    setDialogState(() {
                      errorText = 'Geçerli bir fiyat girin.';
                    });
                    return;
                  }

                  Navigator.pop(ctx);
                  try {
                    final updated = product.copyWith(price: newPrice);
                    await ref
                        .read(productsControllerProvider.notifier)
                        .updateProduct(updated);
                    AppNotificationHost.show(
                      SnackBar(
                        content: Text(
                            '${product.name} fiyatı ₺${newPrice.toStringAsFixed(2)} olarak güncellendi.'),
                        backgroundColor: _kGreen,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } catch (e) {
                    AppNotificationHost.show(
                      SnackBar(
                        content:
                            Text('Fiyat güncellenirken bir hata oluştu: $e'),
                        backgroundColor: _kRed,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProductCard(ProductEntity product, bool isSelected) {
    final isLowStock = product.quantity <= product.minStock;
    final isOutOfStock = product.quantity <= 0;

    final stockColor =
        isOutOfStock ? _kRed : (isLowStock ? Colors.orange[700]! : _kGreen);
    final stockBg =
        isOutOfStock ? _kRedLight : (isLowStock ? _kAmberLight : _kGreenLight);
    final stockText =
        isOutOfStock ? 'Tükendi' : (isLowStock ? 'Kritik Stok' : 'Stokta Var');

    final cardBg = isSelected
        ? const Color(0xFFDCFCE7)
        : (isOutOfStock
            ? const Color(0xFFFFF5F5)
            : (isLowStock ? const Color(0xFFFFFDF5) : const Color(0xFFF8FAFC)));
    final cardBorder = isSelected
        ? _kGreen
        : (isOutOfStock
            ? const Color(0xFFFCA5A5).withValues(alpha: 0.55)
            : (isLowStock
                ? const Color(0xFFFCD34D).withValues(alpha: 0.55)
                : const Color(0xFFCBD5E1).withValues(alpha: 0.55)));

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cardBorder,
          width: isSelected ? 2 : 1.0,
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
          borderRadius: BorderRadius.circular(14),
          splashColor: stockColor.withValues(alpha: 0.08),
          highlightColor: stockColor.withValues(alpha: 0.04),
          onLongPress: () {
            if (!_isLabelSelectionMode) {
              setState(() => _isLabelSelectionMode = true);
            }
            _toggleLabelSelection(product);
          },
          onTap: () => _isLabelSelectionMode
              ? _toggleLabelSelection(product)
              : context.push('/products/edit/${product.id}', extra: product),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // ── Sol Dikey Renk Vurgusu ─────────────────
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: stockColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                if (_isLabelSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    activeColor: _kGreen,
                    onChanged: (_) => _toggleLabelSelection(product),
                  ),
                  const SizedBox(width: 4),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ProductImage(
                    imageUrl: product.imageUrl,
                    barcode: product.id,
                    size: 44,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _kText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.brand.isNotEmpty
                            ? product.brand
                            : product.category,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      if (product.brand.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _kBorder),
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
                const SizedBox(width: 10),
                SizedBox(
                  width: 88,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => _showQuickPriceDialog(product),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kGreenLight,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: _kGreen.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₺${product.price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: _kGreenDark,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.edit_outlined,
                                  size: 11, color: _kGreenDark),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: stockBg,
                          borderRadius: BorderRadius.circular(4),
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
                      const SizedBox(height: 2),
                      Text(
                        '${_stockFormat.format(product.quantity)} ${product.unit}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isOutOfStock ? _kRed : _kText,
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
  }

  Widget _buildSummaryBar(
    AsyncValue<ProductInventorySummary> summaryValue,
    List<ProductEntity> visibleProducts,
  ) {
    final summary = summaryValue.valueOrNull;
    final productCount = summary?.productCount ?? visibleProducts.length;
    final totalStockQuantity = summary?.totalQuantity ??
        visibleProducts.fold<num>(0, (sum, p) => sum + p.quantity);
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
              count: '${_stockFormat.format(totalStockQuantity)} Miktar',
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
