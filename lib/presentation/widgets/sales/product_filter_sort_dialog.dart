// lib/presentation/widgets/sales/product_filter_sort_dialog.dart
import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';

class ProductFilterSortDialog extends StatefulWidget {
  final String? initialCategory;
  final String? initialSort;
  final String? initialStock;
  final List<String> categories;
  final void Function({
    required String? category,
    required String? sortBy,
    required String? stockFilter,
  }) onApply;

  const ProductFilterSortDialog({
    super.key,
    required this.initialCategory,
    required this.initialSort,
    required this.initialStock,
    required this.categories,
    required this.onApply,
  });

  static Future<void> show({
    required BuildContext context,
    required String? initialCategory,
    required String? initialSort,
    required String? initialStock,
    required List<String> categories,
    required void Function({
      required String? category,
      required String? sortBy,
      required String? stockFilter,
    }) onApply,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ProductFilterSortDialog(
        initialCategory: initialCategory,
        initialSort: initialSort,
        initialStock: initialStock,
        categories: categories,
        onApply: onApply,
      ),
    );
  }

  @override
  State<ProductFilterSortDialog> createState() =>
      _ProductFilterSortDialogState();
}

class _ProductFilterSortDialogState extends State<ProductFilterSortDialog> {
  late String? _selectedCategory;
  late String? _selectedSort;
  late String? _selectedStock;

