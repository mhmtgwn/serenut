import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../services/customer_service.dart';
import '../services/product_service.dart';
import '../services/order_service.dart';
import '../services/sms_service.dart';

class CreateOrderPage extends StatefulWidget {
  const CreateOrderPage({super.key});

  @override
  State<CreateOrderPage> createState() => _CreateOrderPageState();
}

class _CreateOrderPageState extends State<CreateOrderPage> {
  final CustomerService _customerService = CustomerService();
  final ProductService _productService = ProductService();
  final OrderService _orderService = OrderService();
  final SmsService _smsService = SmsService();

  List<Customer> _customers = [];
  List<Product> _products = [];
  Customer? _selectedCustomer;
  final Map<Product, int> _cart = {};
  String _paymentMethod = 'cash';
  final _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final customers = await _customerService.getAll();
    final products = await _productService.getAll();
    setState(() {
      _customers = customers;
      _products = products;
    });
  }

  double get _total {
    return _cart.entries
        .fold(0, (sum, entry) => sum + (entry.key.price * entry.value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Sipariş'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCustomerSelector(),
                  const SizedBox(height: 16),
                  _buildProductGrid(),
                  const SizedBox(height: 16),
                  _buildCart(),
                  const SizedBox(height: 16),
                  _buildPaymentMethod(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notlar',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildCustomerSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(_selectedCustomer?.name ?? 'Müşteri Seç'),
        subtitle: Text(_selectedCustomer?.phone ?? ''),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: () async {
          final customer = await showDialog<Customer>(
            context: context,
            builder: (context) => _CustomerDialog(customers: _customers),
          );
          if (customer != null) {
            setState(() => _selectedCustomer = customer);
          }
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ürünler',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _products.length,
          itemBuilder: (context, index) {
            final product = _products[index];
            return _buildProductCard(product);
          },
        ),
      ],
    );
  }

  Widget _buildProductCard(Product product) {
    final inCart = _cart.containsKey(product);
    return Card(
      color: inCart ? Colors.green.shade50 : null,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_cart.containsKey(product)) {
              _cart[product] = _cart[product]! + 1;
            } else {
              _cart[product] = 1;
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text('₺${product.price.toStringAsFixed(2)}'),
              Text('Stok: ${product.stock}',
                  style: const TextStyle(fontSize: 12)),
              if (inCart)
                Chip(
                  label: Text('${_cart[product]}'),
                  backgroundColor: Colors.green,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCart() {
    if (_cart.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sepet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._cart.entries.map((entry) {
          return ListTile(
            title: Text(entry.key.name),
            subtitle: Text('₺${entry.key.price} x ${entry.value}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    setState(() {
                      if (entry.value > 1) {
                        _cart[entry.key] = entry.value - 1;
                      } else {
                        _cart.remove(entry.key);
                      }
                    });
                  },
                ),
                Text('₺${(entry.key.price * entry.value).toStringAsFixed(2)}'),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    setState(() => _cart.remove(entry.key));
                  },
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildPaymentMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ödeme Yöntemi',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(
              child: RadioListTile(
                title: const Text('Nakit'),
                value: 'cash',
                groupValue: _paymentMethod,
                onChanged: (value) => setState(() => _paymentMethod = value!),
              ),
            ),
            Expanded(
              child: RadioListTile(
                title: const Text('Kart'),
                value: 'card',
                groupValue: _paymentMethod,
                onChanged: (value) => setState(() => _paymentMethod = value!),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Toplam'),
                Text(
                  '₺${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _createOrder,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Sipariş Oluştur'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createOrder() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen müşteri seçin')),
      );
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen ürün ekleyin')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final orderNumber = 'ORD${DateTime.now().millisecondsSinceEpoch}';
      final order = Order(
        orderNumber: orderNumber,
        customerId: _selectedCustomer!.id!,
        customerName: _selectedCustomer!.name,
        customerPhone: _selectedCustomer!.phone,
        total: _total,
        status: 'pending',
        paymentMethod: _paymentMethod,
        notes: _notesController.text,
        createdAt: DateTime.now().toIso8601String(),
      );

      final items = _cart.entries.map((entry) {
        return OrderItem(
          orderId: 0,
          productId: entry.key.id!,
          productName: entry.key.name,
          quantity: entry.value,
          price: entry.key.price,
          subtotal: entry.key.price * entry.value,
        );
      }).toList();

      await _orderService.create(order, items);

      // SMS gönder
      await _smsService.sendOrderSms(order, 'pending');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sipariş oluşturuldu!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

class _CustomerDialog extends StatelessWidget {
  final List<Customer> customers;

  const _CustomerDialog({required this.customers});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Müşteri Seç'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: customers.length,
          itemBuilder: (context, index) {
            final customer = customers[index];
            return ListTile(
              title: Text(customer.name),
              subtitle: Text(customer.phone),
              onTap: () => Navigator.pop(context, customer),
            );
          },
        ),
      ),
    );
  }
}
