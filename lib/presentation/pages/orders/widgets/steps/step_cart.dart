part of '../order_creation_dialog.dart';

// Extracted Cart Step widget for OrderCreationDialog
extension OrderCreationCartStep on OrderCreationDialogState {
  Widget _buildCartStep() {
    if (_cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kBorder),
                ),
                child: const Icon(
                  Icons.remove_shopping_cart_rounded,
                  size: 36,
                  color: _kTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sepetiniz Boş',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Siparişe eklemek istediğiniz ürünleri seçmek için ürünler sekmesine gidin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _kTextSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => updateState(() => _activeStep = 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('Ürün Eklemeye Başla'),
              ),
            ],
          ),
        ),
      );
    }

    final totalQuantity = _cart.values.fold(0.0, (a, b) => a + b);

    final itemsListWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    size: 20, color: _kGreen),
                const SizedBox(width: 8),
                const Text(
                  'Sepetteki Ürünler',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _kText,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kGreenLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_cart.length} çeşit / ${totalQuantity % 1 == 0 ? totalQuantity.toInt() : totalQuantity.toStringAsFixed(1)} adet',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kGreenDark,
                    ),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sepeti Temizle'),
                    content: const Text(
                        'Sepetteki tüm ürünleri kaldırmak istediğinizden emin misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Vazgeç'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kRed,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          updateState(() => _cart.clear());
                        },
                        child: const Text('Sepeti Boşalt'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete_sweep_rounded,
                  size: 16, color: _kRed),
              label: const Text('Sepeti Boşalt',
                  style: TextStyle(fontSize: 12, color: _kRed)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._cart.entries.map((entry) {
          final product = entry.key;
          final quantity = entry.value;
          final lineTotal = product.price * quantity;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              product.category.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _kTextSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₺${product.price.toStringAsFixed(2)} / adet',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _kTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Stepper Controls
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_rounded, size: 16),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 30, minHeight: 30),
                        color: _kTextSecondary,
                        onPressed: () {
                          updateState(() {
                            if (quantity > 1) {
                              _cart[product] = quantity - 1;
                            } else {
                              _cart.remove(product);
                            }
                          });
                        },
                      ),
                      _InlineQuantityField(
                        quantity: quantity,
                        hasBorder: false,
                        onChanged: (newQty) {
                          updateState(() {
                            if (newQty <= 0) {
                              _cart.remove(product);
                            } else {
                              _cart[product] = newQty;
                            }
                          });
                        },
                        onRemove: () =>
                            updateState(() => _cart.remove(product)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 16),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 30, minHeight: 30),
                        color: _kGreen,
                        onPressed: () {
                          updateState(() => _cart[product] = quantity + 1);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Line Total
                SizedBox(
                  width: 80,
                  child: Text(
                    '₺${lineTotal.toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Remove Button
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: _kRed),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Ürünü Çıkar',
                  onPressed: () {
                    updateState(() => _cart.remove(product));
                  },
                ),
              ],
            ),
          );
        }),
      ],
    );

    final detailsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Müşteri Bilgi Kartı
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_pin_rounded, size: 24, color: _kGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedCustomer?.name ?? 'Genel Müşteri',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                    if (_selectedCustomer?.phone != null &&
                        _selectedCustomer!.phone.isNotEmpty)
                      Text(
                        'Tel: ${_selectedCustomer!.phone}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => updateState(() => _activeStep = 0),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('Değiştir', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Teslimat Tarihi Seçimi
        InkWell(
          onTap: _pickDeliveryDate,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 20, color: _kGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Teslimat Tarihi',
                        style: TextStyle(
                          fontSize: 10,
                          color: _kTextSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        DateFormat('dd.MM.yyyy').format(_expectedDelivery),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _kText,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kGreenLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Değiştir',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kGreenDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Sipariş Notu
        TextField(
          controller: _notesController,
          maxLines: 3,
          style: const TextStyle(fontSize: 12, color: _kText),
          decoration: InputDecoration(
            labelText: 'Sipariş Notu',
            labelStyle: const TextStyle(fontSize: 12, color: _kTextSecondary),
            hintText: 'Sipariş veya teslimat ile ilgili notlar...',
            hintStyle: const TextStyle(fontSize: 11, color: _kTextSecondary),
            prefixIcon: const Icon(Icons.edit_note_rounded,
                size: 22, color: _kTextSecondary),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kGreen, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 14),

        // Tutar Özeti Kartı
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kGreenLight.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Çeşit Sayısı',
                      style: TextStyle(fontSize: 12, color: _kTextSecondary)),
                  Text('${_cart.length}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _kText)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Toplam Miktar',
                      style: TextStyle(fontSize: 12, color: _kTextSecondary)),
                  Text(
                    '${totalQuantity % 1 == 0 ? totalQuantity.toInt() : totalQuantity.toStringAsFixed(1)} adet',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kText),
                  ),
                ],
              ),
              const Divider(height: 16, thickness: 0.5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOPLAM TUTAR',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kGreenDark,
                    ),
                  ),
                  Text(
                    '₺${_totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _kGreenDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 720;

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(child: itemsListWidget),
                ),
                const VerticalDivider(width: 28, color: _kBorder),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(child: detailsColumn),
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
                itemsListWidget,
                const Divider(height: 28, color: _kBorder),
                detailsColumn,
              ],
            ),
          );
        }
      },
    );
  }
}