  static const _kGreen = POSColors.green;
  static const _kGreenDark = POSColors.greenDark;
  static const _kGreenLight = POSColors.greenLight;
  static const _kText = Color(0xFF0F172A);
  static const _kTextSecondary = Color(0xFF64748B);
  static const _kBorder = Color(0xFFE2E8F0);
  static const _kSurface = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _selectedSort = widget.initialSort;
    _selectedStock = widget.initialStock;
  }

  void _resetFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedSort = null;
      _selectedStock = null;
    });
  }

  void _applyAndClose() {
    widget.onApply(
      category: _selectedCategory,
      sortBy: _selectedSort,
      stockFilter: _selectedStock,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = _selectedCategory != null ||
        _selectedSort != null ||
        _selectedStock != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 680,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Dialog Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _kBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _kGreenLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded,
                        color: _kGreenDark, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sıralama ve Filtreleme',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Ürün sıralama ve kategori filtreleri',
                          style: TextStyle(
                            fontSize: 12,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _kTextSecondary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Kapat',
                    splashRadius: 20,
                  ),
                ],
              ),
            ),

            // ── Dialog Body ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Sıralama
                    _buildSectionHeader(
                      icon: Icons.sort_rounded,
                      title: 'Sıralama Ölçütü',
                    ),
                    const SizedBox(height: 10),
                    _buildSortOptions(),

                    const SizedBox(height: 24),

                    // Section 2: Kategori Filtresi
                    _buildSectionHeader(
                      icon: Icons.category_rounded,
                      title: 'Kategoriye Göre Filtrele',
                    ),
                    const SizedBox(height: 10),
                    _buildCategoryFilterOptions(),

                    const SizedBox(height: 24),

                    // Section 3: Stok Filtresi
                    _buildSectionHeader(
                      icon: Icons.inventory_2_outlined,
                      title: 'Stok Durumu',
                    ),
                    const SizedBox(height: 10),
                    _buildStockFilterOptions(),
                  ],
                ),
              ),
            ),

            // ── Dialog Footer ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: _kSurface,
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              child: Row(
                children: [
                  if (hasActiveFilter)
                    TextButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Sıfırla'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTextSecondary,
                      side: const BorderSide(color: _kBorder),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _applyAndClose,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Uygula'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _kGreenDark),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _kText,
          ),
        ),
      ],
    );
  }

  Widget _buildSortOptions() {
    final sortItems = [
      (
        key: 'best_selling',
        title: 'En Çok Satanlar',
        subtitle: 'En popüler ürünler ilk sırada',
        icon: Icons.local_fire_department_rounded,
        iconColor: const Color(0xFFEA580C),
      ),
      (
        key: 'category',
        title: 'Kategoriye Göre',
        subtitle: 'Kategori sırasına göre diz',
        icon: Icons.category_rounded,
        iconColor: const Color(0xFF2563EB),
      ),
      (
        key: 'name_asc',
        title: 'Ürün Adı (A → Z)',
        subtitle: 'Alfabetik sıralama',
        icon: Icons.sort_by_alpha_rounded,
        iconColor: _kGreenDark,
      ),
      (
        key: 'name_desc',
        title: 'Ürün Adı (Z → A)',
        subtitle: 'Ters alfabetik sıralama',
        icon: Icons.sort_by_alpha_rounded,
        iconColor: const Color(0xFF475569),
      ),
      (
        key: 'price_asc',
        title: 'Fiyat: Düşükten Yükseğe',
        subtitle: 'En ucuzdan en pahalıya',
        icon: Icons.arrow_upward_rounded,
        iconColor: const Color(0xFF059669),
      ),
      (
        key: 'price_desc',
        title: 'Fiyat: Yüksekten Düşüğe',
        subtitle: 'En pahalıdan en ucuza',
        icon: Icons.arrow_downward_rounded,
        iconColor: const Color(0xFFD97706),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 380;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: sortItems.map((item) {
            // null or 'name_asc' both default to A-Z, but we differentiate if user selected 'name_asc'
            final isSelected = _selectedSort == item.key ||
                (_selectedSort == null && item.key == 'name_asc');

            final cardWidth = isWide
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;

            return SizedBox(
              width: cardWidth,
              child: Material(
                color: isSelected ? _kGreenLight : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? _kGreen : _kBorder,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSort = item.key;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: item.iconColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(item.icon,
                              size: 18, color: item.iconColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected ? _kGreenDark : _kText,
                                ),
                              ),
                              Text(
                                item.subtitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected
                                      ? const Color(0xFF15803D)
                                      : _kTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded,
                              color: _kGreen, size: 18)
                        else
                          Icon(Icons.radio_button_unchecked_rounded,
                              color: Colors.grey.shade400, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCategoryFilterOptions() {
    final isAllSelected =
        _selectedCategory == null || _selectedCategory == 'Tümü';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // "Tüm Kategoriler" Chip
        ChoiceChip(
          label: const Text('Tümü'),
          avatar: Icon(
            Icons.grid_view_rounded,
            size: 16,
            color: isAllSelected ? Colors.white : _kTextSecondary,
          ),
          selected: isAllSelected,
          selectedColor: _kGreen,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isAllSelected ? Colors.white : _kText,
          ),
          side: BorderSide(
            color: isAllSelected ? _kGreen : _kBorder,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (_) {
            setState(() => _selectedCategory = null);
          },
        ),

        // List of all categories
        ...widget.categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return ChoiceChip(
            label: Text(cat),
            avatar: Icon(
              Icons.label_outline_rounded,
              size: 16,
              color: isSelected ? Colors.white : _kTextSecondary,
            ),
            selected: isSelected,
            selectedColor: _kGreen,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : _kText,
            ),
            side: BorderSide(
              color: isSelected ? _kGreen : _kBorder,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (_) {
              setState(() => _selectedCategory = isSelected ? null : cat);
            },
          );
        }),
      ],
    );
  }

  Widget _buildStockFilterOptions() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Tümü'),
          selected: _selectedStock == null,
          selectedColor: _kGreenLight,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _selectedStock == null ? _kGreenDark : _kText,
          ),
          side: BorderSide(
            color: _selectedStock == null ? _kGreen : _kBorder,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (_) => setState(() => _selectedStock = null),
        ),
        ChoiceChip(
          label: const Text('Sadece Stokta'),
          selected: _selectedStock == 'in_stock',
          selectedColor: _kGreenLight,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _selectedStock == 'in_stock' ? _kGreenDark : _kText,
          ),
          side: BorderSide(
            color: _selectedStock == 'in_stock' ? _kGreen : _kBorder,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (_) => setState(() => _selectedStock = 'in_stock'),
        ),
        ChoiceChip(
          label: const Text('Kritik Stok'),
          selected: _selectedStock == 'critical',
          selectedColor: const Color(0xFFFEF9C3),
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _selectedStock == 'critical'
                ? const Color(0xFF854D0E)
                : _kText,
          ),
          side: BorderSide(
            color: _selectedStock == 'critical'
                ? const Color(0xFFEAB308)
                : _kBorder,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (_) => setState(() => _selectedStock = 'critical'),
        ),
      ],
    );
  }
}
