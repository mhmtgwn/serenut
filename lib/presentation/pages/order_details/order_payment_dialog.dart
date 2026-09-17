part of '../order_details_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Order Payment Dialog (Vadeli Sipariş İçin Nakit, Kart veya Miks Ödeme Alma)
// Bu işlem sadece o sipariş özelinde ödemeyi günceller, teslimat durumunu bozmaz.
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
            maxWidth: 540,
            maxHeight: 740,
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
  // Tekli ödeme tutarı (Nakit veya Kart seçildiğinde)
  final _amountController = TextEditingController();

  // Miks ödeme tutarları
  final _karmaCashController = TextEditingController();
  final _karmaCardController = TextEditingController();

  // Seçili yöntem: 'cash' | 'card' | 'karma' (Miks)
  String _selectedMethod = 'cash';
  bool _isSubmitting = false;
  bool _printReceipt = true;

  double get _remainingDebt =>
      (widget.saleTx.amount - widget.totalPaid).clamp(0.0, double.infinity);

  double get _enteredAmount {
    final clean = _amountController.text.trim().replaceAll(',', '.');
    return double.tryParse(clean) ?? 0.0;
  }

  double get _karmaCash {
    final clean = _karmaCashController.text.trim().replaceAll(',', '.');
    return double.tryParse(clean) ?? 0.0;
  }

  double get _karmaCard {
    final clean = _karmaCardController.text.trim().replaceAll(',', '.');
    return double.tryParse(clean) ?? 0.0;
  }

  /// Aktif yönteme göre alınacak toplam ödeme miktarı
  double get _effectiveAmount {
    if (_selectedMethod == 'karma') {
      return _karmaCash + _karmaCard;
    }
    return _enteredAmount;
  }

  double get _newRemainingDebt =>
      (_remainingDebt - _effectiveAmount).clamp(0.0, double.infinity);

  bool get _isValid {
    final amt = _effectiveAmount;
    if (_selectedMethod == 'karma') {
      return amt > 0.01 &&
          amt <= _remainingDebt + 0.01 &&
          (_karmaCash > 0 || _karmaCard > 0);
    }
    return amt > 0.01 && amt <= _remainingDebt + 0.01;
  }

  @override
  void initState() {
    super.initState();
    // Varsayılan olarak kalan borcun tamamını yaz
    _amountController.text = _remainingDebt.toStringAsFixed(2);
    _amountController.addListener(() => setState(() {}));
    _karmaCashController.addListener(() => setState(() {}));
    _karmaCardController.addListener(() => setState(() {}));

    final settings = ref.read(settingsNotifierProvider).valueOrNull;
    if (settings != null) {
      _printReceipt = settings.printReceipt;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _karmaCashController.dispose();
    _karmaCardController.dispose();
    super.dispose();
  }

  void _onMethodChanged(String method) {
    setState(() {
      _selectedMethod = method;
      if (method == 'karma') {
        // Miks seçildiğinde eğer boşsa borcun yarısını nakit, yarısını kart yap veya kolaylaştır
        if (_karmaCashController.text.isEmpty &&
            _karmaCardController.text.isEmpty) {
          final half = (_remainingDebt / 2).roundToDouble();
          final otherHalf = _remainingDebt - half;
          _karmaCashController.text = half.toStringAsFixed(2);
          _karmaCardController.text = otherHalf.toStringAsFixed(2);
        }
      }
    });
  }

  Future<void> _submitPayment() async {
    final amount = _effectiveAmount;
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
              'Girilen tutar (₺${amount.toStringAsFixed(2)}) kalan borçtan (₺${_remainingDebt.toStringAsFixed(2)}) fazla olamaz.'),
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
      final cardAmount = _selectedMethod == 'card'
          ? amount
          : _selectedMethod == 'karma'
              ? _karmaCard
              : 0.0;

      if (cardAmount > 0) {
        final hasPos =
            ref.read(hardwareConfigProvider).valueOrNull?.hasPosBridge == true;
        if (hasPos) {
          cardPayment =
              await ref.read(physicalCardPaymentServiceProvider).authorize(
                    amount: cardAmount,
                    idempotencyKey:
                        'order-pay-${widget.order.id}-${DateTime.now().millisecondsSinceEpoch}',
                  );
        }
      }

      final cardMetadata = cardAmount <= 0
          ? null
          : cardPayment?.ledgerMetadata ??
              PhysicalCardPaymentService.manualLedgerMetadata(
                context: 'order_collection',
              );

      // 1. Ödemeyi finansal sisteme kaydet (Sipariş durumuna DOKUNMAZ)
      if (_selectedMethod == 'cash') {
        await paymentService.recordPartialPayment(
          saleId: widget.order.id,
          customerId: widget.order.customerId,
          amount: amount,
          method: 'cash',
          currentPaidAmount: widget.totalPaid,
          totalAmount: widget.saleTx.amount,
          terminalMetadata: null,
        );
      } else if (_selectedMethod == 'card') {
        await paymentService.recordPartialPayment(
          saleId: widget.order.id,
          customerId: widget.order.customerId,
          amount: amount,
          method: 'card',
          currentPaidAmount: widget.totalPaid,
          totalAmount: widget.saleTx.amount,
          terminalMetadata: cardMetadata,
        );
      } else if (_selectedMethod == 'karma') {
        double currentPaid = widget.totalPaid;
        final kCash = _karmaCash;
        final kCard = _karmaCard;

        if (kCash > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: kCash,
            method: 'cash',
            currentPaidAmount: currentPaid,
            totalAmount: widget.saleTx.amount,
            terminalMetadata: null,
          );
          currentPaid += kCash;
        }

        if (kCard > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: kCard,
            method: 'card',
            currentPaidAmount: currentPaid,
            totalAmount: widget.saleTx.amount,
            terminalMetadata: cardMetadata,
          );
        }
      }

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
        final settingsFuture = ref.read(settingsRepositoryProvider.future);
        var settings = ref.read(settingsNotifierProvider).valueOrNull ??
            ref.read(settingsNotifierProvider).value;
        unawaited(() async {
          try {
            var safeSettings = settings;
            if (safeSettings == null) {
              try {
                final repo = await settingsFuture;
                safeSettings = await repo.getSettings();
              } catch (_) {}
            }
            if (safeSettings == null) return;
            CustomerEntity? customer;
            if (widget.order.customerId.isNotEmpty) {
              final custRepo =
                  await ref.read(customerRepositoryProvider.future);
              customer = await custRepo.findById(widget.order.customerId);
            }
            final finalCustomer = customer ??
                CustomerEntity(
                  id: widget.order.customerId,
                  name: widget.order.customerName?.isNotEmpty == true
                      ? widget.order.customerName!
                      : 'Genel Müşteri',
                  email: '',
                  phone: widget.order.customerPhone ?? '',
                  balance: 0,
                  createdAt: DateTime.now(),
                );

            final receiptNote = _selectedMethod == 'karma'
                ? 'Sipariş #${widget.order.displayNumber} Miks Ödeme (Nakit: ₺${_karmaCash.toStringAsFixed(2)}, Kart: ₺${_karmaCard.toStringAsFixed(2)})'
                : 'Sipariş #${widget.order.displayNumber} Tahsilatı (${_selectedMethod == 'cash' ? 'Nakit' : 'Kredi Kartı'})';

            await ref
                .read(printingApplicationServiceProvider)
                .queueCollectionReceipt(
                  finalCustomer,
                  amount,
                  _selectedMethod,
                  receiptNote,
                  safeSettings,
                );
            } catch (e) {
              debugPrint('Receipt print error: $e');
            }
          }());
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
      unawaited(
          TelemetryService().logError(e, st, context: 'order_payment_dialog'));
      if (cardPayment != null) {
        await ref
            .read(physicalCardPaymentServiceProvider)
            .markUnreconciled(cardPayment, e);
      }
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ödeme kaydedilemedi: $e'),
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
    final effective = _effectiveAmount;
    final newRemaining = _newRemainingDebt;
    final isValid = _isValid;
    final isKarma = _selectedMethod == 'karma';

    final customerName = widget.order.customerName ?? 'Müşteri';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sipariş Ödemesini Güncelle',
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

                  // ── Ödeme Yöntemi Seçimi (Nakit, Kart, Miks) ───────────────
                  const Text(
                    'Ödeme Yöntemi Seçin',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // 1. Nakit
                      Expanded(
                        child: _buildMethodTab(
                          id: 'cash',
                          label: 'Nakit',
                          icon: Icons.payments_rounded,
                          activeColor: _kGreen,
                          activeBg: _kGreenLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 2. Kart
                      Expanded(
                        child: _buildMethodTab(
                          id: 'card',
                          label: 'Kredi Kartı',
                          icon: Icons.credit_card_rounded,
                          activeColor: const Color(0xFF2563EB),
                          activeBg: const Color(0xFFDBEAFE),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 3. Miks
                      Expanded(
                        child: _buildMethodTab(
                          id: 'karma',
                          label: 'Miks',
                          icon: Icons.call_split_rounded,
                          activeColor: Colors.purple,
                          activeBg: const Color(0xFFF3E8FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Tutar Girdi Alanları ──────────────────────────────────
                  if (!isKarma) ...[
                    // Tekli Tutar Girişi (Nakit veya Kart)
                    Text(
                      _selectedMethod == 'cash'
                          ? 'Alınacak Nakit Tutarı (₺)'
                          : 'Kart ile Çekilecek Tutar (₺)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*[\.,]?\d{0,2}')),
                      ],
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _kGreenDark,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          _selectedMethod == 'cash'
                              ? Icons.payments_outlined
                              : Icons.credit_card_rounded,
                          color: _selectedMethod == 'cash'
                              ? _kGreenDark
                              : const Color(0xFF2563EB),
                        ),
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
                          borderSide:
                              const BorderSide(color: Color(0xFF86EFAC)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFF86EFAC)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _kGreenDark, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Hızlı Tutar Butonları
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          label: Text(
                              'Tam Borcu Kapat (₺${remaining.toStringAsFixed(2)})'),
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
                            onPressed: () => _amountController.text = '50.00',
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
                            onPressed: () => _amountController.text = '100.00',
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
                            onPressed: () => _amountController.text = '200.00',
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
                            onPressed: () => _amountController.text = '500.00',
                          ),
                      ],
                    ),
                  ] else ...[
                    // Miks Tutar Girişi (Nakit + Kart)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF5FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE9D5FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.call_split_rounded,
                                  size: 16, color: Colors.purple),
                              SizedBox(width: 8),
                              Text(
                                'Miks Ödeme Dağılımı (Nakit + Kart)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // 1. Nakit Girişi
                          Row(
                            children: [
                              const Expanded(
                                flex: 4,
                                child: Text('💵 Nakit:',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _kText)),
                              ),
                              Expanded(
                                flex: 6,
                                child: TextFormField(
                                  controller: _karmaCashController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*[\.,]?\d{0,2}')),
                                  ],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: _kGreenDark,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // 2. Kart Girişi
                          Row(
                            children: [
                              const Expanded(
                                flex: 4,
                                child: Text('💳 Kredi Kartı:',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _kText)),
                              ),
                              Expanded(
                                flex: 6,
                                child: TextFormField(
                                  controller: _karmaCardController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*[\.,]?\d{0,2}')),
                                  ],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Hızlı Dengeleme Butonları
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                label: const Text('Eşit Böl (50 / 50)'),
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                    color: Color(0xFFD8B4FE)),
                                labelStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.purple),
                                onPressed: () {
                                  final half =
                                      (_remainingDebt / 2).roundToDouble();
                                  final otherHalf = _remainingDebt - half;
                                  _karmaCashController.text =
                                      half.toStringAsFixed(2);
                                  _karmaCardController.text =
                                      otherHalf.toStringAsFixed(2);
                                },
                              ),
                              ActionChip(
                                label: const Text('Kalanı Nakite Tamamla'),
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                    color: Color(0xFF86EFAC)),
                                labelStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _kGreenDark),
                                onPressed: () {
                                  final card = _karmaCard;
                                  final diff = (_remainingDebt - card)
                                      .clamp(0.0, double.infinity);
                                  _karmaCashController.text =
                                      diff.toStringAsFixed(2);
                                },
                              ),
                              ActionChip(
                                label: const Text('Kalanı Karta Tamamla'),
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                    color: Color(0xFF93C5FD)),
                                labelStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1D4ED8)),
                                onPressed: () {
                                  final cash = _karmaCash;
                                  final diff = (_remainingDebt - cash)
                                      .clamp(0.0, double.infinity);
                                  _karmaCardController.text =
                                      diff.toStringAsFixed(2);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // ── Tahsilat Sonrası Kalan Canlı Önizleme ─────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: newRemaining <= 0.01
                          ? const Color(0xFFF0FDF4)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: newRemaining <= 0.01
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFFDE68A),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Alınacak Toplam Tutar:',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _kText)),
                            Text(
                              '₺${effective.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: effective > remaining + 0.01
                                    ? _kRed
                                    : _kGreenDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Kalan Sipariş Borcu:',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _kTextSecondary)),
                            Text(
                              newRemaining <= 0.01
                                  ? '₺0.00 (Borç Tam Kapanır)'
                                  : '₺${newRemaining.toStringAsFixed(2)} (Vadeli Devam Eder)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: newRemaining <= 0.01
                                    ? _kGreenDark
                                    : const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

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
                  onPressed: (_isSubmitting || !isValid) ? null : _submitPayment,
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
                        ? 'Ödeme Güncelleniyor...'
                        : (effective > 0.01
                            ? '₺${effective.toStringAsFixed(2)} Ödemeyi Güncelle'
                            : 'Ödemeyi Güncelle'),
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

  Widget _buildMethodTab({
    required String id,
    required String label,
    required IconData icon,
    required Color activeColor,
    required Color activeBg,
  }) {
    final isSel = _selectedMethod == id;

    return InkWell(
      onTap: () => _onMethodChanged(id),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        decoration: BoxDecoration(
          color: isSel ? activeBg : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? activeColor : _kBorder,
            width: isSel ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSel ? activeColor : _kTextSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                color: isSel ? activeColor : _kText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
