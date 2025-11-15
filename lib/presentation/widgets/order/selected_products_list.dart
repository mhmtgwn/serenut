import 'package:flutter/material.dart';

class SelectedProductsList extends StatefulWidget {
  final List<Map<String, dynamic>> selectedProducts;
  final Function(int, double) onQuantityChanged;
  final Function(int) onProductRemoved;
  final double totalAmount;

  const SelectedProductsList({
    Key? key,
    required this.selectedProducts,
    required this.onQuantityChanged,
    required this.onProductRemoved,
    required this.totalAmount,
  }) : super(key: key);

  @override
  State<SelectedProductsList> createState() => _SelectedProductsListState();
}

class _SelectedProductsListState extends State<SelectedProductsList> {
  late Map<int, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _controllers = {};
    for (int i = 0; i < widget.selectedProducts.length; i++) {
      final quantity = widget.selectedProducts[i]['quantity'] ?? 1.0;
      _controllers[i] = TextEditingController(
        text: quantity.toStringAsFixed(quantity == quantity.toInt() ? 0 : 1),
      );
    }
  }

  @override
  void didUpdateWidget(SelectedProductsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProducts.length != widget.selectedProducts.length) {
      _initializeControllers();
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
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
                const Icon(Icons.shopping_cart, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Seçilen Ürünler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Toplam: ${widget.totalAmount.toStringAsFixed(2)} TL',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.selectedProducts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Henüz ürün seçilmedi'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.selectedProducts.length,
                itemBuilder: (context, index) {
                  final product = widget.selectedProducts[index];
                  final unitPrice = product['unitPrice'] ?? 0.0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        '${product['name'] ?? 'İsimsiz Ürün'} - ${unitPrice.toStringAsFixed(2)} TL',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Miktar TextField
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: _controllers[index],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                isDense: true,
                              ),
                              textAlign: TextAlign.center,
                              onTap: () {
                                _controllers[index]?.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset:
                                      _controllers[index]?.text.length ?? 0,
                                );
                              },
                              onSubmitted: (value) {
                                final newQuantity =
                                    double.tryParse(value) ?? 1.0;
                                if (newQuantity > 0) {
                                  widget.onQuantityChanged(index, newQuantity);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => widget.onProductRemoved(index),
                            icon: const Icon(Icons.delete, color: Colors.red),
                            iconSize: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
