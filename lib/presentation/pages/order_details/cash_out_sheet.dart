part of '../order_details_page.dart';

// ── Top-Level Helper For Printing ───────────────────────────────────────────
Future<void> _triggerPrint(WidgetRef ref, OrderEntity order) async {
  final settingsAsync = ref.read(settingsNotifierProvider);
  final settings = settingsAsync.value;
  if (settings == null) return;
  final hasPrinter = await ref
          .read(printingRepositoryProvider)
          .getRoute(PrintDocumentKind.receipt) !=
      null;
  if (!hasPrinter) return;

  try {
    CustomerEntity? customer;
    if (order.customerId.isNotEmpty) {
      try {
        final custRepo = await ref.read(customerRepositoryProvider.future);
        customer = await custRepo.findById(order.customerId);
      } catch (_) {}
    }

    final products = ref.read(productsControllerProvider).value ?? [];
    final receiptItems = order.items.map((item) {
      final prod = products.firstWhere(
        (p) => p.id == item['product_id'],
        orElse: () => ProductEntity(
          id: item['product_id'] ?? '',
          name: item['product_id'] ?? 'Urun',
          description: '',
          price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          quantity: 0,
          category: '',
        ),
      );
      return {
        'product_id': item['product_id'],
        'product_name': item['product_name'] ?? prod.name,
        'barcode': prod.id,
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
      };
    }).toList();

    await ref.read(printingApplicationServiceProvider).queueOrderReceipt(
          order,
          receiptItems,
          customer != null && customer.id.isNotEmpty
              ? customer
              : (order.customerName?.isNotEmpty == true
                  ? CustomerEntity(
                      id: order.customerId,
                      name: order.customerName!,
                      email: '',
                      phone: order.customerPhone ?? '',
                      balance: 0,
                      createdAt: DateTime.now())
                  : null),
          settings,
        );
  } catch (e, st) {
    unawaited(TelemetryService().logError(e, st, context: 'order_delivery_print'));
    debugPrint('Printing error in delivery: $e');
  }
}

// ── Cash Out Bottom Sheet Widget ─────────────────────────────────────────────
class _CashOutSheet extends ConsumerStatefulWidget {
  final OrderEntity order;
  final FinancialTransactionEntity saleTx;
  final double totalPaid;

