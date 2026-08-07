part of '../order_creation_dialog.dart';

// Extracted Cart Summary Step widgets for OrderCreationDialog
extension OrderCreationCartSummaryStep on OrderCreationDialogState {
  Widget _buildCartStep() {
    if (_cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_basket_outlined,
                size: 72, color: Colors.grey[200]),
            const SizedBox(height: 16),
            const Text(
              'Sipariş sepetiniz boş.',
              style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final itemListWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sepetteki Ürünler',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: _kText),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: _cart.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 8, color: _kBorder),
              itemBuilder: (context, idx) {
                final p = _cart.keys.elementAt(idx);
                final qty = _cart[p]!;
                final lineTotal = p.price * qty;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _kText),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '₺${p.price.toStringAsFixed(2)} × ${_formatQuantity(qty)}',
                                  style: const TextStyle(
                                      color: _kTextSecondary, fontSize: 11),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₺${lineTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: _kGreenDark,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ürünü / Fiyatı Düzenle',
                        icon: const Icon(Icons.edit_note_rounded,
                            color: Colors.blue, size: 22),
                        onPressed: () => _showEditCartItemDialog(p, qty),
                      ),
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => updateState(() {
                                if (qty - 1.0 <= 0.0001) {
                                  _cart.remove(p);
                                } else {
                                  _cart[p] = qty - 1.0;
                                }
                              }),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.remove_rounded,
                                    color: _kRed, size: 16),
                              ),
                            ),
                            _InlineQuantityField(
                              quantity: qty,
                              hasBorder: false,
                              onChanged: (val) => updateState(() {
                                if (val <= 0.0001) {
                                  _cart.remove(p);
                                } else {
                                  _cart[p] = val;
                                }
                              }),
                              onRemove: () =>
                                  updateState(() => _cart.remove(p)),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  updateState(() => _cart[p] = qty + 1.0),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.add_rounded,
                                    color: _kGreen, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: _kRed, size: 20),
                        onPressed: () => updateState(() => _cart.remove(p)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );

    final formConfigWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Teslimat Tarihi ve Notlar',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        const Text('Tahmini Teslimat Tarihi',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: _kTextSecondary)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _expectedDelivery,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (date != null) updateState(() => _expectedDelivery = date);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: _kBorder),
              borderRadius: BorderRadius.circular(10),
              color: _kSurface,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('dd.MM.yyyy').format(_expectedDelivery),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Icon(Icons.calendar_month_rounded, color: _kGreen),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Sipariş Notu',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: _kTextSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Sipariş notları...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Sipariş Toplamı:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('₺${_totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: _kGreenDark)),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: itemListWidget),
                ),
                const VerticalDivider(width: 24, color: _kBorder),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(child: formConfigWidget),
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                itemListWidget,
                const Divider(height: 32, color: _kBorder),
                formConfigWidget,
              ],
            ),
          );
        }
      },
    );
  }

  void _showEditCartItemDialog(ProductEntity product, double currentQty) {
    final priceController =
        TextEditingController(text: product.price.toStringAsFixed(2));
    final qtyController =
        TextEditingController(text: _formatQuantity(currentQty));

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(product.name,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Birim Fiyat (₺)',
                  prefixText: '₺ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Miktar',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final newPrice =
                    double.tryParse(priceController.text.replaceAll(',', '.')) ??
                        product.price;
                final newQty =
                    double.tryParse(qtyController.text.replaceAll(',', '.')) ??
                        currentQty;

                updateState(() {
                  _cart.remove(product);
                  if (newQty > 0.0001) {
                    final updatedProduct = product.copyWith(price: newPrice);
                    _cart[updatedProduct] = newQty;
                  }
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
              child:
                  const Text('Kaydet', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
