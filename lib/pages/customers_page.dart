import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/customer_service.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final CustomerService _service = CustomerService();
  List<Customer> _customers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    final customers = await _service.getAll();
    setState(() {
      _customers = customers;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Müşteriler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _customers.isEmpty
              ? const Center(child: Text('Müşteri yok'))
              : ListView.builder(
                  itemCount: _customers.length,
                  itemBuilder: (context, index) {
                    final customer = _customers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(customer.name[0].toUpperCase()),
                      ),
                      title: Text(customer.name),
                      subtitle: Text(customer.phone),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showCustomerDialog(customer),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCustomerDialog(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showCustomerDialog(Customer? customer) async {
    final nameController = TextEditingController(text: customer?.name);
    final phoneController = TextEditingController(text: customer?.phone);
    final addressController = TextEditingController(text: customer?.address);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer == null ? 'Yeni Müşteri' : 'Müşteri Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Telefon'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Adres'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newCustomer = Customer(
                id: customer?.id,
                name: nameController.text,
                phone: phoneController.text,
                address: addressController.text,
                createdAt:
                    customer?.createdAt ?? DateTime.now().toIso8601String(),
              );

              if (customer == null) {
                await _service.add(newCustomer);
              } else {
                await _service.update(newCustomer);
              }

              if (context.mounted) {
                Navigator.pop(context);
                _loadCustomers();
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