  const _CashOutSheet({
    required this.order,
    required this.saleTx,
    required this.totalPaid,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required OrderEntity order,
    required FinancialTransactionEntity saleTx,
    required double totalPaid,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isDesktop = screenWidth >= 900;

    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16,
          vertical: isDesktop ? 24 : 16,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 820,
            maxHeight: (screenHeight * 0.88).clamp(400.0, 750.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _CashOutSheet(
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
  ConsumerState<_CashOutSheet> createState() => _CashOutSheetState();
}

class _CashOutSheetState extends ConsumerState<_CashOutSheet> {
  String _selectedMethod = 'cash'; // 'cash', 'card', 'debt', 'karma'

  final TextEditingController _karmaCashController = TextEditingController();
  final TextEditingController _karmaCardController = TextEditingController();
  final TextEditingController _karmaDebtController = TextEditingController();

  bool _isSubmitting = false;
  bool _printReceipt = true;
  int _printCopies = 1;

  @override
  void dispose() {
    _karmaCashController.dispose();
    _karmaCardController.dispose();
    _karmaDebtController.dispose();
    super.dispose();
  }

  double get _remainingAmount =>
      (widget.saleTx.amount - widget.totalPaid).clamp(0.0, double.infinity);

  double get _karmaCash =>
      double.tryParse(_karmaCashController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaCard =>
      double.tryParse(_karmaCardController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaDebt =>
      double.tryParse(_karmaDebtController.text.replaceAll(',', '.')) ?? 0.0;

  MixedPaymentResult get _karmaResult => MixedPaymentCalculator.calculate(
        total: _remainingAmount,
        cashTendered: _karmaCash,
        card: _karmaCard,
        debt: _karmaDebt,
      );
  double get _karmaTotal => _karmaResult.allocatedTotal;
  double get _karmaRemainder => _karmaResult.remaining;
  bool get _karmaValid => _karmaResult.isValid;

  Future<void> _submitPayment() async {
    setState(() {
      _isSubmitting = true;
    });

    final remaining = _remainingAmount;

    AuthorizedCardPayment? cardPayment;
    try {
      final paymentService = await ref.read(paymentServiceProvider.future);
      final cardAmount = _selectedMethod == 'card'
          ? remaining
          : _selectedMethod == 'karma'
              ? _karmaCard
              : 0.0;
      final hasPos =
          ref.read(hardwareConfigProvider).valueOrNull?.hasPosBridge == true;
      if (cardAmount > 0 && hasPos) {
        cardPayment =
            await ref.read(physicalCardPaymentServiceProvider).authorize(
                  amount: cardAmount,
                  idempotencyKey:
                      'order-payment-${widget.order.id}-${widget.totalPaid.toStringAsFixed(2)}',
                );
      }
      final cardMetadata = cardAmount <= 0
          ? null
          : cardPayment?.ledgerMetadata ??
              PhysicalCardPaymentService.manualLedgerMetadata(
                context: 'order_collection',
              );

      if (_selectedMethod == 'cash') {
        if (remaining > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: remaining,
            method: 'cash',
            currentPaidAmount: widget.totalPaid,
            totalAmount: widget.saleTx.amount,
            terminalMetadata: null,
          );
        }
      } else if (_selectedMethod == 'card') {
        if (remaining > 0) {
          await paymentService.recordPartialPayment(
            saleId: widget.order.id,
            customerId: widget.order.customerId,
            amount: remaining,
            method: 'card',
            currentPaidAmount: widget.totalPaid,
            totalAmount: widget.saleTx.amount,
            terminalMetadata: cardMetadata,
          );
        }
      } else if (_selectedMethod == 'karma') {
        double currentPaid = widget.totalPaid;
        final kCash = _karmaResult.cashApplied;
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
      await ref
          .read(ordersControllerProvider.notifier)
          .updateStatus(widget.order.id, 'delivered');

      await ref.read(customersControllerProvider.notifier).refresh();
      ref.invalidate(customerTransactionsProvider(widget.order.customerId));
      ref.invalidate(customerBalanceDetailsProvider(widget.order.customerId));
      ref.invalidate(_orderDetailProvider(widget.order.id));

      // Print Fiş (Receipt)
      if (_printReceipt) {
        final settingsAsync = ref.read(settingsNotifierProvider);
        final settings = settingsAsync.value;
        if (settings != null) {
          final hasPrinter = await ref
                  .read(printingRepositoryProvider)
                  .getRoute(PrintDocumentKind.receipt) !=
              null;
          if (hasPrinter) {
            CustomerEntity? customer;
            if (widget.order.customerId.isNotEmpty) {
              try {
                final custRepo =
                    await ref.read(customerRepositoryProvider.future);
                customer = await custRepo.findById(widget.order.customerId);
              } catch (_) {}
            }

            final products = ref.read(productsControllerProvider).value ?? [];
            final receiptItems = widget.order.items.map((item) {
              final prod = products.firstWhere(
                (p) => p.id == item['product_id'],
                orElse: () => ProductEntity(
                  id: item['product_id'] ?? '',
                  name: item['product_id'] ?? 'Urun',
                  description: '',
                  price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
                  quantity: 0,
                  category: '',
                ),
              );
              return {
                'product_id': item['product_id'],
                'product_name': item['product_name'] ?? prod.name,
                'barcode': prod.id,
                'quantity': item['quantity'],
                'unit_price': item['unit_price'],
              };
            }).toList();

            final double currentFinalPaid = widget.totalPaid +
                (_selectedMethod == 'cash'
                    ? remaining
                    : (_selectedMethod == 'card'
                        ? remaining
                        : (_selectedMethod == 'karma'
                            ? _karmaResult.paidAmount
                            : 0.0)));

            await ref
                .read(printingApplicationServiceProvider)
                .queueOrderReceipt(
                  widget.order,
                  receiptItems,
                  customer != null && customer.id.isNotEmpty
                      ? customer
                      : (widget.order.customerName?.isNotEmpty == true
                          ? CustomerEntity(
                              id: widget.order.customerId,
                              name: widget.order.customerName!,
                              email: '',
                              phone: widget.order.customerPhone ?? '',
                              balance: 0,
                              createdAt: DateTime.now())
                          : null),
                  settings,
                  paidAmount: currentFinalPaid,
                  notes: widget.order.notes?.trim(),
                  paymentMethod: _selectedMethod,
                  paymentBreakdown: _selectedMethod == 'karma'
                      ? {
                          'cash_applied': _karmaResult.cashApplied,
                          'card': _karmaResult.card,
                          'debt': _karmaResult.debt,
                        }
                      : null,
                  copies: _printCopies,
                );
          }
        }
      }


      if (mounted) {
        Navigator.pop(context);

        String msg = '';
        if (_selectedMethod == 'debt') {
          msg = 'Sipariş vadeli olarak teslim edildi.';
        } else {
          msg = 'Ödeme alındı ve sipariş teslim edildi.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: _kGreenDark,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      unawaited(TelemetryService().logError(e, st, context: 'order_cashout_payment'));
      if (cardPayment != null) {
        await ref
            .read(physicalCardPaymentServiceProvider)
            .markUnreconciled(cardPayment, e);
      }
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingAmount;
    final isKarma = _selectedMethod == 'karma';
    final karmaTotal = _karmaTotal;
    final karmaValid = _karmaValid;
    final karmaRemaining = _karmaRemainder;

    final bool isActionDisabled = _selectedMethod == 'karma' && !karmaValid;

    // Load reactive customer details
    final customerAsync = widget.order.customerId.isNotEmpty
        ? ref.watch(customerDetailProvider(widget.order.customerId))
        : null;
    final customer = customerAsync?.valueOrNull;

    // Left column (Summary Info)
    final leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Sipariş Bilgileri',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        _buildSummaryRow(
          icon: Icons.person_outline_rounded,
          label: 'Seçilen Müşteri',
          value: customer?.name ?? 'Yükleniyor...',
        ),
        if (customer != null)
          _buildSummaryRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Müşteri Bakiyesi',
            value:
                '₺${customer.balance.abs().toStringAsFixed(2)} ${customer.balance < 0 ? "(Borçlu)" : "(Alacaklı)"}',
            valueColor: customer.balance < 0 ? _kRed : _kGreenDark,
          ),
        _buildSummaryRow(
          icon: Icons.calendar_month_outlined,
          label: 'Teslimat Tarihi',
          value: widget.order.expectedDeliveryDate != null
              ? DateFormat('dd.MM.yyyy')
                  .format(widget.order.expectedDeliveryDate!)
              : 'Belirtilmedi',
        ),
        if (widget.order.notes != null && widget.order.notes!.trim().isNotEmpty)
          _buildSummaryRow(
            icon: Icons.notes_rounded,
            label: 'Not',
            value: widget.order.notes!.trim(),
          ),
      ],
    );

    // Right column (Payment Grid + Dynamic Inputs + Printer Settings)
    final rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Ödeme Yöntemi Seçin',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        // Totals box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isKarma && karmaTotal > 0)
                Text(
                  'Kalan: ₺${karmaRemaining.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: karmaValid ? _kGreenDark : _kRed,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                const SizedBox.shrink(),
              Text(
                '₺${remaining.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: _kGreenDark,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Karma Split Input Fields
        if (isKarma) ...[
          _buildKarmaFields(remaining, karmaValid, karmaRemaining),
          const SizedBox(height: 12),
        ],
        // Payment Button Grid
        _buildMethodsGrid(remaining),
        const SizedBox(height: 16),
        // Receipt Printer Controls (Sadece Fiş Yazdırma — Teslimat Aşamasında Etikete Gerek Yok)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(() => _printReceipt = !_printReceipt),
                icon: Icon(
                  _printReceipt
                      ? Icons.print_rounded
                      : Icons.print_disabled_rounded,
                  color: _printReceipt ? _kGreen : _kTextSecondary,
                  size: 20,
                ),
                tooltip:
                    _printReceipt ? 'Fiş Yazdırma Açık' : 'Fiş Yazdırma Kapalı',
                style: IconButton.styleFrom(
                  backgroundColor: _printReceipt ? _kGreenLight : Colors.white,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _printReceipt
                          ? _kGreen.withValues(alpha: 0.3)
                          : _kBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _InlineCopyCountField(
                value: _printCopies,
                isEnabled: _printReceipt,
                onChanged: (val) {
                  setState(() => _printCopies = val);
                },
              ),
              const SizedBox(width: 8),
              Text(
                _printReceipt ? 'Fiş Yazdırılacak' : 'Fiş Yazdırma Kapalı',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _printReceipt ? _kGreenDark : _kTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Teslim Et & Ödeme Al',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
            Text(
              'Sipariş #${widget.order.displayNumber}',
              style: const TextStyle(
                fontSize: 11,
                color: _kTextSecondary,
              ),
            ),
          ],
        ),
        backgroundColor: _kSurface,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isWide = constraints.maxWidth >= 600;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: leftCol,
                        ),
                      ),
                      const VerticalDivider(width: 1, color: _kBorder),
                      Expanded(
                        flex: 5,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: rightCol,
                        ),
                      ),
                    ],
                  );
                } else {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leftCol,
                        const Divider(height: 32, color: _kBorder),
                        rightCol,
                      ],
                    ),
                  );
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_isSubmitting || isActionDisabled)
                      ? null
                      : _submitPayment,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded,
                          size: 20),
                  label: Text(
                    _isSubmitting
                        ? 'Ödeme Kaydediliyor...'
                        : 'Ödemeyi Tamamla & Teslim Et',
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
      {required IconData icon,
      required String label,
      required String value,
      Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _kTextSecondary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: _kTextSecondary, fontSize: 12))),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: valueColor ?? _kText)),
        ],
      ),
    );
  }

  Widget _buildMethodsGrid(double remaining) {
    final methods = [
      {
        'id': 'cash',
        'label': 'Nakit',
        'icon': Icons.payments_rounded,
        'color': _kGreen
      },
      {
        'id': 'card',
        'label': 'Kart',
        'icon': Icons.credit_card_rounded,
        'color': Colors.blue
      },
      {
        'id': 'debt',
        'label': 'Vadeli (Borç)',
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.orange
      },
      {
        'id': 'karma',
        'label': 'Karma (Split)',
        'icon': Icons.call_split_rounded,
        'color': Colors.purple
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double aspectRatio = constraints.maxWidth > 400 ? 2.4 : 3.0;

        return GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: aspectRatio,
          physics: const NeverScrollableScrollPhysics(),
          children: methods.map((m) {
            final isSel = _selectedMethod == m['id'];
            final color = m['color'] as Color;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedMethod = m['id'] as String;
                  if (_selectedMethod == 'karma') {
                    _karmaCashController.text = remaining.toStringAsFixed(2);
                    _karmaCardController.text = '0.00';
                    _karmaDebtController.text = '0.00';
                  }
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
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
          }).toList(),
        );
      },
    );
  }

  void _onSplitFieldChanged(
      String field, String valStr, double remaining, bool hasCustomer) {
    setState(() {});
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
    return TextField(
      controller: controller,
      enabled: isEnabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: isEnabled ? color : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 11),
        prefixIcon:
            Icon(icon, color: isEnabled ? color : Colors.grey, size: 16),
        prefixText: '₺',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        isDense: true,
      ),
      onChanged: (val) =>
          _onSplitFieldChanged(fieldId, val, remaining, hasCustomer),
    );
  }

  Widget _buildKarmaFields(
      double remaining, bool karmaValid, double karmaRemaining) {
    final customerId = widget.order.customerId;
    final bool hasCustomer = customerId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: karmaValid ? _kGreen.withValues(alpha: 0.4) : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split_rounded,
                  size: 14, color: _kTextSecondary),
              const SizedBox(width: 6),
              const Text('Karma Ödeme Dağılımı',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (karmaValid)
                const Text('✓ Tamam',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kGreenDark,
                        fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          KarmaPaymentSummaryBar(
            total: remaining,
            paid: _karmaResult.paidAmount,
            remaining: karmaRemaining,
            debt: _karmaDebt,
            change: _karmaResult.change,
            isValid: karmaValid,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildSplitField(
                  controller: _karmaCashController,
                  label: 'Alınan Nakit',
                  icon: Icons.payments_rounded,
                  color: _kGreen,
                  fieldId: 'cash',
                  remaining: remaining,
                  hasCustomer: hasCustomer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSplitField(
                  controller: _karmaCardController,
                  label: 'Kart',
                  icon: Icons.credit_card_rounded,
                  color: Colors.blue,
                  fieldId: 'card',
                  remaining: remaining,
                  hasCustomer: hasCustomer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSplitField(
                  controller: _karmaDebtController,
                  label: 'Vadeli',
                  icon: Icons.account_balance_wallet_rounded,
                  color: Colors.orange,
                  fieldId: 'debt',
                  remaining: remaining,
                  hasCustomer: hasCustomer,
                  isEnabled: hasCustomer,
                ),
              ),
            ],
          ),
          if (_karmaResult.change > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Para üstü: ₺${_karmaResult.change.toStringAsFixed(2)}',
              style: const TextStyle(
                color: _kGreenDark,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Copy Count Field For Bottom Sheet ────────────────────────────────────────
class _InlineCopyCountField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool isEnabled;

  const _InlineCopyCountField({
    required this.value,
    required this.onChanged,
    this.isEnabled = true,
  });

  @override
  State<_InlineCopyCountField> createState() => _InlineCopyCountFieldState();
}

class _InlineCopyCountFieldState extends State<_InlineCopyCountField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_InlineCopyCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value.toString();
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _submitValue();
    }
  }

  void _submitValue() {
    final val = int.tryParse(_controller.text);
    if (val != null && val >= 1) {
      widget.onChanged(val);
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = widget.isEnabled
        ? Colors.white
        : (isDark ? Colors.black26 : Colors.grey.shade100);

    final Color borderColor = widget.isEnabled
        ? _kBorder
        : (isDark ? Colors.white24 : Colors.grey.shade300);

    final Color textColor =
        widget.isEnabled ? _kText : _kTextSecondary.withValues(alpha: 0.5);

    return Container(
      width: 36,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.isEnabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onSubmitted: (_) {
          _submitValue();
          _focusNode.unfocus();
        },
      ),
    );
  }
}
