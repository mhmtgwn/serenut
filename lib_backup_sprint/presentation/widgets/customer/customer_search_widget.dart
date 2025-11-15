import 'package:flutter/material.dart';

class CustomerSearchWidget extends StatelessWidget {
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final VoidCallback onAddCustomer;

  const CustomerSearchWidget({
    Key? key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onAddCustomer,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Müşteri Ara',
                hintText: 'İsim veya telefon numarası',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            onPressed: onAddCustomer,
            tooltip: 'Yeni Müşteri',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
