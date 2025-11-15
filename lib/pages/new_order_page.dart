import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import 'customers_page.dart';
import 'products_page.dart';

class NewOrderPage extends StatefulWidget {
  const NewOrderPage({super.key});

  @override
  State<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends State<NewOrderPage> {
  final OrderService _orderService = OrderService();
  final ProductService _productService = ProductService();

  Customer? _selectedCustomer;
  final Map<Product, int> _cart = {};
  double _paidAmount = 0;
  String _paymentMethod = 'cash';
  final _notesController = TextEditingController();
  bool _isLoading = false;

  double get _total {
    return _cart.entries
        .fold(0, (sum, entry) => sum + (entry.key.price * entry.value));
  }

  double get _remainingAmount => _total - _paidAmount;

  bool get _isQuickSale => _selectedCustomer == null;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectCustomer() async {
    final result = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomersPage(),
      ),
    );

    if (result != null) {
      setState(() => _selectedCustomer = result);
    }
  }

  Future<void> _selectProducts() async {
    final result = await Navigator.push<List<Product>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProductsPage(),
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        for (var product in result) {
          _cart[product] = (_cart[product] ?? 0) + 1;
        }
      });
    }
  }

  Future<void> _updateQuantity(Product product, int currentQty) async {
    final controller = TextEditingController(text: currentQty.toString());

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Miktar',
            suffixText: 'adet',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = int.tryParse(controller.text) ?? 0;
              if (newQty > 0) {
                setState(() => _cart[product] = newQty);
              } else {
                setState(() => _cart.remove(product));
              }
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _createOrder() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen ürün ekleyin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Stok kontrolü
      for (var entry in _cart.entries) {
        if (entry.key.stock < entry.value) {
          throw Exception('${entry.key.name} için yeterli stok yok!');
        }
      }

      final order = Order(
        orderNumber: 'SIP-${DateTime.now().millisecondsSinceEpoch}',
        customerId: _selectedCustomer?.id ?? 0,
        customerName: _selectedCustomer?.name ?? 'Hızlı Satış',
        customerPhone: _selectedCustomer?.phone ?? '',
        total: _total,
        paidAmount: _paidAmount,
        paymentStatus: _paidAmount >= _total
            ? 'paid'
            : (_paidAmount > 0 ? 'partial' : 'unpaid'),
        status: 'pending',
        paymentMethod: _paymentMethod,
        notes: _notesController.text,
        createdAt: DateTime.now().toIso8601String(),
      );

      final items = _cart.entries.map((entry) {
        final subtotal = entry.key.price * entry.value;
        return OrderItem(
          orderId: 0, // Geçici, create metodu dolduracak
          productId: entry.key.id!,
          productName: entry.key.name,
          quantity: entry.value,
          price: entry.key.price,
          subtotal: subtotal,
        );
      }).toList();

      await _orderService.create(order, items);

      // Stok güncelle
      for (var entry in _cart.entries) {
        final newStock = entry.key.stock - entry.value;
        await _productService.updateStock(entry.key.id!, newStock);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isQuickSale
                ? 'Hızlı satış tamamlandı'
                : 'Sipariş oluşturuldu'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isQuickSale ? 'Hızlı Satış' : 'Yeni Sipariş'),
        actions: [
          if (_selectedCustomer != null)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _selectedCustomer = null),
              tooltip: 'Müşteriyi Kaldır',
            ),
        ],
      ),
      body: Column(
        children: [
          // Müşteri Seçimi
          Container(
            color: _isQuickSale
                ? Colors.orange.withOpacity(0.1)
                : const Color(0xFF10B981).withOpacity(0.1),
            child: ListTile(
              leading: Icon(
                _isQuickSale ? Icons.flash_on_rounded : Icons.person_rounded,
                color: _isQuickSale ? Colors.orange : const Color(0xFF10B981),
              ),
              title: Text(
                _selectedCustomer?.name ?? 'Hızlı Satış',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _selectedCustomer?.phone ?? 'Müşteri seçilmedi',
                style: TextStyle(color: Colors.grey[600]),
              ),
              trailing: ElevatedButton.icon(
                onPressed: _selectCustomer,
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: Text(
                    _selectedCustomer == null ? 'Müşteri Seç' : 'Değiştir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isQuickSale ? Colors.orange : const Color(0xFF10B981),
                ),
              ),
            ),
          ),

          // Ürünler
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('Sepet boş',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey[600])),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _selectProducts,
                          icon: const Icon(Icons.add_shopping_cart_rounded),
                          label: const Text('Ürün Ekle'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final entry = _cart.entries.elementAt(index);
                      final product = entry.key;
                      final quantity = entry.value;
                      final subtotal = product.price * quantity;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.inventory_2_rounded,
                                color: Color(0xFF3B82F6)),
                          ),
                          title: Text(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '₺${product.price.toStringAsFixed(2)} × $quantity = ₺${subtotal.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_rounded),
                                onPressed: () =>
                                    _updateQuantity(product, quantity),
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFF1F5F9),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded),
                                onPressed: () =>
                                    setState(() => _cart.remove(product)),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red.withOpacity(0.1),
                                  foregroundColor: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Alt Bar
          if (_cart.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ürün Ekle Butonu
                      OutlinedButton.icon(
                        onPressed: _selectProducts,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Daha Fazla Ürün Ekle'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Toplam
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Toplam:',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          Text('₺${_total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF10B981))),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Ödeme Tutarı
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Ödenen Tutar',
                          prefixText: '₺',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.done_all_rounded),
                            onPressed: () =>
                                setState(() => _paidAmount = _total),
                            tooltip: 'Tamamını Öde',
                          ),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setState(
                              () => _paidAmount = double.tryParse(value) ?? 0);
                        },
                      ),

                      if (_remainingAmount > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_rounded,
                                  color: Colors.orange, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Kalan: ₺${_remainingAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange),
                              ),
                              if (!_isQuickSale) ...[
                                const Spacer(),
                                const Text('(Müşteriye borç)',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.orange)),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Oluştur Butonu
                      ElevatedButton(
                        onPressed: _isLoading ? null : _createOrder,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _isQuickSale
                                    ? 'Satışı Tamamla'
                                    : 'Siparişi Oluştur',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
