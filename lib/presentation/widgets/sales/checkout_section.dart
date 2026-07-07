// lib/presentation/widgets/sales/checkout_section.dart
// Serenut POS — Ödeme & Checkout Paneli
// UX Redesign v3: KARMA split payment, 64px buttons, inline print status
// Preserved: all FSM calls, controller calls, provider reads

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:uuid/uuid.dart';

// ── POS Tema Renkleri (korundu) ───────────────────────────────────────────────
const _kGreen      = Color(0xFF16A34A);
const _kGreenDark  = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kBlue       = Color(0xFF2563EB);
const _kOrange     = Color(0xFFEA580C);
const _kOrangeLight= Color(0xFFFFEDD5);
const _kRed        = Color(0xFFDC2626);
const _kRedLight   = Color(0xFFFEE2E2);
const _kSurface    = Color(0xFFF8FAFC);
const _kText       = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder     = Color(0xFFE2E8F0);

class CheckoutSection extends ConsumerStatefulWidget {
  final double total;
  final CustomerEntity? selectedCustomer;
  final String paymentMethod;
  final double paidAmount;
  final TextEditingController paidController;
  final bool isSubmitting;
  final AsyncValue<List<CustomerEntity>> customersAsyncVal;
  final Function(CustomerEntity?) onCustomerChanged;
  final Function(String) onPaymentMethodChanged;
  final Function(double) onPaidAmountChanged;
  final VoidCallback onSubmitSale;
  final VoidCallback? onQuickCash;

  const CheckoutSection({
    super.key,
    required this.total,
    required this.selectedCustomer,
    required this.paymentMethod,
    required this.paidAmount,
    required this.paidController,
    required this.isSubmitting,
    required this.customersAsyncVal,
    required this.onCustomerChanged,
    required this.onPaymentMethodChanged,
    required this.onPaidAmountChanged,
    required this.onSubmitSale,
    this.onQuickCash,
  });

  @override
  ConsumerState<CheckoutSection> createState() => _CheckoutSectionState();
}

class _CheckoutSectionState extends ConsumerState<CheckoutSection> {
  // KARMA split payment controllers
  final TextEditingController _cashSplitController = TextEditingController();
  final TextEditingController _cardSplitController = TextEditingController();
  final TextEditingController _debtSplitController = TextEditingController();

  @override
  void dispose() {
    _cashSplitController.dispose();
    _cardSplitController.dispose();
    _debtSplitController.dispose();
    super.dispose();
  }

  double get _karmaCash => double.tryParse(_cashSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaCard => double.tryParse(_cardSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaDebt => widget.selectedCustomer != null
      ? (double.tryParse(_debtSplitController.text.replaceAll(',', '.')) ?? 0.0)
      : 0.0;

  double get _karmaTotal => _karmaCash + _karmaCard + _karmaDebt;
  double get _karmaRemainder => (widget.total - _karmaTotal).clamp(0.0, double.infinity);
  bool get _karmaValid => widget.total > 0 && (_karmaTotal - widget.total).abs() < 0.01;

  void _handlePayment(String method) {
    widget.onPaymentMethodChanged(method);
    if (method == 'cash' || method == 'card') {
      widget.onPaidAmountChanged(widget.total);
    } else if (method == 'debt') {
      if (widget.selectedCustomer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vadeli satış için müşteri seçilmesi zorunludur!'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      widget.onPaidAmountChanged(0.0);
    } else if (method == 'karma') {
      // Will be submitted via _handleKarmaSubmit
      return;
    }
    Future.microtask(() => widget.onSubmitSale());
  }

  void _handleKarmaSubmit() {
    if (!_karmaValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Toplam tutar eşleşmiyor. Kalan: ₺${_karmaRemainder.toStringAsFixed(2)}',
          ),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onPaidAmountChanged(_karmaCash + _karmaCard);
    Future.microtask(() => widget.onSubmitSale());
  }

  @override
  Widget build(BuildContext context) {
    final isKarma = widget.paymentMethod == 'karma';

    return Container(
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── MÜŞTERİ SELECTİON ──────────────────────────────────────────
            _buildCustomerSection(),
            const SizedBox(height: 12),

            // ── TOPLAM TUTAR BOX ────────────────────────────────────────────
            _buildTotalBox(),
            const SizedBox(height: 12),

            // ── KARMA SPLIT ALANLAR (yalnızca karma seçiliyken) ────────────
            if (isKarma) ...[
              _buildKarmaSplit(),
              const SizedBox(height: 12),
            ],

            // ── ÖDEME BUTONLARI ─────────────────────────────────────────────
            _buildPaymentButtons(isKarma),
          ],
        ),
      ),
    );
  }

