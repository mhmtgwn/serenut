part of '../order_creation_dialog.dart';

// Extracted Checkout Step widgets for OrderCreationDialog
extension OrderCreationCheckoutStep on OrderCreationDialogState {
  Widget _buildCheckoutStep() {
    final isKarma = _paymentMethod == 'karma';
    final totalQty = _cart.values.fold(0.0, (a, b) => a + b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Compact Order & Customer Summary Banner ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kGreenLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      size: 22, color: _kGreenDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _selectedCustomer?.name ?? 'Genel Müşteri',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _kText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _kBorder),
                            ),
                            child: Text(
                              '${_cart.length} Çeşit (${totalQty % 1 == 0 ? totalQty.toInt() : totalQty.toStringAsFixed(1)} Adet)',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _kTextSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Teslimat: ${DateFormat('dd.MM.yyyy').format(_expectedDelivery)}',
                        style: const TextStyle(
                            fontSize: 11, color: _kTextSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Ödenecek Tutar',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _kTextSecondary),
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
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Sepeti Düzenle',
                  icon: const Icon(Icons.edit_outlined,
                      size: 20, color: _kGreen),
                  onPressed: () => updateState(() => _activeStep = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Payment Methods Selection ──
          const Text(
            'Ödeme Yöntemi Seçin',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _kText,
            ),
          ),
          const SizedBox(height: 12),
          _buildPaymentSelectionGrid(),

          if (isKarma) ...[
            const SizedBox(height: 18),
            _buildKarmaFields(),
          ],

          const SizedBox(height: 20),
          // ── Print Choices ──
          Row(
            children: [
              Expanded(
                child: _buildPrintChoice(
                  icon: Icons.receipt_long_rounded,
                  label: 'Fiş Yazdır',
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
              const SizedBox(width: 12),
              Expanded(
                child: _buildPrintChoice(
                  icon: Icons.label_rounded,
                  label: 'Sipariş Etiketi',
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
      ),
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



  void _showCashPaymentDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CashPaymentDialog(
        total: _totalAmount,
        onComplete: (double givenAmount) {
          Navigator.of(ctx).pop();
          updateState(() {
            _paymentMethod = 'cash';
            _givenCashController.text = givenAmount.toStringAsFixed(2);
          });
        },
      ),
    );
  }

  Widget _buildKarmaFields() {
    final remaining = _totalAmount;
    final hasCustomer = _selectedCustomer != null;

    return Container(
      key: _karmaFieldsKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _karmaValid ? _kGreen.withValues(alpha: 0.4) : _kBorder,
          width: _karmaValid ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split_rounded,
                  size: 16, color: _kTextSecondary),
              const SizedBox(width: 6),
              const Text(
                'Karma Ödeme Tutarları',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
              ),
              const Spacer(),
              if (_karmaValid)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kGreenLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('✓ Tutar Eşleşti',
                      style: TextStyle(
                          fontSize: 10,
                          color: _kGreenDark,
                          fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          KarmaPaymentSummaryBar(
            total: _totalAmount,
            paid: _karmaResult.paidAmount,
            remaining: _karmaRemainder,
            debt: _karmaDebt,
            change: _karmaResult.change,
            isValid: _karmaValid,
          ),
          const SizedBox(height: 12),
          _buildSplitField(
            controller: _cashSplitController,
            label: 'Alınan Nakit',
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
        ],
      ),
    );
  }

  void _onSplitFieldChanged(
      String field, String valStr, double remaining, bool hasCustomer) {
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
          width: 125,
          height: 36,
          child: TextField(
            controller: controller,
            enabled: isEnabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.end,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isEnabled ? _kText : Colors.grey),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: const OutlineInputBorder(),
              suffixIcon: isEnabled
                  ? IconButton(
                      icon: const Icon(Icons.download_rounded,
                          size: 14, color: Colors.grey),
                      tooltip: 'Kalan tutarı doldur',
                      onPressed: () {
                        final currentCash = fieldId == 'cash'
                            ? 0.0
                            : double.tryParse(_cashSplitController.text
                                    .replaceAll(',', '.')) ??
                                0.0;
                        final currentCard = fieldId == 'card'
                            ? 0.0
                            : double.tryParse(_cardSplitController.text
                                    .replaceAll(',', '.')) ??
                                0.0;
                        final currentDebt = fieldId == 'debt'
                            ? 0.0
                            : double.tryParse(_debtSplitController.text
                                    .replaceAll(',', '.')) ??
                                0.0;
                        final otherTotal =
                            currentCash + currentCard + currentDebt;
                        final rem = (remaining - otherTotal)
                            .clamp(0.0, double.infinity);
                        controller.text = rem > 0 ? rem.toStringAsFixed(2) : '';
                        updateState(() {});
                      },
                    )
                  : null,
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
          'label': 'Vadeli',
          'icon': Icons.account_balance_wallet_rounded,
          'color': _kOrange,
        },
      {
        'id': 'karma',
        'label': 'Karma Ödeme',
        'icon': Icons.call_split_rounded,
        'color': Colors.purple,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.8,
          children: methods.map((m) {
            final isSel = _paymentMethod == m['id'];
            final enabled = m['enabled'] as bool? ?? true;
            final color = m['color'] as Color;
            return GestureDetector(
              onTap: enabled
                  ? () {
                      if (m['id'] == 'cash') {
                        _showCashPaymentDialog();
                      } else {
                        updateState(() => _paymentMethod = m['id'] as String);
                      }
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isSel ? color : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSel
                        ? color
                        : (enabled
                            ? color.withValues(alpha: 0.4)
                            : Colors.grey.shade300),
                    width: isSel ? 2 : 1.5,
                  ),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                              color: color.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ]
                      : [],
                ),
                child: Opacity(
                  opacity: enabled ? 1.0 : 0.45,
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
            );
          }).toList(),
        );
      },
    );
  }
}
