import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../pages/products.dart';

class ProductSelector extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final Function(Map<String, dynamic>) onProductSelected;
  final bool isLoading;

  const ProductSelector({
    Key? key,
    required this.products,
    required this.onProductSelected,
    required this.isLoading,
  }) : super(key: key);

  @override
  State<ProductSelector> createState() => _ProductSelectorState();
}

class _ProductSelectorState extends State<ProductSelector> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products;
  }

  @override
  void didUpdateWidget(ProductSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products != widget.products) {
      _filteredProducts = widget.products;
      _filterProducts();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = widget.products;
      } else {
        _filteredProducts = widget.products.where((product) {
          final name = product['name']?.toString().toLowerCase() ?? '';
          final barcode = product['barcode']?.toString().toLowerCase() ?? '';
          return name.contains(query) || barcode.contains(query);
        }).toList();
      }
    });
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
                const Icon(Icons.inventory, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'Ürün Seçimi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _showBarcodeScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Barkod Tara',
                ),
                TextButton.icon(
                  onPressed: () => _navigateToProducts(),
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Ürün'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Ürün Ara',
                hintText: 'Ürün adı veya barkod',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _filterProducts(),
            ),
            const SizedBox(height: 12),
            if (widget.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_filteredProducts.isEmpty)
              const Center(
                child: Text('Ürün bulunamadı'),
              )
            else
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    return ListTile(
                      leading: const Icon(Icons.inventory_2),
                      title: Text(product['name'] ?? 'İsimsiz Ürün'),
                      subtitle: Text(
                        'Fiyat: ${product['price']} TL - Stok: ${product['stock']}',
                      ),
                      trailing: IconButton(
                        onPressed: () => widget.onProductSelected(product),
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                      ),
                      onTap: () => widget.onProductSelected(product),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBarcodeScanner() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Barkod Tara'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final barcode = barcodes.first.rawValue;
                Navigator.pop(context);
                _searchByBarcode(barcode ?? '');
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  void _searchByBarcode(String barcode) {
    final product = widget.products.firstWhere(
      (p) => p['barcode'] == barcode,
      orElse: () => {},
    );

    if (product.isNotEmpty) {
      widget.onProductSelected(product);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barkod bulunamadı: $barcode'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _navigateToProducts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProductsContent(),
      ),
    );
  }
}
