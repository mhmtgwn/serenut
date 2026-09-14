part of '../order_details_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Order Payment Dialog (Vadeli Sipariş İçin Tam veya Kısmi Tahsilat Alma)
// ─────────────────────────────────────────────────────────────────────────────

class _OrderPaymentDialog extends ConsumerStatefulWidget {
  final OrderEntity order;
  final FinancialTransactionEntity saleTx;
  final double totalPaid;

  const _OrderPaymentDialog({
    required this.order,
    required this.saleTx,
    required this.totalPaid,
  });

  static Future<void> show(
    BuildContext context, {
    required OrderEntity order,
    required FinancialTransactionEntity saleTx,
    required double totalPaid,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16,
          vertical: isDesktop ? 24 : 16,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 520,
            maxHeight: 700,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _OrderPaymentDialog(
              order: order,
              saleTx: saleTx,
              totalPaid: totalPaid,
            ),
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<_OrderPaymentDialog> createState() =>
      _OrderPaymentDialogState();
}

class _OrderPaymentDialogState extends ConsumerState<_OrderPaymentDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _selectedMethod = 'cash'; // 'cash' | 'card'
  bool _isSubmitting = false;
  bool _printReceipt = true;

  double get _remainingDebt =>
      (widget.saleTx.amount - widget.totalPaid).clamp(0.0, double.infinity);

  double get _enteredAmount {
    final clean = _amountController.text.trim().replaceAll(',', '.');
    return double.tryParse(clean) ?? 0.0;
  }

  double get _newRemainingDebt =>
      (_remainingDebt - _enteredAmount).clamp(0.0, double.infinity);

  @override
  void initState() {
    super.initState();
    // Varsayılan olarak kalan borcun tamamını yaz
    _amountController.text = _remainingDebt.toStringAsFixed(2);
    _amountController.addListener(() => setState(() {}));

    final settings = ref.read(settingsNotifierProvider).valueOrNull;
    if (settings != null) {
      _printReceipt = settings.printReceipt;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    final amount = _enteredAmount;
    if (amount <= 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir ödeme tutarı girin.'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (amount > _remainingDebt + 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Girilen tutar kalan borçtan (₺${_remainingDebt.toStringAsFixed(2)}) fazla olamaz.'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    AuthorizedCardPayment? cardPayment;
    try {
      final paymentService = await ref.read(paymentServiceProvider.future);

      if (_selectedMethod == 'card') {
        final hasPos =
            ref.read(hardwareConfigProvider).valueOrNull?.hasPosBridge == true;
        if (hasPos) {
          cardPayment =
              await ref.read(physicalCardPaymentServiceProvider).authorize(
                    amount: amount,
                    idempotencyKey:
                        'order-pay-${widget.order.id}-${DateTime.now().millisecondsSinceEpoch}',
                  );
        }
      }

      final cardMetadata = _selectedMethod != 'card'
          ? null
          : cardPayment?.ledgerMetadata ??
              PhysicalCardPaymentService.manualLedgerMetadata(
                context: 'order_collection',
              );

      // 1. Ödemeyi finansal sisteme kaydet (Sipariş durumunu ASLA değiştirmez)
      await paymentService.recordPartialPayment(
        saleId: widget.order.id,
        customerId: widget.order.customerId,
        amount: amount,
        method: _selectedMethod,
        currentPaidAmount: widget.totalPaid,
        totalAmount: widget.saleTx.amount,
        terminalMetadata: cardMetadata,
      );

      if (cardPayment != null) {
        await ref.read(physicalCardPaymentServiceProvider).markLocalCommit(
              cardPayment,
              contextId: widget.order.id,
            );
      }

      // 2. Arayüzü ve sağlayıcıları anında güncelle
      ref.invalidate(_orderDetailProvider(widget.order.id));
      ref.invalidate(_orderPaymentInfoProvider(widget.order.id));
      ref.invalidate(ordersControllerProvider);
      ref.invalidate(customersControllerProvider);
      ref.invalidate(dashboardProvider);
      if (widget.order.customerId.isNotEmpty) {
        ref.invalidate(customerDetailProvider(widget.order.customerId));
        ref.invalidate(customerTransactionsProvider(widget.order.customerId));
      }

      // 3. Fiş yazdırma (isteğe bağlı)
      if (_printReceipt) {
        final settings = ref.read(settingsNotifierProvider).valueOrNull;
        if (settings != null) {
          unawaited(() async {
            try {
              CustomerEntity? customer;
              if (widget.order.customerId.isNotEmpty) {
                final custRepo =
                    await ref.read(customerRepositoryProvider.future);
                customer = await custRepo.findById(widget.order.customerId);
              }
              if (customer != null) {
                await ref
                    .read(printingApplicationServiceProvider)
                    .queueCollectionReceipt(
                      customer,
                      amount,
                      _selectedMethod,
                      'Sipariş #${widget.order.displayNumber} Tahsilatı',
                      settings,
                    );
              }
            } catch (e) {
              debugPrint('Receipt print error: $e');
            }
          }());
        }
      }

      if (mounted) {
        Navigator.pop(context);
        final remaining = _newRemainingDebt;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remaining <= 0.01
                  ? '₺${amount.toStringAsFixed(2)} tahsil edildi. Sipariş borcu tamamen kapandı.'
                  : '₺${amount.toStringAsFixed(2)} tahsil edildi. Kalan Borç: ₺${remaining.toStringAsFixed(2)}',
            ),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      unawaited(TelemetryService().logError(e, st, context: 'order_payment_dialog'));
      if (cardPayment != null) {
        await ref
            .read(physicalCardPaymentServiceProvider)
            .markUnreconciled(cardPayment, e);
      }
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tahsilat kaydedilemedi: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingDebt;
    final entered = _enteredAmount;
    final newRemaining = _newRemainingDebt;
    final isValid = entered > 0.01 && entered <= remaining + 0.01;

    final customerName = widget.order.customerName ?? 'Müşteri';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sipariş Tahsilatı Al',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
            Text(
              'Sipariş #${widget.order.displayNumber} • $customerName',
              style: const TextStyle(
                fontSize: 12,
                color: _kTextSecondary,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: _kText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _kText),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, color: _kBorder),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Borç Durumu Bilgi Kartı ──────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sipariş Toplamı',
                                style: TextStyle(
                                    fontSize: 12, color: _kTextSecondary)),
                            Text('₺${widget.saleTx.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _kText)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Şu Ana Kadar Ödenen',
                                style: TextStyle(
                                    fontSize: 12, color: _kTextSecondary)),
                            Text('₺${widget.totalPaid.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _kGreenDark)),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Kalan Sipariş Borcu',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _kRed),
                            ),
                            Text(
                              '₺${remaining.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: _kRed,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Alınacak Tutar Alanı ─────────────────────────────────
                  const Text(
                    'Tahsil Edilecek Tutar (₺)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d{0,2}')),
                    ],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _kGreenDark,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.payments_outlined,
                          color: _kGreenDark),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _amountController.clear(),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF0FDF4),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF86EFAC)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF86EFAC)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _kGreenDark, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Hızlı Tutar Butonları ─────────────────────────────────
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        label: Text('Tam Borcu Kapat (₺${remaining.toStringAsFixed(2)})'),
                        backgroundColor: _kGreenLight,
                        side: const BorderSide(color: _kGreen),
                        labelStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _kGreenDark),
                        onPressed: () {
                          _amountController.text =
                              remaining.toStringAsFixed(2);
                        },
                      ),
                      if (remaining > 50)
                        ActionChip(
                          label: const Text('50 ₺'),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide.none,
                          labelStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kText),
                          onPressed: () =>
                              _amountController.text = '50.00',
                        ),
                      if (remaining > 100)
                        ActionChip(
                          label: const Text('100 ₺'),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide.none,
                          labelStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kText),
                          onPressed: () =>
                              _amountController.text = '100.00',
                        ),
                      if (remaining > 200)
                        ActionChip(
                          label: const Text('200 ₺'),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide.none,
                          labelStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kText),
                          onPressed: () =>
                              _amountController.text = '200.00',
                        ),
                      if (remaining > 500)
                        ActionChip(
                          label: const Text('500 ₺'),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide.none,
                          labelStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kText),
                          onPressed: () =>
                              _amountController.text = '500.00',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Tahsilat Sonrası Kalan Canlı Önizleme ─────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: newRemaining <= 0.01
                          ? const Color(0xFFF0FDF4)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: newRemaining <= 0.01
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFFDE68A),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          newRemaining <= 0.01
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: newRemaining <= 0.01
                              ? _kGreenDark
                              : const Color(0xFFB45309),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            newRemaining <= 0.01
                                ? 'Bu tahsilat ile sipariş borcunun tamamı kapanacaktır.'
                                : 'Tahsilat sonrası siparişte kalan borç: ₺${newRemaining.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: newRemaining <= 0.01
                                  ? _kGreenDark
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Ödeme Yöntemi Seçimi ──────────────────────────────────
                  const Text(
                    'Ödeme Yöntemi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedMethod = 'cash'),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: _selectedMethod == 'cash'
                                  ? _kGreenLight
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedMethod == 'cash'
                                    ? _kGreen
                                    : _kBorder,
                                width: _selectedMethod == 'cash' ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.payments_rounded,
                                    size: 18,
                                    color: _selectedMethod == 'cash'
                                        ? _kGreenDark
                                        : _kTextSecondary),
                                const SizedBox(width: 6),
                                Text(
                                  'Nakit',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _selectedMethod == 'cash'
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: _selectedMethod == 'cash'
                                        ? _kGreenDark
                                        : _kText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedMethod = 'card'),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: _selectedMethod == 'card'
                                  ? const Color(0xFFDBEAFE)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedMethod == 'card'
                                    ? const Color(0xFF2563EB)
                                    : _kBorder,
                                width: _selectedMethod == 'card' ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.credit_card_rounded,
                                    size: 18,
                                    color: _selectedMethod == 'card'
                                        ? const Color(0xFF1D4ED8)
                                        : _kTextSecondary),
                                const SizedBox(width: 6),
                                Text(
                                  'Kredi Kartı',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _selectedMethod == 'card'
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: _selectedMethod == 'card'
                                        ? const Color(0xFF1D4ED8)
                                        : _kText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Fiş Yazdırma Ayarı ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _printReceipt
                              ? Icons.receipt_long_rounded
                              : Icons.receipt_long_outlined,
                          size: 18,
                          color: _printReceipt ? _kGreenDark : _kTextSecondary,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Tahsilat Bilgi Fişi Yazdır',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kText,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: _printReceipt,
                          activeColor: _kGreen,
                          onChanged: (val) =>
                              setState(() => _printReceipt = val),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Onay Butonu ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_isSubmitting || !isValid)
                      ? null
                      : _submitPayment,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    _isSubmitting
                        ? 'Tahsilat Kaydediliyor...'
                        : (entered > 0.01
                            ? '₺${entered.toStringAsFixed(2)} Ödemeyi Al ve Kaydet'
                            : 'Ödemeyi Kaydet'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
