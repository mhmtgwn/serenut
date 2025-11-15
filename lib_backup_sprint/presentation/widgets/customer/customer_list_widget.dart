import 'package:flutter/material.dart';
import '../../../data/datasources/customer_service.dart';
import '../add_customer_form.dart';

class CustomerListWidget extends StatefulWidget {
  final List<Map<String, dynamic>> customers;
  final String searchQuery;
  final bool isSelectionMode;
  final Function(Map<String, dynamic>) onCustomerTap;
  final VoidCallback onCustomersChanged;

  const CustomerListWidget({
    Key? key,
    required this.customers,
    required this.searchQuery,
    required this.isSelectionMode,
    required this.onCustomerTap,
    required this.onCustomersChanged,
  }) : super(key: key);

  @override
  State<CustomerListWidget> createState() => _CustomerListWidgetState();
}

class _CustomerListWidgetState extends State<CustomerListWidget> {
  List<Map<String, dynamic>> get _filteredCustomers {
    if (widget.searchQuery.isEmpty) {
      return widget.customers;
    }

    return widget.customers.where((customer) {
      final name = customer['displayName']?.toString().toLowerCase() ?? '';
      final phone = customer['phone']?.toString().toLowerCase() ?? '';
      final query = widget.searchQuery.toLowerCase();

      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = _filteredCustomers;

    if (filteredCustomers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'Müşteri bulunamadı',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredCustomers.length,
      itemBuilder: (context, index) {
        final customer = filteredCustomers[index];
        return _buildCustomerCard(customer);
      },
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: Text(
            (customer['displayName']?.toString().isNotEmpty == true)
                ? customer['displayName'].toString()[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer['displayName'] ?? 'İsimsiz',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (customer['phone']?.toString().isNotEmpty == true)
              Text('📞 ${customer['phone']}'),
            if (customer['email']?.toString().isNotEmpty == true)
              Text('✉️ ${customer['email']}'),
            if (customer['company']?.toString().isNotEmpty == true)
              Text('🏢 ${customer['company']}'),
          ],
        ),
        trailing: widget.isSelectionMode
            ? const Icon(Icons.arrow_forward_ios)
            : PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(value, customer),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Düzenle'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Sil'),
                    ),
                  ),
                ],
              ),
        onTap: () => widget.onCustomerTap(customer),
      ),
    );
  }

  void _handleMenuAction(String action, Map<String, dynamic> customer) {
    switch (action) {
      case 'edit':
        _editCustomer(customer);
        break;
      case 'delete':
        _deleteCustomer(customer);
        break;
    }
  }

  void _editCustomer(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AddCustomerForm(
        onCustomerAdded: () {
          widget.onCustomersChanged();
        },
      ),
    );
  }

  void _deleteCustomer(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Müşteriyi Sil'),
        content: Text(
          '${customer['displayName'] ?? 'Bu müşteri'} silinsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performDelete(customer);
            },
            child: const Text(
              'Sil',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDelete(Map<String, dynamic> customer) async {
    try {
      await CustomerService.instance.deleteCustomer(customer['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Müşteri başarıyla silindi'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onCustomersChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Müşteri silinirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
