// lib/presentation/widgets/discount_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serenutos/config/theme.dart';

class DiscountDialog extends StatefulWidget {
  final double subtotal;
  final double currentDiscount;
  final void Function(double discountAmount) onApply;

  const DiscountDialog({
    super.key,
    required this.subtotal,
    required this.currentDiscount,
    required this.onApply,
  });

  static Future<void> show({
    required BuildContext context,
    required double subtotal,
    required double currentDiscount,
    required void Function(double discountAmount) onApply,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DiscountDialog(
        subtotal: subtotal,
        currentDiscount: currentDiscount,
        onApply: onApply,
      ),
    );
  }

  @override
  State<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<DiscountDialog> {
  bool _isPercentage = false;
  late TextEditingController _controller;
  double _calculatedDiscount = 0.0;

  @override
  void initState() {
    super.initState();
    _calculatedDiscount = widget.currentDiscount.clamp(0.0, widget.subtotal);
    if (widget.currentDiscount > 0) {
      _controller = TextEditingController(
        text: widget.currentDiscount.toStringAsFixed(2).replaceAll('.00', ''),
      );
    } else {
      _controller = TextEditingController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onValueChanged(String val) {
    final parsed = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    setState(() {
      if (_isPercentage) {
        _calculatedDiscount =
            (widget.subtotal * (parsed / 100.0)).clamp(0.0, widget.subtotal);
      } else {
        _calculatedDiscount = parsed.clamp(0.0, widget.subtotal);
      }
    });
  }

  void _setPercentagePreset(double percent) {
    setState(() {
      _isPercentage = true;
      _controller.text = percent.toStringAsFixed(0);
      _calculatedDiscount =
          (widget.subtotal * (percent / 100.0)).clamp(0.0, widget.subtotal);
    });
  }

  @override
  Widget build(BuildContext context) {
    const greenDark = POSColors.greenDark;
    const greenLight = POSColors.greenLight;
    const border = Color(0xFFE2E8F0);
    const textSec = Color(0xFF64748B);

    final netTotal = (widget.subtotal - _calculatedDiscount).clamp(0.0, double.infinity);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: greenLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.discount_outlined,
                      color: greenDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'İskonto / İndirim',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: textSec),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Subtotal Display ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sepet Tutarı (Ara Toplam):',
                      style: TextStyle(fontSize: 13, color: textSec),
                    ),
                    Text(
                      '₺${widget.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Mode Toggle: ₺ vs % ──
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_isPercentage) {
                          setState(() {
                            _isPercentage = false;
                            _controller.text = _calculatedDiscount > 0
                                ? _calculatedDiscount.toStringAsFixed(2).replaceAll('.00', '')
                                : '';
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_isPercentage ? greenDark : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: !_isPercentage ? greenDark : border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '₺ Sabit Tutar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: !_isPercentage ? Colors.white : textSec,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (!_isPercentage) {
                          setState(() {
                            _isPercentage = true;
                            if (widget.subtotal > 0 && _calculatedDiscount > 0) {
                              final p = (_calculatedDiscount / widget.subtotal) * 100.0;
                              _controller.text = p.toStringAsFixed(0);
                            } else {
                              _controller.clear();
                            }
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _isPercentage ? greenDark : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isPercentage ? greenDark : border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '% Yüzde Oranı',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _isPercentage ? Colors.white : textSec,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Quick Preset Chips ──
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [5.0, 10.0, 15.0, 20.0, 25.0, 50.0].map((pct) {
                  return InkWell(
                    onTap: () => _setPercentagePreset(pct),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _isPercentage &&
                                _controller.text == pct.toStringAsFixed(0)
                            ? greenLight
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isPercentage &&
                                  _controller.text == pct.toStringAsFixed(0)
                              ? greenDark
                              : border,
                        ),
                      ),
                      child: Text(
                        '%${pct.toInt()}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isPercentage &&
                                  _controller.text == pct.toStringAsFixed(0)
                              ? greenDark
                              : textSec,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // ── Input Field ──
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d{0,2}')),
                ],
                onChanged: _onValueChanged,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: _isPercentage ? 'İndirim Yüzdesi' : 'İndirim Tutarı',
                  suffixText: _isPercentage ? '%' : '₺',
                  suffixStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: greenDark,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: greenDark, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              // ── Preview Calculation Card ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: greenLight.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: greenDark.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Uygulanan İndirim:',
                          style: TextStyle(fontSize: 12, color: textSec),
                        ),
                        Text(
                          '-₺${_calculatedDiscount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 10, thickness: 0.5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GENEL TOPLAM:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: greenDark,
                          ),
                        ),
                        Text(
                          '₺${netTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: greenDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Action Buttons ──
              Row(
                children: [
                  if (widget.currentDiscount > 0)
                    TextButton.icon(
                      onPressed: () {
                        widget.onApply(0.0);
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFDC2626)),
                      label: const Text(
                        'Kaldır',
                        style: TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Vazgeç', style: TextStyle(color: textSec)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.onApply(_calculatedDiscount);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: greenDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: const Text(
                      'Uygula',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
