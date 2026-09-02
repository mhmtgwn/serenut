part of '../order_creation_dialog.dart';

// Extracted Product Selection Step widgets for OrderCreationDialog
extension OrderCreationProductStep on OrderCreationDialogState {
  Widget _buildProductStep() {
    final productsVal = ref.watch(ordersProductsControllerProvider);
    final categories = ref.watch(productCategoriesProvider);
    final stockFilter = ref.watch(ordersProductStockFilterProvider);
    final sortBy = ref.watch(ordersProductSortProvider);

    return productsVal.when(
      loading: () => const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(_kGreen))),
      error: (err, _) => Center(
          child: Text('Ürünler yüklenemedi: $err',
              style: const TextStyle(color: _kRed))),
      data: (productsList) {
        final filtered = productsList;
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
                        onTap: () =>
                            _showCategoryBottomSheet(context, categories),
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
                                  _selectedCategory == 'Tümü'
                                      ? 'Kategori: Tümü'
                                      : 'Kategori: $_selectedCategory',
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
                    isLabelVisible: stockFilter != null || sortBy != null,
                    child: IconButton(
                      onPressed: _showOrderProductFilters,
                      icon: const Icon(Icons.tune_rounded, color: _kGreen),
                      tooltip: 'Ürün filtreleri',
                    ),
                  ),
                  // Photo Camera scanner
                  IconButton(
                    onPressed: () {
                      BarcodeScannerDialog.show(
                        context,
                        onBarcodeScanned: (code) {
                          _handleBarcodeSubmit(code, productsList);
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
                  : GridView.builder(
                      controller: _productScrollController,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
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
            ],
          );

        return Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: _cart.isNotEmpty ? 76 : 16,
              ),
              child: catalogWidget,
            ),
            if (_cart.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: _buildFloatingCartBar(),
              ),
          ],
        );
      },
    );
  }

  // ── Mobil / Dar Ekran Kayan Sepet Çubuğu ──────────────────────────────────────
  Widget _buildFloatingCartBar() {
    final hasNote = _notesController.text.trim().isNotEmpty;
    final totalQty = _cart.values.fold<double>(0, (sum, q) => sum + q);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        onTap: () => updateState(() => _activeStep = 2),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A), // Slate 900
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kGreen, width: 1.2),
          ),
          child: Row(
            children: [
              Badge(
                label: Text('${_cart.length}'),
                backgroundColor: _kGreen,
                child: const Icon(Icons.shopping_cart_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          '₺${_totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        if (hasNote) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _kGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Not var',
                                style: TextStyle(
                                    color: _kGreenLight, fontSize: 10)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${_formatQuantity(totalQty)} birim • Teslim: ${DateFormat('dd.MM.yyyy').format(_expectedDelivery)}',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => updateState(() => _activeStep = 2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Sepete Git',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Future<void> _showOrderProductFilters() async {
    var stock = ref.read(ordersProductStockFilterProvider);
    var sort = ref.read(ordersProductSortProvider);
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
                    label: const Text('Tümü'),
                    selected: stock == null,
                    onSelected: (_) => setSheetState(() => stock = null),
                  ),
                  ChoiceChip(
                    label: const Text('Stokta'),
                    selected: stock == 'in_stock',
                    onSelected: (_) => setSheetState(() => stock = 'in_stock'),
                  ),
                  ChoiceChip(
                    label: const Text('Kritik'),
                    selected: stock == 'critical',
                    onSelected: (_) => setSheetState(() => stock = 'critical'),
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
                      value: 'price_asc',
                      child: Text('Fiyat: düşükten yükseğe')),
                  DropdownMenuItem(
                      value: 'price_desc',
                      child: Text('Fiyat: yüksekten düşüğe')),
                ],
                onChanged: (value) => setSheetState(() => sort = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.read(ordersProductStockFilterProvider.notifier).state =
                      stock;
                  ref.read(ordersProductSortProvider.notifier).state = sort;
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

  void _showCategoryBottomSheet(
      BuildContext context, List<String> categoriesList) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  'Kategori Seçin',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ListTile(
                title: const Text('Tümü'),
                leading: Icon(
                  Icons.category_rounded,
                  color: _selectedCategory == 'Tümü' ? _kGreen : Colors.grey,
                ),
                onTap: () {
                  updateState(() {
                    _selectedCategory = 'Tümü';
                  });
                  Navigator.of(context).pop();
                },
              ),
              ...categoriesList.map((category) {
                final isSelected = _selectedCategory == category;
                return ListTile(
                  title: Text(category),
                  leading: Icon(
                    Icons.label_outline_rounded,
                    color: isSelected ? _kGreen : Colors.grey,
                  ),
                  onTap: () {
                    updateState(() {
                      _selectedCategory = category;
                    });
                    Navigator.of(context).pop();
                  },
                );
              }),
            ],
          ),
        );
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
