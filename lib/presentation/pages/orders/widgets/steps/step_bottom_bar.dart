part of '../order_creation_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Action Bar + Validation + Order Submit Logic
// ─────────────────────────────────────────────────────────────────────────────

extension OrderCreationBottomBar on OrderCreationDialogState {
  Widget buildBottomActionBar() {
    final nextDisabled = _isNextDisabled();
    final totalQty = _cart.values.fold(0.0, (a, b) => a + b);

    String nextButtonLabel = 'Devam Et';
    if (_activeStep == 0) {
      nextButtonLabel = 'Ürün Seçimine Geç';
    } else if (_activeStep == 1) {
      nextButtonLabel = 'Sepete Geç (${_formatQuantity(totalQty)} Birim)';
    } else if (_activeStep == 2) {
      nextButtonLabel = 'Ödemeye Geç (₺${_totalAmount.toStringAsFixed(2)})';
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          _activeStep > 0
              ? OutlinedButton.icon(
                  onPressed: _prevStep,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Geri'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                )
              : OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                  child: const Text('Kapat'),
                ),
          // Next / Confirm button
          _activeStep < 3
              ? ElevatedButton.icon(
                  onPressed: nextDisabled ? null : _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(nextButtonLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                )
              : ElevatedButton.icon(
                  onPressed: _isSubmitting ||
                          _paymentMethod.isEmpty ||
                          (_paymentMethod == 'karma' && !_karmaValid)
                      ? null
                      : _submitOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(
                      widget.existingOrder != null
                          ? 'Siparişi Güncelle'
                          : 'Siparişi Onayla',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
        ],
      ),
    );
  }

  bool _isNextDisabled() {
    if (_activeStep == 0) return _selectedCustomer == null;
    if (_activeStep == 1) return _cart.isEmpty;
    if (_activeStep == 2) return _cart.isEmpty;
    return false;
  }

  Future<void> _submitOrder() async {
    updateState(() => _isSubmitting = true);

    AuthorizedCardPayment? cardPayment;
    try {
      // 0. Pre-flight inventory stock verification BEFORE running card transaction or modifying state
      final inventoryCheckItems = _cart.entries.map((e) {
        final rawQty = e.value;
        final intQty = rawQty >= 1.0 ? rawQty.round() : (rawQty > 0.0 ? 1 : 0);
        return SaleItemInput(
          productId: e.key.id,
          productName: e.key.name,
          quantity: intQty,
          saleQuantity: rawQty,
          unitPrice: e.key.price,
        );
      }).toList();
      await ref
          .read(ordersControllerProvider.notifier)
          .verifyStockAvailability(inventoryCheckItems);

      final itemsList = _cart.entries
          .map((e) => {
                'product_id': e.key.id,
                'product_name': e.key.name,
                'quantity': e.value,
                'unit_price': e.key.price,
                'tax': e.key.vat ?? 0.0,
                'total_price': e.value * e.key.price,
              })
          .toList();

      final isEdit = widget.existingOrder != null;
      // Use uuid v4 for new orders — consistent & collision-free
      final String orderId =
          isEdit ? widget.existingOrder!.id : 'ord-${const Uuid().v4()}';

      final currentUser = ref.read(currentUserProvider);
      final cashierName = currentUser?.name ?? 'Kasiyer';

      final newOrder = OrderEntity(
        id: orderId,
        customerId: _selectedCustomer!.id,
        customerName: _selectedCustomer!.name,
        customerPhone: _selectedCustomer!.phone,
        status: isEdit ? widget.existingOrder!.status : 'created',
        createdAt: isEdit ? widget.existingOrder!.createdAt : DateTime.now(),
        expectedDeliveryDate: _expectedDelivery,
        actualDeliveryDate:
            isEdit ? widget.existingOrder!.actualDeliveryDate : null,
        items: itemsList,
        notes: _notesController.text.trim(),
        createdBy: isEdit ? widget.existingOrder!.createdBy : cashierName,
        discountAmount: _discountAmount,
      );

      // Process customer balance ledger
      final previousDebt = max(0.0, -_selectedCustomer!.balance);
      double finalPaid = _totalAmount;
      if (_paymentMethod == 'debt') {
        finalPaid = 0.0;
      } else if (_paymentMethod == 'karma') {
        finalPaid = _karmaResult.paidAmount;
      }
      final cardAmount = _paymentMethod == 'card'
          ? _totalAmount
          : _paymentMethod == 'karma'
              ? _karmaCard
              : 0.0;
      final hasPos =
          ref.read(hardwareConfigProvider).valueOrNull?.hasPosBridge == true;
      if (cardAmount > 0 && hasPos) {
        cardPayment = await ref
            .read(ordersControllerProvider.notifier)
            .authorizeCardPayment(
              amount: cardAmount,
              idempotencyKey: 'order-card-$orderId',
            );
      }
      final cardMetadata = cardAmount <= 0
          ? null
          : cardPayment?.ledgerMetadata ??
              PhysicalCardPaymentService.manualLedgerMetadata(
                context: 'order_creation',
              );
      final paymentMetadata = _paymentMethod == 'karma'
          ? <String, dynamic>{
              'payment_breakdown': {
                'cash_tendered': _karmaResult.cashTendered,
                'cash_applied': _karmaResult.cashApplied,
                'card': _karmaResult.card,
                'debt': _karmaResult.debt,
                'change': _karmaResult.change,
              },
              ...?cardMetadata,
            }
          : cardMetadata;

      await ref.read(ordersControllerProvider.notifier).recordOrderPayment(
            order: newOrder,
            isEdit: isEdit,
            existingOrder: widget.existingOrder,
            customerId: _selectedCustomer!.id,
            orderTotal: _totalAmount,
            orderPaid: finalPaid,
            paymentMethod: _paymentMethod,
            paymentMetadata: paymentMetadata,
          );

      if (cardPayment != null) {
        await ref
            .read(ordersControllerProvider.notifier)
            .commitCardPayment(cardPayment, contextId: newOrder.id);
      }

      // ── Pop dialog immediately to keep UI ultra responsive (<50ms) ──
      if (!mounted) return;
      // Capture necessary providers & root container BEFORE popping the dialog
      // to eliminate "Bad state: Cannot use ref after the widget was disposed"
      final container = ProviderScope.containerOf(context);
      final ordersNotifier = ref.read(ordersControllerProvider.notifier);
      var settings = ref.read(settingsNotifierProvider).valueOrNull ??
          ref.read(settingsNotifierProvider).value;
      final ordersCustomersNotifier =
          ref.read(ordersCustomersControllerProvider.notifier);

      Navigator.pop(context);
      AppNotificationHost.show(
        SnackBar(
          content: Text(isEdit
              ? 'Sipariş başarıyla güncellendi.'
              : 'Sipariş başarıyla oluşturuldu.'),
          backgroundColor: _kGreen,
        ),
      );

      // ── Background tasks: Print immediately & refresh state via root container ──
      final customer = _selectedCustomer;
      final existingCustId = widget.existingOrder?.customerId;
      final printReceiptNeeded = _printReceipt;
      final printLabelNeeded = _printLabel;
      final printCopies = _printCopies;
      final labelCopies = _labelCopies;
      final paymentMethod = _paymentMethod;
      final karmaResult = _karmaResult;
      final notes = _notesController.text.trim();
      final totalAmount = _totalAmount;
      final receiptItems = _cart.entries
          .map((e) => {
                'product_name': e.key.name,
                'product_id': e.key.id,
                'barcode': e.key.id,
                'quantity': e.value,
                'unit_price': e.key.price,
              })
          .toList();

      unawaited(() async {
        await ordersNotifier.queueOrderPrints(
          order: newOrder,
          receiptItems: receiptItems,
          customer: customer,
          settings: settings,
          finalPaid: finalPaid,
          previousDebt: previousDebt,
          orderTotal: totalAmount,
          paymentMethod: paymentMethod,
          paymentBreakdown: paymentMethod == 'karma'
              ? {
                  'cash_applied': karmaResult.cashApplied,
                  'card': karmaResult.card,
                  'debt': karmaResult.debt,
                }
              : null,
          notes: notes,
          printLabel: printLabelNeeded,
          printReceipt: printReceiptNeeded,
          labelCopies: labelCopies,
          printCopies: printCopies,
        );

        // 3. Ekran yenilemeleri (Root Container üzerinden, Widget dispose'undan etkilenmez)
        try {
          await ordersCustomersNotifier.refresh();
          container.invalidate(customersControllerProvider);
          container.invalidate(salesCustomersControllerProvider);
          container.invalidate(customerBalanceSummaryProvider);
          container.invalidate(customerLookupMapProvider);
          if (customer != null) {
            container.invalidate(customerTransactionsProvider(customer.id));
            container.invalidate(customerBalanceDetailsProvider(customer.id));
            container.invalidate(customerDetailProvider(customer.id));
          }
          if (isEdit &&
              existingCustId != null &&
              customer?.id != existingCustId) {
            container.invalidate(customerTransactionsProvider(existingCustId));
            container
                .invalidate(customerBalanceDetailsProvider(existingCustId));
            container.invalidate(customerDetailProvider(existingCustId));
          }
          container.invalidate(productsControllerProvider);
          container.invalidate(salesProductsControllerProvider);
          container.invalidate(ordersProductsControllerProvider);
          container.invalidate(dashboardProvider);
        } catch (refreshError) {
          debugPrint(
              '[OrderCreationDialog] Ekran verileri yenileme hatası: $refreshError');
        }
      }());
    } catch (e) {
      if (cardPayment != null) {
        await ref
            .read(physicalCardPaymentServiceProvider)
            .markUnreconciled(cardPayment, e);
      }
      updateState(() => _isSubmitting = false);
      if (mounted) {
        AppNotificationHost.show(
          SnackBar(
              content: Text('Sipariş kaydedilirken hata: $e'),
              backgroundColor: _kRed),
        );
      }
    }
  }
}
