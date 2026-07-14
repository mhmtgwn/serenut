part of '../order_creation_dialog.dart';

// Extracted Checkout Step widgets for OrderCreationDialog
extension OrderCreationCheckoutStep on OrderCreationDialogState {
  Widget _buildCheckoutStep() {
    final isKarma = _paymentMethod == 'karma';

    final leftSummaryColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ödeme Detayları',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: _kText),
        ),
        const SizedBox(height: 12),
        _buildSummaryRow(
          icon: Icons.person_outline_rounded,
          label: 'Müşteri',
          value: _selectedCustomer?.name ?? 'Seçilmedi',
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          icon: Icons.calendar_month_rounded,
          label: 'Teslimat Tarihi',
          value: DateFormat('dd.MM.yyyy').format(_expectedDelivery),
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          icon: Icons.shopping_basket_outlined,
          label: 'Toplam Ürün',
          value:
              _formatQuantity(_cart.values.fold(0.0, (sum, val) => sum + val)),
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          icon: Icons.money_rounded,
          label: 'Sipariş Tutarı',
          value: '₺${_totalAmount.toStringAsFixed(2)}',
          valueColor: _kGreenDark,
        ),
        const SizedBox(height: 16),
        const Divider(color: _kBorder),
        const SizedBox(height: 16),
        // Printer Receipt / Labels checkbox options
        Row(
          children: [
            Checkbox(
              value: _printReceipt,
              activeColor: _kGreen,
              onChanged: (val) {
                if (val != null) updateState(() => _printReceipt = val);
              },
            ),
            const Text(
              'Fiş Yazdır',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
            ),
            if (_printReceipt) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => updateState(() {
                  if (_printCopies > 1) _printCopies--;
                }),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      border: Border.all(color: _kBorder),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.remove,
                      size: 12, color: _kTextSecondary),
                ),
              ),
              const SizedBox(width: 6),
              _InlineCopyCountField(
                value: _printCopies,
                onChanged: (val) => updateState(() => _printCopies = val),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => updateState(() => _printCopies++),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      border: Border.all(color: _kBorder),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.add, size: 12, color: _kGreen),
                ),
              ),
              const SizedBox(width: 4),
              const Text('Kopya',
                  style: TextStyle(fontSize: 11, color: _kTextSecondary)),
            ],
          ],
        ),
        Row(
          children: [
            Checkbox(
              value: _printLabel,
              activeColor: _kGreen,
              onChanged: (val) {
                if (val != null) {
                  updateState(() => _printLabel = val);
                  _saveLabelPrinterSettings();
                }
              },
            ),
            const Text(
              'Sipariş Etiketi Yazdır',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
            ),
            if (_printLabel) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_labelCopies > 1) {
                    updateState(() => _labelCopies--);
                    _saveLabelPrinterSettings();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      border: Border.all(color: _kBorder),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.remove,
                      size: 12, color: _kTextSecondary),
                ),
              ),
              const SizedBox(width: 6),
              _InlineCopyCountField(
                value: _labelCopies,
                onChanged: (val) {
                  updateState(() => _labelCopies = val);
                  _saveLabelPrinterSettings();
                },
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  updateState(() => _labelCopies++);
                  _saveLabelPrinterSettings();
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      border: Border.all(color: _kBorder),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.add, size: 12, color: _kGreen),
                ),
              ),
              const SizedBox(width: 4),
              const Text('Kopya',
                  style: TextStyle(fontSize: 11, color: _kTextSecondary)),
            ],
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
    final methods = [
      {
        'id': 'cash',
        'label': 'Nakit',
        'icon': Icons.money_rounded,
        'color': _kGreen
      },
      {
        'id': 'card',
        'label': 'Kredi Kartı',
        'icon': Icons.credit_card_rounded,
        'color': Colors.blue
      },
      if (_selectedCustomer != null)
        {
          'id': 'debt',
          'label': 'Veresiye / Cari',
          'icon': Icons.people_outline_rounded,
          'color': _kRed
        },
      {
        'id': 'karma',
        'label': 'Karma Ödeme',
        'icon': Icons.account_balance_wallet_rounded,
        'color': _kAmberDark
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.2,
      ),
      itemCount: methods.length,
      itemBuilder: (context, idx) {
        final m = methods[idx];
        final id = m['id'] as String;
        final isSel = _paymentMethod == id;
        final color = m['color'] as Color;

        return GestureDetector(
          onTap: () {
            updateState(() {
              _paymentMethod = id;
              if (id == 'cash') {
                _paidAmount = _totalAmount;
              } else if (id == 'card') {
                _paidAmount = _totalAmount;
              } else if (id == 'debt') {
                _paidAmount = 0.0;
              } else if (id == 'karma') {
                _cashSplitController.text = _totalAmount.toStringAsFixed(2);
                _cardSplitController.text = '0.00';
                _debtSplitController.text = '0.00';
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSel ? color : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSel ? color : _kBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  m['icon'] as IconData,
                  color: isSel ? Colors.white : color,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  m['label'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isSel ? Colors.white : _kText,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
