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


part 'checkout/karma_fields.dart';
part 'checkout/pay_buttons.dart';
part 'checkout/customer_selection.dart';

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

