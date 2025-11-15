import 'package:flutter/material.dart';
import '../../../data/datasources/customer_service.dart';
import '../../pages/customers.dart';
import '../../../shared/utils/debug_config.dart';

class CustomerSelector extends StatefulWidget {
  final Map<String, dynamic>? selectedCustomer;
  final Function(Map<String, dynamic>?) onCustomerSelected;
  final bool isLoading;

  const CustomerSelector({
    Key? key,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.isLoading,
  }) : super(key: key);

  @override
  State<CustomerSelector> createState() => _CustomerSelectorState();
}

class _CustomerSelectorState extends State<CustomerSelector> {
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void didUpdateWidget(CustomerSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Seçilen müşteri değişirse dropdown'u güncelle
    if (oldWidget.selectedCustomer != widget.selectedCustomer) {
      setState(() {});
    }
  }

  Future<void> _loadCustomers() async {
    try {
      DebugConfig.logDebug('Müşteriler yükleniyor...');
      final customers = await CustomerService.instance.getAllCustomers();
      DebugConfig.logDebug('Yüklenen müşteri sayısı: ${customers.length}');
      if (customers.isNotEmpty) {
        DebugConfig.logSuccess('Müşteriler başarıyla yüklendi');
      } else {
        DebugConfig.logWarning('Hiç müşteri bulunamadı');
      }
      setState(() {
        _customers = customers;
      });
    } catch (e) {
      DebugConfig.logError('Müşteriler yüklenirken hata', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Müşteri Seçimi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _navigateToCustomers(),
                  icon: const Icon(Icons.add),
                  label: const Text('Müşteri Seç'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (widget.selectedCustomer != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.selectedCustomer!['displayName'] ??
                                'İsimsiz',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (widget.selectedCustomer!['phone']
                                  ?.toString()
                                  .isNotEmpty ==
                              true)
                            Text(
                              '📞 ${widget.selectedCustomer!['phone']}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        widget.onCustomerSelected(null);
                        DebugConfig.logDebug('Müşteri seçimi temizlendi');
                      },
                      icon: const Icon(Icons.close, color: Colors.red),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.person_off, size: 32, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text(
                      'Müşteri seçilmedi',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => _navigateToCustomers(),
                      icon: const Icon(Icons.add),
                      label: const Text('Müşteri Seç'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToCustomers() async {
    final selectedCustomer = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const CustomersContent(isSelectionMode: true),
      ),
    );

    if (selectedCustomer != null) {
      widget.onCustomerSelected(selectedCustomer);
      DebugConfig.logSuccess(
          'Müşteri seçildi: ${selectedCustomer['displayName']}');
      setState(() {
        _customers = [
          selectedCustomer,
          ..._customers.where((c) => c['id'] != selectedCustomer['id'])
        ];
      });
    }
  }
}
