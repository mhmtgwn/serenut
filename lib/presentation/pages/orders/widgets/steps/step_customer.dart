part of '../order_creation_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Müşteri Seçme Adımı — OrderCreationDialog için
// Ortak CustomerPickerWidget kullanır; eski ~540 satır buraya gerek kalmadı.
// ─────────────────────────────────────────────────────────────────────────────



extension OrderCreationCustomerStep on OrderCreationDialogState {
  Widget _buildCustomerStep() {
    return CustomerPickerWidget(
      config: CustomerPickerConfig.orders(),
      selectedCustomer: _selectedCustomer,
      fullPageMode: true,
      onSelected: (customer) {
        updateState(() => _selectedCustomer = customer);
      },
      onCleared: () {
        updateState(() => _selectedCustomer = null);
      },
      onSavedAndSelected: (newCustomer) {
        // Sipariş adımında yeni müşteri eklenince otomatik ilerle
        updateState(() => _selectedCustomer = newCustomer);
        _showNotification('${newCustomer.name} seçildi ve siparişe atandı.');
        _nextStep();
      },
    );
  }
}
