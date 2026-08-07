part of '../order_creation_dialog.dart';

// Extracted Checkout Step widgets for OrderCreationDialog
extension OrderCreationCheckoutStep on OrderCreationDialogState {
  Widget _buildCheckoutStep() {
    final isKarma = _paymentMethod == 'karma';

    final leftSummaryColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sipariş Sepeti',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: _kText),
        ),
        const SizedBox(height: 10),
        ..._cart.entries.map((entry) {
          final product = entry.key;
          final quantity = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text(
                        '${_formatQuantity(quantity)} × ₺${product.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 10, color: _kTextSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₺${(product.price * quantity).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: _kText),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        _buildSummaryRow(
          icon: Icons.person_outline_rounded,
          label: _selectedCustomer?.name ?? 'Müşteri',
          value: 'Teslim ${DateFormat('dd.MM.yyyy').format(_expectedDelivery)}',
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          icon: Icons.payments_rounded,
          label: 'Toplam',
          value: '₺${_totalAmount.toStringAsFixed(2)}',
          valueColor: _kGreenDark,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPrintChoice(
                icon: Icons.receipt_long_rounded,
                label: 'Fiş',
                enabled: _printReceipt,
                copies: _printCopies,
                onToggle: () =>
                    updateState(() => _printReceipt = !_printReceipt),
                onMinus: _printCopies > 1
                    ? () => updateState(() => _printCopies--)
                    : null,
                onPlus: () => updateState(() => _printCopies++),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPrintChoice(
                icon: Icons.label_rounded,
                label: 'Etiket',
                enabled: _printLabel,
                copies: _labelCopies,
                onToggle: () {
                  updateState(() => _printLabel = !_printLabel);
                  _saveLabelPrinterSettings();
                },
                onMinus: _labelCopies > 1
                    ? () {
                        updateState(() => _labelCopies--);
                        _saveLabelPrinterSettings();
                      }
                    : null,
                onPlus: () {
                  updateState(() => _labelCopies++);
                  _saveLabelPrinterSettings();
                },
              ),
            ),
          ],
        ),
      ],
    );

    final rightPaymentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ödeme Yöntemi Seçin',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: _kText),
        ),
        const SizedBox(height: 12),
        _buildPaymentSelectionGrid(),
        if (isKarma) ...[
          const SizedBox(height: 16),
          _buildKarmaFields(),
        ],
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
                  child: SingleChildScrollView(child: leftSummaryColumn),
                ),
                const VerticalDivider(width: 24, color: _kBorder),
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: rightPaymentColumn),
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
                leftSummaryColumn,
                const Divider(height: 32, color: _kBorder),
                rightPaymentColumn,
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildPrintChoice({
    required IconData icon,
    required String label,
    required bool enabled,
    required int copies,
    required VoidCallback onToggle,
    required VoidCallback? onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: enabled ? _kGreenLight : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled ? _kGreen.withValues(alpha: .35) : _kBorder,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '$label yazdırmayı ${enabled ? 'kapat' : 'aç'}',
            visualDensity: VisualDensity.compact,
            onPressed: onToggle,
            icon: Icon(icon,
                size: 18, color: enabled ? _kGreenDark : _kTextSecondary),
          ),
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          if (enabled) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onMinus,
              icon: const Icon(Icons.remove_rounded, size: 15),
            ),
            Text('$copies',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onPlus,
              icon: const Icon(Icons.add_rounded, size: 15),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
      {required IconData icon,
      required String label,
      required String value,
      Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _kTextSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(color: _kTextSecondary, fontSize: 12)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: valueColor ?? _kText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKarmaFields() {
    final remaining = _totalAmount;
    final hasCustomer = _selectedCustomer != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Karma Ödeme Tutarları',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
          ),
          const SizedBox(height: 12),
          _buildSplitField(
            controller: _cashSplitController,
            label: 'Nakit Ödeme',
            icon: Icons.money_rounded,
            color: _kGreen,
            fieldId: 'cash',
            remaining: remaining,
            hasCustomer: hasCustomer,
          ),
          const SizedBox(height: 8),
          _buildSplitField(
            controller: _cardSplitController,
            label: 'Kredi Kartı',
            icon: Icons.credit_card_rounded,
            color: Colors.blue,
            fieldId: 'card',
            remaining: remaining,
            hasCustomer: hasCustomer,
          ),
          const SizedBox(height: 8),
          _buildSplitField(
            controller: _debtSplitController,
            label: 'Veresiye / Cari',
            icon: Icons.people_outline_rounded,
            color: _kRed,
            fieldId: 'debt',
            remaining: remaining,
            hasCustomer: hasCustomer,
            isEnabled: hasCustomer,
          ),
          const Divider(height: 24, color: _kBorder),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Dağıtılan Toplam:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              Text('₺${_karmaTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _karmaValid ? _kGreenDark : _kRed)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Kalan Tutar:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              Text('₺${_karmaRemainder.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _kText)),
            ],
          ),
        ],
      ),
    );
  }

  void _onSplitFieldChanged(
      String field, String valStr, double remaining, bool hasCustomer) {
    final val = double.tryParse(valStr.replaceAll(',', '.')) ?? 0.0;

    if (!hasCustomer) {
      _debtSplitController.text = '0.00';
      if (field == 'cash') {
        final cardVal = (remaining - val).clamp(0.0, remaining);
        _cardSplitController.text = cardVal.toStringAsFixed(2);
      } else if (field == 'card') {
        final cashVal = (remaining - val).clamp(0.0, remaining);
        _cashSplitController.text = cashVal.toStringAsFixed(2);
      }
    } else {
      if (field == 'cash') {
        final currentCard =
            double.tryParse(_cardSplitController.text.replaceAll(',', '.')) ??
                0.0;
        final debtVal = (remaining - (val + currentCard)).clamp(0.0, remaining);
        _debtSplitController.text = debtVal.toStringAsFixed(2);
      } else if (field == 'card') {
        final currentCash =
            double.tryParse(_cashSplitController.text.replaceAll(',', '.')) ??
                0.0;
        final debtVal = (remaining - (currentCash + val)).clamp(0.0, remaining);
        _debtSplitController.text = debtVal.toStringAsFixed(2);
      } else if (field == 'debt') {
        final currentCash =
            double.tryParse(_cashSplitController.text.replaceAll(',', '.')) ??
                0.0;
        final cardVal = (remaining - (currentCash + val)).clamp(0.0, remaining);
        _cardSplitController.text = cardVal.toStringAsFixed(2);
      }
    }
    updateState(() {});
  }

  Widget _buildSplitField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    required String fieldId,
    required double remaining,
    required bool hasCustomer,
    bool isEnabled = true,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isEnabled ? color : Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isEnabled ? _kText : Colors.grey)),
        ),
        SizedBox(
          width: 100,
          height: 32,
          child: TextField(
            controller: controller,
            enabled: isEnabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.end,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isEnabled ? _kText : Colors.grey),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
            ],
            onChanged: (val) =>
                _onSplitFieldChanged(fieldId, val, remaining, hasCustomer),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSelectionGrid() {
    final hasPos =
        ref.watch(hardwareConfigProvider).valueOrNull?.hasPosBridge == true;
    final methods = [
      {
        'id': 'cash',
        'label': 'Nakit',
        'icon': Icons.money_rounded,
        'color': _kGreen
      },
      {
        'id': 'card',
        'label': hasPos ? 'Kart' : 'POS yok',
        'icon': Icons.credit_card_rounded,
        'color': Colors.blue,
        'enabled': hasPos,
      },
      if (_selectedCustomer != null)
        {
          'id': 'debt',
          'label': 'Veresiye / Cari',
          'icon': Icons.people_outline_rounded,
          'color': _kRed,
          'enabled': true,
        },
      {
        'id': 'karma',
        'label': 'Karma Ödeme',
        'icon': Icons.account_balance_wallet_rounded,
        'color': _kAmberDark,
        'enabled': true,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? methods.length : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods.map((m) {
            final id = m['id'] as String;
            final isSel = _paymentMethod == id;
            final color = m['color'] as Color;
            final enabled = m['enabled'] as bool? ?? true;
            return SizedBox(
              width: width,
              height: 48,
              child: Material(
                color: isSel ? color : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSel ? color : _kBorder,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: !enabled
                      ? null
                      : () {
                          updateState(() {
                            _paymentMethod = id;
                            if (id == 'karma') {
                              _cashSplitController.text =
                                  _totalAmount.toStringAsFixed(2);
                              _cardSplitController.text = '0.00';
                              _debtSplitController.text = '0.00';
                            }
                          });
                        },
                  child: Opacity(
                    opacity: enabled ? 1 : .45,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            m['icon'] as IconData,
                            color: isSel ? Colors.white : color,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              m['label'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: isSel ? Colors.white : _kText,
                              ),
                            ),
                          ),
                        ],
                      ),
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
}
