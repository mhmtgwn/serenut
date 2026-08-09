part of '../checkout_section.dart';

// ── Nakit Ödeme Dialog ─────────────────────────────────────────────────────────
// Sayısal klavye + para üstü hesaplama + Tam Tutar kısayol butonu

class _CashPaymentDialog extends StatefulWidget {
  final double total;
  final void Function(double givenAmount) onComplete;

  const _CashPaymentDialog({
    required this.total,
    required this.onComplete,
  });

  @override
  State<_CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<_CashPaymentDialog> {
  String _input = '';

  double get _given => double.tryParse(_input.replaceAll(',', '.')) ?? 0.0;
  double get _change => _given - widget.total;
  bool get _hasInput => _input.isNotEmpty;
  bool get _canComplete => !_hasInput || _change >= -0.001;

  void _append(String ch) {
    setState(() {
      // Ondalık nokta kontrolü
      if (ch == '.') {
        if (_input.isEmpty) {
          _input = '0.';
        } else if (!_input.contains('.')) {
          _input += '.';
        }
        return;
      }
      // Ondalık basamak sınırı (maks 2)
      if (_input.contains('.')) {
        final parts = _input.split('.');
        if (parts[1].length >= 2) return;
      }
      // Başta sıfır engeli
      if (_input == '0') {
        _input = ch;
        return;
      }
      _input += ch;
    });
  }

  void _backspace() {
    setState(() {
      if (_input.isNotEmpty) {
        _input = _input.substring(0, _input.length - 1);
      }
    });
  }

  void _clearAll() {
    setState(() => _input = '');
  }

  void _setExact() {
    setState(() {
      _input = widget.total.toStringAsFixed(2);
    });
  }

  void _submit() {
    final amount = _hasInput ? _given : widget.total;
    widget.onComplete(amount);
  }

  void _submitExact() {
    _setExact();
    // Kısa gecikme ile tutarı göster, sonra tamamla
    Future.delayed(const Duration(milliseconds: 250), _submit);
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final dialogWidth = sw >= 600 ? 360.0 : sw * 0.92;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogWidth,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: const BoxDecoration(
                color: _kGreenLight,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                        Icons.payments_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nakit Ödeme',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: _kText),
                      ),
                      Text(
                        'Tahsil edilecek: ₺${widget.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: _kGreenDark,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: _kTextSecondary),
                    style: IconButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.all(6),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                children: [
                  // Tutar Ekranı
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _hasInput
                            ? (_change >= 0 ? _kGreen : _kRed)
                                .withValues(alpha: 0.5)
                            : _kBorder,
                        width: _hasInput ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Tutar göstergesi
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Alınan',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _hasInput
                                      ? _kTextSecondary
                                      : _kTextSecondary,
                                  fontWeight: FontWeight.w500),
                            ),
                            Text(
                              _hasInput ? '₺$_input' : '₺0',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: _hasInput ? _kText : _kBorder,
                                letterSpacing: -1,
                              ),
                            ),
                          ],
                        ),
                        // Para üstü / eksik göstergesi
                        if (_hasInput) ...[
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color:
                                  _change >= 0 ? _kGreenLight : _kRedLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _change >= 0
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 12,
                                  color: _change >= 0 ? _kGreenDark : _kRed,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _change >= 0
                                      ? 'Para Üstü: ₺${_change.toStringAsFixed(2)}'
                                      : 'Eksik: ₺${(-_change).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _change >= 0 ? _kGreenDark : _kRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Türkiye TL Hızlı Tutar / Banknot Chipleri
                  _buildQuickCashChips(),

                  const SizedBox(height: 10),

                  // Sayısal Klavye
                  _buildNumpad(),

                  const SizedBox(height: 14),

                  // Aksiyon Butonları
                  Row(
                    children: [
                      // ── Tam Tutar Butonu ──────────────────────────────
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton(
                            onPressed: _submitExact,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kGreen,
                              side:
                                  const BorderSide(color: _kGreen, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Tam Tutar',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '₺${widget.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // ── Tamamla Butonu ────────────────────────────────
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _canComplete ? _submit : null,
                            icon: const Icon(Icons.check_circle_rounded,
                                size: 18),
                            label: const Text(
                              'Tamamla',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              disabledBackgroundColor: _kBorder,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: List.generate(row.length, (i) {
              final key = row[i];
              final isBack = key == '⌫';
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i > 0 ? 8 : 0),
                  child: SizedBox(
                    height: 52,
                    child: Material(
                      color: isBack ? _kRedLight : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: isBack ? _backspace : () => _append(key),
                        onLongPress:
                            isBack ? _clearAll : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isBack
                                  ? _kRed.withValues(alpha: 0.25)
                                  : _kBorder,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: isBack
                              ? const Icon(Icons.backspace_outlined,
                                  size: 20, color: _kRed)
                              : Text(
                                  key,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: _kText,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickCashChips() {
    final suggestions = _calculateQuickCashOptions(widget.total);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: suggestions.map((amount) {
          final formatted = amount % 1 == 0
              ? amount.toInt().toString()
              : amount.toStringAsFixed(2);
          final isSelected = _input == formatted;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () {
                setState(() {
                  _input = formatted;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? _kGreenLight : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? _kGreen : _kBorder,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '₺$formatted',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? _kGreenDark : _kText,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Kasa tutarına göre Türk Lirası banknot kombinasyonlarını (5, 10, 20, 50, 100, 200 TL)
  /// ve katlarını esas alarak toplamdan BÜYÜK akıllı hızlı ödeme tutarları üretir.
  /// Örn: 1235 TL kasa -> [₺1240, ₺1250, ₺1300, ₺1400 (7x200), ₺1500]
  List<double> _calculateQuickCashOptions(double total) {
    if (total <= 0) return [];
    final Set<double> set = {};

    // TL banknot ve yuvarlama adımları: 5, 10, 20, 50, 100, 200, 500
    const steps = [5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0];

    for (final step in steps) {
      double next = (total / step).ceil() * step;
      if ((next - total).abs() < 0.01) {
        next += step;
      }
      set.add(next);
    }

    final list = set.toList()..sort();
    return list.take(5).toList();
  }
}
