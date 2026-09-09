part of '../checkout_section.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Satış / Checkout Müşteri Seçim Penceresi
// Ortak CustomerPickerWidget kullanır; ~540 satırlık duplikasyon elendi.
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerSelectionSheet extends StatelessWidget {
  final CustomerEntity? initialSelected;
  final Function(CustomerEntity?) onCustomerChanged;
  final bool isDialog;

  const _CustomerSelectionSheet({
    required this.initialSelected,
    required this.onCustomerChanged,
    required this.isDialog,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Müşteri Seç',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _kText,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: _kTextSecondary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: CustomerPickerWidget(
            config: CustomerPickerConfig.sales(),
            selectedCustomer: initialSelected,
            fullPageMode: false,
            onSelected: (customer) {
              onCustomerChanged(customer);
              Navigator.of(context).pop();
            },
            onCleared: () {
              onCustomerChanged(null);
              Navigator.of(context).pop();
            },
            onSavedAndSelected: (newCustomer) {
              onCustomerChanged(newCustomer);
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );

    if (isDialog) {
      return Container(
        width: 450,
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: content,
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        maxWidth: 500,
      ),
      child: content,
    );
  }
}