  void _togglePrintReceipt(bool currentVal, dynamic settings) {
    ref.read(settingsNotifierProvider.notifier).updateSettings(
      settings.copyWith(printReceipt: !currentVal),
    );
  }

  Widget _buildPrintReceiptToggle() {
    final settingsAsync = ref.watch(settingsNotifierProvider);
    return settingsAsync.maybeWhen(
      data: (settings) {
        final isActive = settings.printReceipt;
        return IconButton(
          onPressed: () => _togglePrintReceipt(isActive, settings),
          icon: Icon(
            isActive ? Icons.print_rounded : Icons.print_disabled_rounded,
            color: isActive ? _kGreen : _kTextSecondary,
            size: 18,
          ),
          tooltip: isActive ? 'Otomatik Fiş Yazdırma Açık' : 'Otomatik Fiş Yazdırma Kapalı',
          style: IconButton.styleFrom(
            backgroundColor: isActive ? _kGreenLight : Colors.white,
            padding: const EdgeInsets.all(8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isActive ? _kGreen.withValues(alpha: 0.3) : _kBorder,
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  // ── Müşteri Bölümü ────────────────────────────────────────────────────────

  void _showCustomerSelection(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    if (isWide) {
      showDialog(
        context: context,
        builder: (context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: _CustomerSelectionSheet(
              initialSelected: widget.selectedCustomer,
              onCustomerChanged: widget.onCustomerChanged,
              isDialog: true,
            ),
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return _CustomerSelectionSheet(
            initialSelected: widget.selectedCustomer,
            onCustomerChanged: widget.onCustomerChanged,
            isDialog: false,
          );
        },
      );
    }
  }

  Widget _buildCustomerSection() {
    final cust = widget.selectedCustomer;
    if (cust == null) {
      return Row(
        children: [
          _buildPrintReceiptToggle(),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _showCustomerSelection(context),
            icon: const Icon(Icons.person_add_rounded, color: _kGreen, size: 20),
            tooltip: 'Müşteri Seç veya Ekle',
            style: IconButton.styleFrom(
              backgroundColor: _kGreenLight,
              padding: const EdgeInsets.all(8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _showCustomerSelection(context),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: cust.balance < 0 ? _kRedLight : _kGreenLight,
                  child: Text(
                    cust.name.isNotEmpty ? cust.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cust.balance < 0 ? _kRed : _kGreenDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cust.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (cust.phone.isNotEmpty)
                        Text(
                          cust.phone,
                          style: const TextStyle(color: _kTextSecondary, fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      cust.balance < 0
                          ? 'Geçmiş Borç'
                          : cust.balance > 0
                              ? 'Alacak'
                              : 'Borç Yok',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: cust.balance < 0
                            ? _kRed
                            : cust.balance > 0
                                ? _kGreenDark
                                : _kTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '₺${cust.balance.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cust.balance < 0
                            ? _kRed
                            : cust.balance > 0
                                ? _kGreenDark
                                : _kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPrintReceiptToggle(),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                widget.onCustomerChanged(null);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kRedLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Temizle',
                  style: TextStyle(fontSize: 11, color: _kRed, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Toplam Kutu ───────────────────────────────────────────────────────────

  Widget _buildTotalBox() {
    final isKarma = widget.paymentMethod == 'karma';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isKarma && _karmaTotal > 0)
            Text(
              'Kalan: ₺${_karmaRemainder.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                color: _karmaValid ? _kGreenDark : _kRed,
                fontWeight: FontWeight.w800,
              ),
            )
          else
            const SizedBox.shrink(),
          Text(
            '₺${widget.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              color: _kGreenDark,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── KARMA Split Alanlar ────────────────────────────────────────────────────

  Widget _buildKarmaSplit() {
    final remainderForCash = (widget.total - _karmaCard - _karmaDebt).clamp(0.0, double.infinity);
    final remainderForCard = (widget.total - _karmaCash - _karmaDebt).clamp(0.0, double.infinity);
    final remainderForDebt = (widget.total - _karmaCash - _karmaCard).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
              const Icon(Icons.call_split_rounded, size: 14, color: _kTextSecondary),
              const SizedBox(width: 6),
              const Text(
                'Karma Ödeme Dağılımı',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: _kText),
              ),
              const Spacer(),
              if (_karmaValid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kGreenLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('✓ Tamam',
                      style: TextStyle(
                          fontSize: 10, color: _kGreenDark, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _KarmaSplitField(
                  controller: _cashSplitController,
                  label: 'Nakit',
                  icon: Icons.payments_rounded,
                  color: _kGreen,
                  remainder: remainderForCash,
                  onSuffixTap: () => setState(() {
                    _cashSplitController.text = remainderForCash.toStringAsFixed(2);
                    widget.onPaidAmountChanged(_karmaCash + _karmaCard);
                  }),
                  onChanged: (_) => setState(() {
                    widget.onPaidAmountChanged(_karmaCash + _karmaCard);
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KarmaSplitField(
                  controller: _cardSplitController,
                  label: 'Kart',
                  icon: Icons.credit_card_rounded,
                  color: _kBlue,
                  remainder: remainderForCard,
                  onSuffixTap: () => setState(() {
                    _cardSplitController.text = remainderForCard.toStringAsFixed(2);
                    widget.onPaidAmountChanged(_karmaCash + _karmaCard);
                  }),
                  onChanged: (_) => setState(() {
                    widget.onPaidAmountChanged(_karmaCash + _karmaCard);
                  }),
                ),
              ),
              if (widget.selectedCustomer != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _KarmaSplitField(
                    controller: _debtSplitController,
                    label: 'Vadeli',
                    icon: Icons.account_balance_wallet_rounded,
                    color: _kOrange,
                    remainder: remainderForDebt,
                    onSuffixTap: () => setState(() {
                      _debtSplitController.text = remainderForDebt.toStringAsFixed(2);
                      widget.onPaidAmountChanged(_karmaCash + _karmaCard);
                    }),
                    onChanged: (_) => setState(() {
                      widget.onPaidAmountChanged(_karmaCash + _karmaCard);
                    }),
                  ),
                ),
              ],
            ],
          ),
          if (!_karmaValid && _karmaTotal > 0) ...[
            const SizedBox(height: 6),
            Text(
              _karmaTotal > widget.total
                  ? '₺${(_karmaTotal - widget.total).toStringAsFixed(2)} fazla girildi'
                  : '₺${_karmaRemainder.toStringAsFixed(2)} eksik',
              style: const TextStyle(color: _kRed, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  // ── Ödeme Butonları ────────────────────────────────────────────────────────

  Widget _buildPaymentButtons(bool isKarma) {
    final disabled = widget.isSubmitting || widget.total <= 0;
    final debtDisabled = disabled || widget.selectedCustomer == null;

    if (isKarma) {
      // KARMA modu: geniş tek "Onayla" butonu + "Geri Dön" seçeneği
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PayButton(
                  label: 'KARMA ÖNAYLA',
                  sublabel: widget.selectedCustomer != null
                      ? '₺${_karmaCash.toStringAsFixed(2)} N + ₺${_karmaCard.toStringAsFixed(2)} K + ₺${_karmaDebt.toStringAsFixed(2)} V'
                      : '₺${_karmaCash.toStringAsFixed(2)} N + ₺${_karmaCard.toStringAsFixed(2)} K',
                  icon: Icons.call_split_rounded,
                  color: _kGreen,
                  disabled: disabled || !_karmaValid,
                  height: 64,
                  onTap: _handleKarmaSubmit,
                ),
              ),
              const SizedBox(width: 8),
              _CancelKarmaButton(
                onTap: () {
                  setState(() {
                    _cashSplitController.clear();
                    _cardSplitController.clear();
                    _debtSplitController.clear();
                  });
                  widget.onPaymentMethodChanged('cash');
                },
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        // NAKİT
        Expanded(
          child: _PayButton(
            label: 'NAKİT',
            sublabel: '₺${widget.total.toStringAsFixed(2)}',
            icon: Icons.payments_rounded,
            color: _kGreen,
            disabled: disabled,
            height: 64,
            onTap: () => _handlePayment('cash'),
          ),
        ),
        const SizedBox(width: 6),

        // KART
        Expanded(
          child: _PayButton(
            label: 'KART',
            sublabel: '₺${widget.total.toStringAsFixed(2)}',
            icon: Icons.credit_card_rounded,
            color: _kBlue,
            disabled: disabled,
            height: 64,
            onTap: () => _handlePayment('card'),
          ),
        ),
        const SizedBox(width: 6),

        // VADELİ
        Expanded(
          child: _PayButton(
            label: 'VADELİ',
            sublabel: debtDisabled && !disabled ? 'Müşteri Seçin' : '₺${widget.total.toStringAsFixed(2)}',
            icon: Icons.account_balance_wallet_rounded,
            color: _kOrange,
            disabled: debtDisabled,
            height: 64,
            onTap: () => _handlePayment('debt'),
          ),
        ),
        const SizedBox(width: 6),

        // KARMA — küçük buton
        _KarmaToggleButton(
          disabled: disabled,
          onTap: () {
            setState(() {
              _cashSplitController.clear();
              _cardSplitController.clear();
              _debtSplitController.clear();
            });
            widget.onPaymentMethodChanged('karma');
          },
        ),
      ],
    );
  }
}

// ── Karma Split TextField ─────────────────────────────────────────────────────

class _KarmaSplitField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color color;
  final double remainder;
  final VoidCallback? onSuffixTap;
  final ValueChanged<String>? onChanged;

  const _KarmaSplitField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.color,
    required this.remainder,
    this.onSuffixTap,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showSuffix = remainder > 0.01;

    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
        prefixIcon: Icon(icon, color: color, size: 18),
        prefixText: '₺',
        prefixStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 0,
          minHeight: 0,
        ),
        suffixIcon: showSuffix
            ? Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: color.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onSuffixTap,
                  child: Text(
                    '+₺${remainder.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        filled: true,
        fillColor: color.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

// ── Ödeme Butonu ─────────────────────────────────────────────────────────────

class _PayButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final bool disabled;
  final double height;
  final VoidCallback onTap;

  const _PayButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.disabled,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = disabled ? _kSurface : color;
    final fg = disabled ? _kTextSecondary : Colors.white;

    return SizedBox(
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: disabled ? Border.all(color: _kBorder) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    color: disabled ? _kTextSecondary : fg.withValues(alpha: 0.8),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── KARMA Geçiş Butonu (küçük) ────────────────────────────────────────────────

class _KarmaToggleButton extends StatelessWidget {
  final bool disabled;
  final VoidCallback onTap;

  const _KarmaToggleButton({required this.disabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: 44,
      child: Material(
        color: disabled ? _kSurface : const Color(0xFF7C3AED).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: disabled
                    ? _kBorder
                    : const Color(0xFF7C3AED).withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.call_split_rounded,
                  size: 16,
                  color: disabled ? _kTextSecondary : const Color(0xFF7C3AED),
                ),
                const SizedBox(height: 2),
                Text(
                  'MIX',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: disabled ? _kTextSecondary : const Color(0xFF7C3AED),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── KARMA İptal Butonu ────────────────────────────────────────────────────────

class _CancelKarmaButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelKarmaButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: 44,
      child: Material(
        color: _kRedLight,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 18, color: _kRed),
              SizedBox(height: 2),
              Text(
                'İptal',
                style: TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w800, color: _kRed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── MÜŞTERİ SEÇİM BOTTOM SHEET ────────────────────────────────────────────────

class _CustomerSelectionSheet extends ConsumerStatefulWidget {
  final CustomerEntity? initialSelected;
  final Function(CustomerEntity?) onCustomerChanged;
  final bool isDialog;

  const _CustomerSelectionSheet({
    required this.initialSelected,
    required this.onCustomerChanged,
    required this.isDialog,
  });

  @override
  ConsumerState<_CustomerSelectionSheet> createState() => _CustomerSelectionSheetState();
}

class _CustomerSelectionSheetState extends ConsumerState<_CustomerSelectionSheet> {
  bool _isAdding = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // Add Customer Form Key & Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');

  bool _isSaving = false;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    if (widget.isDialog) {
      return Container(
        width: 450,
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isAdding ? _buildAddView() : _buildSelectionView(),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        maxWidth: 500,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isAdding ? _buildAddView() : _buildSelectionView(),
      ),
    );
  }

  Widget _buildSelectionView() {
    final customersAsync = ref.watch(customersControllerProvider);

    return Column(
      key: const ValueKey('selection_view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Müşteri Seç',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kText),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'İsim veya telefon ile ara...',
                    hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _kTextSecondary),
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
                    filled: true,
                    fillColor: _kSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => setState(() {
                _isAdding = true;
                _nameController.text = _searchQuery; 
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text(
                'Yeni',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Flexible(
          child: customersAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hata: $err', style: const TextStyle(color: _kRed, fontSize: 12)),
            ),
            data: (customersList) {
              final filtered = customersList.where((c) {
                final q = _searchQuery.toLowerCase();
                return c.name.toLowerCase().contains(q) || c.phone.contains(q);
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        const Text(
                          'Müşteri bulunamadı.',
                          style: TextStyle(color: _kTextSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _isAdding = true;
                            _nameController.text = _searchQuery;
                          }),
                          icon: const Icon(Icons.person_add_rounded, color: _kGreen),
                          label: Text(
                            '"$_searchQuery" Ekle',
                            style: const TextStyle(color: _kGreen, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, idx) {
                  final cust = filtered[idx];
                  final isDebt = cust.balance < 0;
                  final isSelected = widget.initialSelected?.id == cust.id;

                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected ? _kGreenLight.withValues(alpha: 0.5) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? _kGreen : _kBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected
                            ? _kGreen
                            : (isDebt ? _kRedLight : _kGreenLight),
                        child: Text(
                          cust.name.isNotEmpty ? cust.name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isDebt ? _kRed : _kGreenDark),
                          ),
                        ),
                      ),
                      title: Text(
                        cust.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isSelected ? _kGreenDark : _kText,
                        ),
                      ),
                      subtitle: Text(
                        cust.phone.isEmpty ? 'Telefon yok' : cust.phone,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₺${cust.balance.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              color: isDebt ? _kRed : _kGreenDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle_rounded, color: _kGreen, size: 18),
                          ],
                        ],
                      ),
                      onTap: () {
                        widget.onCustomerChanged(cust);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddView() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('add_view'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _isAdding = false),
              ),
              const Expanded(
                child: Text(
                  'Yeni Müşteri Ekle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Müşteri / Firma Adı *',
              hintText: 'Ad Soyad veya Firma Ünvanı',
              prefixIcon: const Icon(Icons.person_rounded, size: 18, color: _kTextSecondary),
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
                borderSide: const BorderSide(color: _kGreen, width: 2),
              ),
              filled: true,
              fillColor: _kSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Ad zorunludur' : null,
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\+\-]'))],
            decoration: InputDecoration(
              labelText: 'Telefon Numarası',
              hintText: 'Örn: 0500 000 0000',
              prefixIcon: const Icon(Icons.phone_rounded, size: 18, color: _kTextSecondary),
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
                borderSide: const BorderSide(color: _kGreen, width: 2),
              ),
              filled: true,
              fillColor: _kSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: _balanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\.\,\-]'))],
            decoration: InputDecoration(
              labelText: 'Başlangıç Bakiyesi (₺)',
              hintText: 'Negatif: Borçlu, Pozitif: Alacaklı',
              prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 18, color: _kTextSecondary),
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
                borderSide: const BorderSide(color: _kGreen, width: 2),
              ),
              filled: true,
              fillColor: _kSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Bakiye giriniz';
              if (double.tryParse(v.trim().replaceAll(',', '.')) == null) {
                return 'Geçerli bir sayı giriniz';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => setState(() => _isAdding = false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: const BorderSide(color: _kBorder),
                  ),
                  child: const Text(
                    'İptal',
                    style: TextStyle(color: _kTextSecondary, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Kaydet ve Seç',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveCustomer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    try {
      final newCust = CustomerEntity(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: '',
        balance: double.tryParse(_balanceController.text.trim().replaceAll(',', '.')) ?? 0.0,
        createdAt: DateTime.now(),
      );

      await ref.read(customersControllerProvider.notifier).addCustomer(newCust);
      ref.invalidate(dashboardProvider);
      widget.onCustomerChanged(newCust);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newCust.name} eklendi ve seçildi.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Müşteri eklenirken hata: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
