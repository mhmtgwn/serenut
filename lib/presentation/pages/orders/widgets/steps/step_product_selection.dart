part of '../order_creation_dialog.dart';

// Extracted Product Selection Step widgets for OrderCreationDialog
extension OrderCreationProductStep on OrderCreationDialogState {
  Widget _buildProductStep() {
    final productsVal = ref.watch(ordersProductsControllerProvider);
    final categories = ref.watch(productCategoriesProvider);

    return productsVal.when(
      loading: () => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kGreen))),
      error: (err, _) => Center(child: Text('Ürünler yüklenemedi: $err', style: const TextStyle(color: _kRed))),
      data: (productsList) {
        final filtered = productsList;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
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
                            decoration: const InputDecoration(
                              hintText: 'Ürün ara...',
                              hintStyle: TextStyle(color: _kTextSecondary, fontSize: 13),
                              prefixIcon: Icon(Icons.search_rounded, color: _kTextSecondary, size: 18),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                            ),
                            style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
                            onChanged: (val) {
                              updateState(() => _productQuery = val);
                              ref.read(ordersProductSearchQueryProvider.notifier).state = val;
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: _kRed),
                        onPressed: () {
                          updateState(() {
                            _isProductSearching = false;
                            _productQuery = '';
                            _productSearchController.clear();
                          });
                          ref.read(ordersProductSearchQueryProvider.notifier).state = '';
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
                          onTap: () => _showCategoryBottomSheet(context, categories),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9), // Slate 100
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.filter_list_rounded, size: 16, color: _kGreenDark),
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
                                const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _kTextSecondary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
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
                      icon: const Icon(Icons.photo_camera_rounded, color: _kGreen),
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
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text(
                              'Eşleşen ürün bulunamadı.',
                              style: TextStyle(color: _kTextSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: _productScrollController,
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final p = filtered[idx];
                          final qtyInCart = _cart[p] ?? 0;
                          final outOfStock = p.quantity <= 0;
                          final isLowStock = p.quantity <= 5;
                          final Color badgeBgColor = outOfStock
                              ? _kRedLight
                              : (isLowStock ? _kAmberLight : _kGreenLight);
                          final Color badgeTextColor = outOfStock
                              ? _kRed
                              : (isLowStock ? const Color(0xFF854D0E) : _kGreenDark);
                          final Color borderColor = qtyInCart > 0
                              ? _kGreen
                              : (outOfStock
                                  ? _kRed.withValues(alpha: 0.25)
                                  : (isLowStock ? _kAmber.withValues(alpha: 0.35) : _kBorder));

                          return AnimatedOpacity(
                            opacity: outOfStock ? 0.85 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: borderColor,
                                  width: qtyInCart > 0 ? 2.0 : ((outOfStock || isLowStock) ? 1.5 : 1.0),
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
                                  onTap: () => updateState(() => _cart[p] = qtyInCart + 1.0),
                                  borderRadius: BorderRadius.circular(14),
                                  splashColor: _kGreenLight,
                                  highlightColor: _kGreenLight.withValues(alpha: 0.5),
                                  child: Padding(
                                    padding: const EdgeInsets.all(11),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: badgeBgColor,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                outOfStock
                                                    ? 'Tükendi'
                                                    : (isLowStock ? '${p.quantity} adet' : '${p.quantity}'),
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
                                            fontSize: 14,
                                            color: _kText,
                                            height: 1.25,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '₺${p.price % 1 == 0 ? p.price.toInt() : p.price.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15,
                                                  color: _kGreenDark,
                                                  letterSpacing: -0.3,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            qtyInCart == 0
                                                ? Container(
                                                    width: 32,
                                                    height: 32,
                                                    decoration: BoxDecoration(
                                                      color: _kGreen,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: const Icon(
                                                      Icons.add_rounded,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                  )
                                                : GestureDetector(
                                                    onTap: () {}, // Swallows taps on the controller container to prevent card onTap trigger
                                                    child: Container(
                                                      height: 32,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: _kGreen, width: 1.5),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          GestureDetector(
                                                            onTap: () => updateState(() {
                                                              if (qtyInCart - 1.0 <= 0.0001) {
                                                                _cart.remove(p);
                                                              } else {
                                                                _cart[p] = qtyInCart - 1.0;
                                                              }
                                                            }),
                                                            child: const Padding(
                                                              padding: EdgeInsets.symmetric(horizontal: 6),
                                                              child: Icon(Icons.remove_rounded, color: _kRed, size: 14),
                                                            ),
                                                          ),
                                                          _InlineQuantityField(
                                                            quantity: qtyInCart,
                                                            hasBorder: false,
                                                            onChanged: (val) => updateState(() {
                                                              if (val <= 0.0001) {
                                                                _cart.remove(p);
                                                              } else {
                                                                _cart[p] = val;
                                                              }
                                                            }),
                                                            onRemove: () => updateState(() => _cart.remove(p)),
                                                          ),
                                                          GestureDetector(
                                                            onTap: () => updateState(() => _cart[p] = qtyInCart + 1.0),
                                                            child: const Padding(
                                                              padding: EdgeInsets.symmetric(horizontal: 6),
                                                              child: Icon(Icons.add_rounded, color: _kGreen, size: 14),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
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
          ),
        );
      },
    );
  }

  Widget _buildCategoryModalChip(
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
}
