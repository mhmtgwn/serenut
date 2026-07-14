// lib/presentation/pages/products_page.dart
// Serenut POS — Ürünler Sayfası
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

// ── POS Tema Renkleri ──────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;
  bool _showFilters = false;

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
      debugPrint('[ProductsPage] ⚠️ Barcode lookup failed for "$cleanBarcode": $e');
      TelemetryService().logError(e, st, context: 'products_page_barcode_lookup');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(productsControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProductsVal = ref.watch(filteredProductsProvider);
    final hasMore = ref.watch(productsControllerProvider.notifier).hasMoreData;
    final categoriesVal = ref.watch(productCategoriesProvider);
    final selectedCategory = ref.watch(productCategoryFilterProvider);

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
                  const Icon(Icons.filter_list_rounded, size: 18, color: _kGreenDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedCategory == null ? 'Kategori: Tümü' : 'Kategori: $selectedCategory',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                  ),
                  Icon(
                    _showFilters
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
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
                            ref.read(productCategoryFilterProvider.notifier).state = null;
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
                          ref.read(productCategoryFilterProvider.notifier).state = isAll ? null : catName;
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
      body: filteredProductsVal.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kGreen)),
                ),
                error: (err, _) => Center(
                  child: Text('Ürünler yüklenirken hata oluştu: $err', style: const TextStyle(color: _kRed)),
                ),
                data: (products) {
                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text('Kayıtlı ürün bulunamadı.', style: TextStyle(color: _kTextSecondary)),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      _buildSummaryBar(products),
                      Expanded(
                        child: ListView.builder(
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
                            final isLowStock = product.quantity <= 5;
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
                                  onTap: () => context.push('/products/edit/${product.id}', extra: product),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        // Sol: Ürün görseli/kategori ikonu çerçevesi (Premium square design)
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: stockBg,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: stockColor.withValues(alpha: 0.15)),
                                          ),
                                          child: Icon(
                                            _getCategoryIcon(product.category),
                                            color: stockColor,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Orta Kısım: Ürün Adı, Açıklama, Kategori Tagı ve ID
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                                product.description.isEmpty ? 'Açıklama girilmemiş' : product.description,
                                                style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
                                                  const SizedBox(width: 6),
                                                  const Icon(Icons.qr_code_scanner_rounded, size: 10, color: _kTextSecondary),
                                                  const SizedBox(width: 2),
                                                  Expanded(
                                                    child: Text(
                                                      product.id,
                                                      style: const TextStyle(color: _kTextSecondary, fontSize: 9, fontFamily: 'monospace'),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Sağ Kısım: Satış Fiyatı ve Stok Miktarı
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _kGreenLight,
                                                borderRadius: BorderRadius.circular(6),
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
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
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
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${product.quantity} Adet',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isOutOfStock ? _kRed : _kText,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 8),

                                        // Silme Aksiyonu (Compact delete button, no redundant chevron)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 18),
                                          onPressed: () => _confirmDelete(context, product),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          tooltip: 'Sil',
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
        label: const Text('Yeni Ürün', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSummaryBar(List<ProductEntity> products) {
    final totalStockValue = products.fold<double>(0.0, (sum, p) => sum + (p.price * p.quantity));
    final totalStockQuantity = products.fold<int>(0, (sum, p) => sum + p.quantity);
    final criticalStockCount = products.where((p) => p.quantity <= 5).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _SummaryChip(
              label: 'Toplam Envanter',
              value: '${products.length} Çeşit',
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

  void _confirmDelete(BuildContext context, ProductEntity product) {
    requireAdminAccess(
      context,
      title: 'Ürün Silme Yetkisi',
      requirePin: true,
      onGranted: (approvedByUserId, approvedByUserName) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Ürünü Sil'),
              content: Text('"${product.name}" ürününü silmek istediğinize emin misiniz?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w900)),
                Text(count, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

