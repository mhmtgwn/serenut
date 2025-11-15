import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/datasources/customer_service.dart';
import '../../shared/constants/app_theme.dart';
import '../../shared/constants/theme_provider.dart';
import '../widgets/add_customer_form.dart';
import '../widgets/customer/contact_sync_widget.dart';
import '../widgets/customer/customer_search_widget.dart';
import '../widgets/customer/customer_list_widget.dart';

class CustomersContent extends StatefulWidget {
  final bool isSelectionMode;

  const CustomersContent({super.key, this.isSelectionMode = false});

  @override
  State<CustomersContent> createState() => CustomersContentState();
}

class CustomersContentState extends State<CustomersContent> {
  List<Map<String, dynamic>> _customers = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Public erişim için getter
  TextEditingController get searchController => _searchController;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await CustomerService.instance.getAllCustomers();
      if (mounted) {
        setState(() {
          _customers = customers;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Müşteriler yüklenirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _onCustomerTap(Map<String, dynamic> customer) {
    if (widget.isSelectionMode) {
      Navigator.pop(context, customer);
    } else {
      _showCustomerDetails(customer);
    }
  }

  void _showCustomerDetails(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer['displayName'] ?? 'Müşteri Detayı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (customer['phone']?.toString().isNotEmpty == true)
              Text('Telefon: ${customer['phone']}'),
            if (customer['email']?.toString().isNotEmpty == true)
              Text('E-posta: ${customer['email']}'),
            if (customer['company']?.toString().isNotEmpty == true)
              Text('Şirket: ${customer['company']}'),
            if (customer['notes']?.toString().isNotEmpty == true)
              Text('Notlar: ${customer['notes']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _addNewCustomer() {
    showDialog(
      context: context,
      builder: (context) => AddCustomerForm(
        onCustomerAdded: _loadCustomers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode
        ? AppTheme.darkBackgroundColor
        : AppTheme.lightBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Arama çubuğu
          CustomerSearchWidget(
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            onAddCustomer: _addNewCustomer,
          ),

          // Rehber senkronizasyonu
          if (!widget.isSelectionMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ContactSyncWidget(
                onSyncCompleted: _loadCustomers,
              ),
            ),

          // Müşteri listesi
          Expanded(
            child: CustomerListWidget(
              customers: _customers,
              searchQuery: _searchQuery,
              isSelectionMode: widget.isSelectionMode,
              onCustomerTap: _onCustomerTap,
              onCustomersChanged: _loadCustomers,
            ),
          ),
        ],
      ),
    );
  }
}
