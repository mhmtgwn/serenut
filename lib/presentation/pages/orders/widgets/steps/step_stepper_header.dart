part of '../order_creation_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stepper Header + Step Body Router
// ─────────────────────────────────────────────────────────────────────────────

extension OrderCreationStepperHeader on OrderCreationDialogState {
  Widget buildStepperHeader() {
    final totalQty = _cart.values.fold(0.0, (a, b) => a + b);

    final steps = [
      {'icon': Icons.person_rounded, 'label': 'Müşteri'},
      {'icon': Icons.inventory_2_rounded, 'label': 'Ürünler'},
      {'icon': Icons.shopping_cart_rounded, 'label': 'Sepet'},
      {'icon': Icons.payments_rounded, 'label': 'Ödeme'},
    ];

    return Container(
      color: _kSurface,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final step = entry.value;
          final isCompleted = idx < _activeStep;
          final isCurrent = idx == _activeStep;
          final isCartStep = idx == 2;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () {
                  if (idx <= _activeStep) {
                    updateState(() => _activeStep = idx);
                  } else if (idx == 1 && _selectedCustomer != null) {
                    updateState(() => _activeStep = 1);
                  } else if (idx == 2 && _cart.isNotEmpty) {
                    updateState(() => _activeStep = 2);
                  } else if (idx == 3 && _cart.isNotEmpty) {
                    updateState(() => _activeStep = 3);
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? _kGreen
                                  : (isCompleted
                                      ? _kGreenLight
                                      : Colors.white),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isCurrent || isCompleted
                                    ? _kGreen
                                    : _kBorder,
                                width: isCurrent ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              isCompleted
                                  ? Icons.check_circle_rounded
                                  : (step['icon'] as IconData),
                              size: 16,
                              color: isCurrent
                                  ? Colors.white
                                  : (isCompleted
                                      ? _kGreenDark
                                      : _kTextSecondary),
                            ),
                          ),
                          if (isCartStep && _cart.isNotEmpty)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: _kGreenDark,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  _formatQuantity(totalQty),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        step['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.w600,
                          color: isCurrent
                              ? _kGreenDark
                              : (isCompleted ? _kText : _kTextSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (idx < 3)
                Container(
                  width: 24,
                  height: 2,
                  color: isCompleted ? _kGreen : _kBorder,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget buildStepBody() {
    switch (_activeStep) {
      case 0:
        return _buildCustomerStep();
      case 1:
        return _buildProductStep();
      case 2:
        return _buildCartStep();
      case 3:
        return _buildCheckoutStep();
      default:
        return const SizedBox.shrink();
    }
  }
}

