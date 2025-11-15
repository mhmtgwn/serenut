import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/datasources/order_service.dart';
import '../../data/datasources/order_receipt_service.dart';
import '../../data/datasources/database_service.dart';
import '../../data/datasources/bluetooth_service.dart';
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import '../pages/customers.dart';
import '../pages/products.dart';
import 'order/selected_products_list.dart';
import 'order/payment_section.dart';

class AddOrderForm extends StatefulWidget {
  final Function? onOrderAdded;

  const AddOrderForm({Key? key, this.onOrderAdded}) : super(key: key);

  @override
  State<AddOrderForm> createState() => _AddOrderFormState();
}

class _AddOrderFormState extends State<AddOrderForm> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _paymentController = TextEditingController();

  // State variables
  Map<String, dynamic>? _selectedCustomer;
  List<Map<String, dynamic>> _selectedProducts = [];

  // Calculations
  double _totalAmount = 0.0;
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  void _updateProductQuantity(int index, double quantity) {
    setState(() {
      _selectedProducts[index]['quantity'] = quantity;
      _selectedProducts[index]['subtotal'] =
          quantity * _selectedProducts[index]['unitPrice'];
      _calculateTotal();
    });
  }

  void _removeProduct(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    double total = 0.0;
    for (var product in _selectedProducts) {
      total += product['subtotal'] ?? 0.0;
    }
    setState(() {
      _totalAmount = total;
      _remainingAmount = _totalAmount - _paidAmount;
    });
  }

  void _onPaymentChanged(double payment) {
    setState(() {
      _paidAmount = payment;
      _remainingAmount = _totalAmount - _paidAmount;
    });
  }

  Future<void> _saveOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen en az bir ürün seçin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final orderData = {
        'customerId': _selectedCustomer?['id'],
        'customerName': _selectedCustomer?['displayName'] ?? 'Misafir',
        'orderDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'totalAmount': _totalAmount,
        'paidAmount': _paidAmount,
        'remainingAmount': _remainingAmount,
        'orderStatus': _remainingAmount <= 0 ? 'Tamamlandı' : 'Bekliyor',
        'paymentStatus': _remainingAmount <= 0 ? 'Ödendi' : 'Bekliyor',
        'paymentMethod': 'Nakit',
        'notes': _notesController.text,
      };

      await OrderService.instance.addOrderWithValidation(
        orderData,
        _selectedProducts,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sipariş başarıyla kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );

        widget.onOrderAdded?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sipariş kaydedilirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _printReceipt() async {
    if (_selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen en az bir ürün seçin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Fiş yazıcısını bul
      final devices = await DatabaseService.instance.getAllDevices();
      final receiptPrinters = devices
          .where(
            (d) => d['isReceiptPrinter'] == 1,
          )
          .toList();

      if (receiptPrinters.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Fiş yazıcısı bulunamadı. Lütfen aygıt ayarlarından bir yazıcıyı fiş yazıcısı olarak işaretleyin.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // İlk fiş yazıcısını kullan
      final printerDevice = receiptPrinters.first;

      // Bluetooth yazıcıysa bağlantıyı kontrol et ve gerekirse bağlan
      if (printerDevice['connection'] == 'bluetooth') {
        final isConnected = BluetoothService.instance.isConnected;

        if (!isConnected) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('${printerDevice['name']} yazıcısına bağlanılıyor...'),
                backgroundColor: Colors.blue,
              ),
            );
          }

          // BluetoothDevice nesnesi oluştur
          final bluetoothDevice = BluetoothDevice(
            printerDevice['name'] ?? 'Yazıcı',
            printerDevice['bluetoothAddress'],
          );

          // Bağlan
          final success =
              await BluetoothService.instance.connect(bluetoothDevice);

          if (!success) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Yazıcıya bağlanılamadı'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${printerDevice['name']} bağlantısı başarılı'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }

      // Sipariş numarası oluştur
      final orderNumber =
          'SIP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      // Ürünleri OrderItem formatına çevir
      final items = _selectedProducts
          .map((p) => OrderItem(
                name: p['productName'] ?? 'Ürün',
                quantity: p['quantity'] ?? 1.0,
                price: p['unitPrice'] ?? 0.0,
                total: p['subtotal'] ?? 0.0,
              ))
          .toList();

      // Fiş yazdır
      final success = await OrderReceiptService.instance.printOrderReceipt(
        connection: printerDevice['connection'] ?? 'bluetooth',
        address: printerDevice['bluetoothAddress'],
        protocol: printerDevice['protocol'] ?? 'esc_pos',
        paperWidth: printerDevice['paperWidth'] ?? 58,
        printLogo: true,
        companyName: 'SHAMAN POS',
        companyAddress: 'İstanbul, Türkiye',
        companyPhone: '0555 123 45 67',
        customerName: _selectedCustomer?['displayName'],
        customerPhone: _selectedCustomer?['phone'],
        customerAddress: _selectedCustomer?['address'],
        orderNumber: orderNumber,
        orderDate: DateTime.now(),
        items: items,
        subtotal: _totalAmount,
        discount: 0.0,
        tax: 0.0,
        total: _totalAmount,
        payment: _paidAmount,
        remaining: _remainingAmount,
        thankYouMessage: 'Bizi tercih ettiğiniz için teşekkürler!',
        printBarcode: true,
        printQRCode: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(success ? 'Fiş yazdırılıyor...' : 'Fiş yazdırılamadı'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fiş yazdırma hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Sipariş'),
        actions: [
          TextButton(
            onPressed: _saveOrder,
            child: const Text(
              'Kaydet',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: _printReceipt,
            child: const Text(
              'Fiş Yazdır',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Müşteri ve Ürün Seçimi - Icon Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Müşteri Seçimi
                    Column(
                      children: [
                        IconButton(
                          onPressed: () {
                            // Müşteri seçim sayfasına git
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CustomersContent(
                                    isSelectionMode: true),
                              ),
                            ).then((selectedCustomer) {
                              if (selectedCustomer != null) {
                                setState(() {
                                  _selectedCustomer = selectedCustomer;
                                });
                              }
                            });
                          },
                          icon: const Icon(Icons.person_add, size: 32),
                          color: _selectedCustomer != null
                              ? Colors.green
                              : Colors.blue,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Müşteri',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    // Ürün Seçimi
                    Column(
                      children: [
                        IconButton(
                          onPressed: () {
                            // Ürün seçim sayfasına git
                            Navigator.push<Map<String, dynamic>>(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ProductsContent(
                                    isSelectionMode: true),
                              ),
                            ).then((selectedProduct) {
                              if (selectedProduct != null) {
                                final double price =
                                    selectedProduct['price'] is double
                                        ? selectedProduct['price']
                                        : (selectedProduct['price'] is String
                                            ? double.tryParse(
                                                    selectedProduct['price']) ??
                                                0.0
                                            : 0.0);

                                setState(() {
                                  final productItem = {
                                    'id': selectedProduct['id'],
                                    'productId': selectedProduct['id'],
                                    'name': selectedProduct['name'],
                                    'productName': selectedProduct['name'],
                                    'quantity': 1.0,
                                    'unitPrice': price,
                                    'price': price,
                                    'subtotal': price,
                                  };

                                  _selectedProducts.add(productItem);
                                  _calculateTotal();
                                });
                              }
                            });
                          },
                          icon: const Icon(Icons.shopping_cart_checkout,
                              size: 32),
                          color: _selectedProducts.isNotEmpty
                              ? Colors.green
                              : Colors.blue,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ürün',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    // Barkod/QR Tarama
                    Column(
                      children: [
                        IconButton(
                          onPressed: () {
                            // Barkod/QR tarama
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Barkod/QR tarama özelliği yakında'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.qr_code_scanner, size: 32),
                          color: Colors.purple,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Barkod',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Seçilen Müşteri Bilgisi
              if (_selectedCustomer != null)
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
                            const Text(
                              'Müşteri:',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              _selectedCustomer!['displayName'] ?? 'İsimsiz',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedCustomer = null;
                          });
                        },
                        icon: const Icon(Icons.close, color: Colors.red),
                        iconSize: 20,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Seçilen ürünler
              SelectedProductsList(
                selectedProducts: _selectedProducts,
                onQuantityChanged: _updateProductQuantity,
                onProductRemoved: _removeProduct,
                totalAmount: _totalAmount,
              ),
              const SizedBox(height: 16),

              // Ödeme bilgileri
              PaymentSection(
                paymentController: _paymentController,
                totalAmount: _totalAmount,
                paidAmount: _paidAmount,
                remainingAmount: _remainingAmount,
                onPaymentChanged: _onPaymentChanged,
              ),
              const SizedBox(height: 16),

              // Notlar
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notlar',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Buton Grubu
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveOrder,
                      icon: const Icon(Icons.save),
                      label: const Text('Sipariş Kaydet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _printReceipt,
                      icon: const Icon(Icons.print),
                      label: const Text('Fiş Yazdır'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
