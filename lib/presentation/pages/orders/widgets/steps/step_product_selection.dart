part of '../order_creation_dialog.dart';

// Extracted Product Selection Step widgets for OrderCreationDialog
extension OrderCreationProductStep on OrderCreationDialogState {
  Widget _buildProductStep() {
    final productsVal = ref.watch(ordersProductsControllerProvider);
    final loadingMore = ref.watch(productLoadingMoreProvider);
    final hasMore =
        ref.watch(ordersProductsControllerProvider.notifier).hasMoreData;
    final categories = ref.watch(productCategoriesProvider);
    final categoryFilter = ref.watch(ordersProductCategoryFilterProvider);
    final stockFilter = ref.watch(ordersProductStockFilterProvider);
    final sortBy = ref.watch(ordersProductSortProvider);

    final cachedProducts = productsVal.valueOrNull;
    if (cachedProducts == null && productsVal.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen)),
      );
    }
    if (productsVal.hasError && cachedProducts == null) {
      return Center(
        child: Text('Ürünler yüklenemedi: ${productsVal.error}',
            style: const TextStyle(color: _kRed)),
      );
    }

    final filtered = cachedProducts ?? const <ProductEntity>[];
        final catalogWidget = Column(
          children: [
            // Search & Category toggle filter bar (like Sales screen catalog)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (_isProductSearching) ...[
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: TextField(
                          controller: _productSearchController,
                          focusNode: _productSearchFocusNode,
                          decoration: const InputDecoration(
                            hintText: 'Ürün ara...',
                            hintStyle: TextStyle(
                                color: _kTextSecondary, fontSize: 13),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: _kTextSecondary, size: 18),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 9, horizontal: 12),
                          ),
                          style: const TextStyle(
                              color: _kText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          onChanged: (val) {
                            ref
                                .read(
                                    ordersProductSearchQueryProvider.notifier)
                                .state = val;
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: _kRed),
                      onPressed: () {
                        updateState(() {
                          _isProductSearching = false;
                          _productSearchController.clear();
                        });
                        ref
                            .read(ordersProductSearchQueryProvider.notifier)
                            .state = '';
                      },
                    ),
                  ] else ...[
                    IconButton(
                      icon: const Icon(Icons.search_rounded, color: _kGreen),
                      tooltip: 'Ara',
                      onPressed: () {
                        updateState(() {
                          _isProductSearching = true;
                        });
                      },
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _showOrderProductFilters(categories),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9), // Slate 100
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.filter_list_rounded,
                                  size: 16, color: _kGreenDark),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  categoryFilter == null || categoryFilter.isEmpty
                                      ? 'Kategori: Tümü'
                                      : 'Kategori: $categoryFilter',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _kText,
                                  ),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 16, color: _kTextSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Badge(
                    isLabelVisible: categoryFilter != null ||
                        stockFilter != null ||
                        sortBy != null,
                    child: IconButton(
                      onPressed: () => _showOrderProductFilters(categories),
                      icon: const Icon(Icons.tune_rounded, color: _kGreen),
                      tooltip: 'Sıralama ve Filtreler',
                    ),
                  ),
                  // Photo Camera scanner
                  IconButton(
                    onPressed: () {
                      BarcodeScannerDialog.show(
                        context,
                        onBarcodeScanned: (code) {
                          _handleBarcodeSubmit(code, filtered);
                        },
                      );
                    },
                    icon: const Icon(Icons.photo_camera_rounded,
                        color: _kGreen),
                    tooltip: 'Kamera Tarayıcı',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _kBorder),
            const SizedBox(height: 12),
            // Grid View
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text(
                            'Eşleşen ürün bulunamadı.',
                            style: TextStyle(
                                color: _kTextSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (scrollInfo) {
                        if (scrollInfo.metrics.pixels >=
                            scrollInfo.metrics.maxScrollExtent - 400) {
                          if (hasMore && !loadingMore) {
                            ref
                                .read(ordersProductsControllerProvider.notifier)
                                .loadNextPage();
                          }
                        }
                        return false;
                      },
                      child: GridView.builder(
                        controller: _productScrollController,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: filtered.length + (loadingMore ? 1 : 0),
                        itemBuilder: (context, idx) {
                          if (idx == filtered.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation(_kGreen),
                                ),
                              ),
                            );
                          }
                          final p = filtered[idx];
                        final existingKey = _cart.keys.firstWhere(
                          (item) => item.id == p.id,
                          orElse: () => p,
                        );
                        final qtyInCart = _cart[existingKey] ?? 0;
                        final outOfStock = p.quantity <= 0;
                        final isLowStock = p.quantity <= p.minStock;
                        final Color badgeBgColor = outOfStock
                            ? _kRedLight
                            : (isLowStock ? _kAmberLight : _kGreenLight);
                        final Color badgeTextColor = outOfStock
                            ? _kRed
                            : (isLowStock
                                ? const Color(0xFF854D0E)
                                : _kGreenDark);
                        final Color borderColor = qtyInCart > 0
                            ? _kGreen
                            : (outOfStock
                                ? _kRed.withValues(alpha: 0.25)
                                : (isLowStock
                                    ? _kAmber.withValues(alpha: 0.35)
                                    : _kBorder));

                        return AnimatedOpacity(
                          opacity: outOfStock ? 0.85 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: borderColor,
                                width: qtyInCart > 0
                                    ? 2.0
                                    : ((outOfStock || isLowStock)
                                        ? 1.5
                                        : 1.0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: qtyInCart > 0
                                      ? _kGreen.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () => _handleProductTap(
                                    p, existingKey, qtyInCart),
                                borderRadius: BorderRadius.circular(14),
                                splashColor: _kGreenLight,
                                highlightColor:
                                    _kGreenLight.withValues(alpha: 0.5),
                                child: Padding(
                                  padding: const EdgeInsets.all(11),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.category.toUpperCase(),
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
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 3),
                                            decoration: BoxDecoration(
                                              color: badgeBgColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              outOfStock
                                                  ? 'Tükendi'
                                                  : (isLowStock
                                                      ? '${p.quantity} adet'
                                                      : '${p.quantity}'),
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: badgeTextColor,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        p.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                          color: _kText,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            '₺${p.price.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              color: _kText,
                                            ),
                                          ),
                                          if (qtyInCart > 0)
                                            GestureDetector(
                                              onTap: () {},
                                              child: Container(
                                                height: 30,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color: _kGreen,
                                                      width: 1.5),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    GestureDetector(
                                                      onTap: () =>
                                                          updateState(() {
                                                        if (qtyInCart - 1.0 <=
                                                            0.0001) {
                                                          _cart.remove(p);
                                                        } else {
                                                          _cart[p] =
                                                              qtyInCart - 1.0;
                                                        }
                                                      }),
                                                      child: const Padding(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                horizontal: 6),
                                                        child: Icon(
                                                            Icons
                                                                .remove_rounded,
                                                            color: _kRed,
                                                            size: 14),
                                                      ),
                                                    ),
                                                    _InlineQuantityField(
                                                      quantity: qtyInCart,
                                                      hasBorder: false,
                                                      onChanged: (val) =>
                                                          updateState(() {
                                                        if (val <= 0.0001) {
                                                          _cart.remove(p);
                                                        } else {
                                                          _cart[p] = val;
                                                        }
                                                      }),
                                                      onRemove: () =>
                                                          updateState(() =>
                                                              _cart.remove(p)),
                                                    ),
                                                    GestureDetector(
                                                      onTap: () =>
                                                          updateState(() =>
                                                              _cart[p] =
                                                                  qtyInCart +
                                                                      1.0),
                                                      child: const Padding(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                horizontal: 6),
                                                        child: Icon(
                                                            Icons.add_rounded,
                                                            color: _kGreen,
                                                            size: 14),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          else
                                            Container(
                                              width: 30,
                                              height: 30,
                                              decoration: BoxDecoration(
                                                color: _kGreenLight,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.add_rounded,
                                                size: 18,
                                                color: _kGreenDark,
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
                      },
                    ),
                  ),
              ),
            ],
          );

        return Padding(
          padding: const EdgeInsets.all(16),
          child: catalogWidget,
        );
  }

  Future<void> _showOrderProductFilters(List<String> categoriesList) async {
    final currentCat = ref.read(ordersProductCategoryFilterProvider);
    final currentSort = ref.read(ordersProductSortProvider);
    final currentStock = ref.read(ordersProductStockFilterProvider);

    await ProductFilterSortDialog.show(
      context: context,
      initialCategory: currentCat,
      initialSort: currentSort,
      initialStock: currentStock,
      categories: categoriesList,
      onApply: ({required category, required sortBy, required stockFilter}) {
        ref.read(ordersProductCategoryFilterProvider.notifier).state = category;
        ref.read(ordersProductSortProvider.notifier).state = sortBy;
        ref.read(ordersProductStockFilterProvider.notifier).state = stockFilter;
      },
    );
  }

  Future<void> _handleProductTap(
      ProductEntity p, ProductEntity existingKey, double qtyInCart) async {
    if (p.quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${p.name}" stokta bulunmamaktadır (Stok: ${p.quantity}).'),
          backgroundColor: _kRed,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (p.isWeighed) {
      final selectedKg =
          await _showWeightInputDialog(p, currentWeightKg: qtyInCart);
      if (selectedKg != null && selectedKg > 0) {
        updateState(() => _cart[existingKey] = selectedKg);
      }
    } else {
      updateState(() => _cart[existingKey] = qtyInCart + 1.0);
    }
  }

  Future<double?> _showWeightInputDialog(ProductEntity product,
      {double currentWeightKg = 0.0}) {
    final initialKg = currentWeightKg > 0 ? currentWeightKg : 0.5;
    final controller =
        TextEditingController(text: _formatQuantity(initialKg));
    double selectedKg = initialKg;

    return showDialog<double>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final lineTotal = product.price * selectedKg;

            void updateKg(double newKg) {
              setDlgState(() {
                selectedKg = newKg;
                controller.text = _formatQuantity(newKg);
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kGreenLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.scale_rounded,
                        color: _kGreenDark, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _kText),
                        ),
                        Text(
                          '₺${product.price.toStringAsFixed(2)} / kg',
                          style: const TextStyle(
                              fontSize: 12, color: _kTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {'label': '250 gr', 'kg': 0.25},
                        {'label': '500 gr', 'kg': 0.5},
                        {'label': '750 gr', 'kg': 0.75},
                        {'label': '1 kg', 'kg': 1.0},
                        {'label': '1.5 kg', 'kg': 1.5},
                        {'label': '2 kg', 'kg': 2.0},
                      ].map((preset) {
                        final kg = preset['kg'] as double;
                        final isSel = (selectedKg - kg).abs() < 0.001;
                        return ChoiceChip(
                          label: Text(preset['label'] as String),
                          selected: isSel,
                          selectedColor: _kGreenLight,
                          labelStyle: TextStyle(
                            color: isSel ? _kGreenDark : _kText,
                            fontWeight: isSel
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (_) => updateKg(kg),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _kText),
                      decoration: InputDecoration(
                        labelText: 'Miktar (Kilogram)',
                        suffixText: 'kg',
                        suffixStyle: const TextStyle(
                            fontWeight: FontWeight.bold, color: _kGreenDark),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*[.,]?\d*')),
                      ],
                      onChanged: (val) {
                        final parsed =
                            double.tryParse(val.replaceAll(',', '.'));
                        if (parsed != null && parsed >= 0) {
                          setDlgState(() => selectedKg = parsed);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Kalem Tutarı:',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _kTextSecondary),
                          ),
                          Text(
                            '₺${lineTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _kGreenDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('İptal'),
                ),
                ElevatedButton.icon(
                  onPressed: selectedKg > 0
                      ? () => Navigator.pop(ctx, selectedKg)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Sepete Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
