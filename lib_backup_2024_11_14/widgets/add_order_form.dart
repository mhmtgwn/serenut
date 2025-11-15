import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../services/customer_service.dart';
import '../services/receipt_service.dart';
import 'package:intl/intl.dart';
import '../pages/customers.dart';
import '../pages/products.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'receipt_preview_dialog.dart';
import 'printer_selection_dialog.dart';

class AddOrderForm extends StatefulWidget {
  final Function? onOrderAdded;

  const AddOrderForm({Key? key, this.onOrderAdded}) : super(key: key);

  @override
  State<AddOrderForm> createState() => _AddOrderFormState();
}

class _AddOrderFormState extends State<AddOrderForm> {
  final _formKey = GlobalKey<FormState>();
  
  // Müşteri ve ürün listeleri
  List<Map<String, dynamic>> _products = [];
  bool _isLoadingCustomers = true;
  bool _isLoadingProducts = true;
  
  // Seçilen müşteri ve ürünler
  Map<String, dynamic>? _selectedCustomer;
  final List<Map<String, dynamic>> _selectedProducts = [];
  
  // Form alanları
  final TextEditingController _dateController = TextEditingController();
  final String _orderStatus = 'Bekliyor';
  final TextEditingController _notesController = TextEditingController();
  
  // Toplam tutar
  double _totalAmount = 0.0;
  
  // Ürün arama
  final TextEditingController _productSearchController = TextEditingController();
  
  // Ödeme alanı
  final TextEditingController _paymentController = TextEditingController();
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;
  
  // Fiş yazdırma
  final ReceiptService _receiptService = ReceiptService();
  bool _isPrinting = false;
  
  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _loadCustomers();
    _loadProducts();
  }
  
  @override
  void dispose() {
    _dateController.dispose();
    _notesController.dispose();
    _productSearchController.dispose();
    _paymentController.dispose();
    super.dispose();
  }
  
  // Müşterileri yükle
  Future<void> _loadCustomers() async {
    try {
      await CustomerService.instance.getAllCustomers();
      setState(() {
        _isLoadingCustomers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCustomers = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Müşteriler yüklenirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Ürünleri yükle
  Future<void> _loadProducts() async {
    try {
      final products = await ProductService.instance.getAllProducts();
      setState(() {
        _products = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingProducts = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ürünler yüklenirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Ürün ekleme diyaloğunu göster
  void _addProductToOrder(Map<String, dynamic> selectedProduct) {
    
    // Ürün fiyatını kontrol et
    final double price = selectedProduct['price'] is double 
        ? selectedProduct['price'] 
        : (selectedProduct['price'] is String 
            ? double.tryParse(selectedProduct['price']) ?? 0.0 
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

  // Ürün miktarını güncelle
  void _updateProductQuantity(int index, double quantity) {
    setState(() {
      final product = _selectedProducts[index];
      product['quantity'] = quantity;
      product['subtotal'] = quantity * (product['unitPrice'] ?? 0.0);
      _calculateTotal();
    });
  }

  // Ürün fiyatını güncelle
  void _updateProductPrice(int index, double price) {
    setState(() {
      final product = _selectedProducts[index];
      product['unitPrice'] = price;
      product['price'] = price;
      product['subtotal'] = price * (product['quantity'] ?? 1.0);
      _calculateTotal();
    });
  }
  
  // Toplam tutarı hesapla
  void _calculateTotal() {
    double total = 0.0;
    for (var product in _selectedProducts) {
      final subtotal = product['subtotal'] is double 
          ? product['subtotal'] 
          : (product['subtotal'] is String 
              ? double.tryParse(product['subtotal']) ?? 0.0 
              : 0.0);
      total += subtotal;
    }
    
    
    setState(() {
      _totalAmount = total;
      _remainingAmount = total - _paidAmount;
    });
  }
  
  // Ödeme tutarını güncelle
  void _updatePayment(String value) {
    
    final double amount = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    
    setState(() {
      _paidAmount = amount;
      _remainingAmount = _totalAmount - _paidAmount;
    });
  }

  /// Fiş yazdır
  Future<void> _printReceipt() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce bir müşteri seçin')),
      );
      return;
    }

    if (_selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir ürün ekleyin')),
      );
      return;
    }

    try {
      // İşletme bilgilerini al
      final prefs = await SharedPreferences.getInstance();
      final businessInfo = {
        'businessName': prefs.getString('business_name') ?? 'İŞLETME',
        'address': prefs.getString('address') ?? '',
        'phone': prefs.getString('phone') ?? '',
        'taxInfo': prefs.getString('tax_info') ?? '',
        'footerNote': prefs.getString('footer_note') ?? 'Teşekkür ederiz!',
      };

      // Geçici sipariş oluştur (henüz kaydedilmemiş)
      final tempOrder = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'customerId': _selectedCustomer!['id'],
        'customerName': _selectedCustomer!['name'],
        'customerPhone': _selectedCustomer!['phone'],
        'customerAddress': _selectedCustomer!['address'],
        'orderDate': _dateController.text,
        'totalAmount': _totalAmount,
        'paidAmount': _paidAmount,
        'remainingAmount': _remainingAmount,
        'orderStatus': _orderStatus,
        'paymentStatus': _remainingAmount > 0 ? 'Kısmi Ödeme' : 'Tam Ödeme',
        'paymentMethod': 'Nakit', // Varsayılan ödeme yöntemi
        'notes': _notesController.text,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // Müşteri bilgilerini al
      final customer = {
        'id': _selectedCustomer!['id'],
        'name': _selectedCustomer!['name'],
        'phone': _selectedCustomer!['phone'],
        'address': _selectedCustomer!['address'],
        'email': _selectedCustomer!['email'],
        'notes': _selectedCustomer!['notes'],
        'creditBalance': 0.0,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // Sipariş öğelerini oluştur
      final orderItems = _selectedProducts.map((product) => {
        'id': DateTime.now().millisecondsSinceEpoch + _selectedProducts.indexOf(product),
        'orderId': tempOrder['id'],
        'productId': product['id'],
        'productName': product['name'],
        'quantity': product['quantity'],
        'unitPrice': product['price'],
        'subtotal': product['price'] * product['quantity'],
      }).toList();

      // Fiş önizleme verilerini oluştur
      final receiptData = _receiptService.getReceiptPreview(
        order: tempOrder,
        customer: customer,
        items: orderItems,
        businessInfo: businessInfo,
      );

      // Önizleme göster
      final shouldPrint = await showDialog<bool>(
        context: context,
        builder: (context) => ReceiptPreviewDialog(receiptData: receiptData),
      );

      if (shouldPrint == true) {
        // Yazıcı seçimi yap
        final selectedPrinterId = await showPrinterSelectionDialog(context);
        
        if (selectedPrinterId == null) {
          // Kullanıcı yazıcı seçmedi
          return;
        }

        setState(() {
          _isPrinting = true;
        });

        // Seçilen yazıcı ile fişi yazdır
        final success = await _receiptService.printOrderReceiptWithPrinter(
          printerId: selectedPrinterId,
          order: tempOrder,
          customer: customer,
          items: orderItems,
          businessInfo: businessInfo,
        );

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fiş başarıyla yazdırıldı'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fiş yazdırılamadı. Yazıcı bağlantısını kontrol edin.'),
              backgroundColor: Colors.red,
            ),
          );
        }

        setState(() {
          _isPrinting = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fiş yazdırma hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // Siparişi kaydet
  Future<void> _saveOrder() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen en az bir ürün ekleyin'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Sipariş durumunu belirle
      String orderStatus = _selectedCustomer == null ? 'Satış' : _orderStatus;
      
      // Satış durumu kontrolü
      if (orderStatus == 'Satış') {
        // Satış durumu için ödeme kontrolü yap
        if (_paidAmount <= 0) {
          // Satış için ödeme yapılmamış, uyarı göster
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Satış işlemleri için ödeme tutarı girilmelidir'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        // Para üstü hesaplama (ödeme tutarı sipariş tutarından büyükse)
        double changeAmount = _paidAmount - _totalAmount;
        if (changeAmount > 0) {
          // Para üstü var, onay iste
          bool? shouldProceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Para Üstü Onayı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Satış Tutarı: ${_totalAmount.toStringAsFixed(2)} ₺'),
                  Text('Alınan Ödeme: ${_paidAmount.toStringAsFixed(2)} ₺'),
                  const Divider(),
                  Text(
                    'Para Üstü: ${changeAmount.toStringAsFixed(2)} ₺',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Onayla ve Kaydet'),
                ),
              ],
            ),
          );
          
          if (shouldProceed != true) {
            return; // Kullanıcı işlemi iptal etti
          }
        }
        else if (changeAmount < 0) {
          // Eksik ödeme var, uyarı göster
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Satış işlemlerinde tutarın tamamı ödenmelidir'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      
      try {
        // Ödeme durumunu belirle
        String paymentStatus = 'Bekliyor'; // Başlangıçta bekliyor olarak ayarla
        String paymentMethod = 'Nakit';
        
        if (orderStatus == 'Satış') {
          // Satış durumunda ödeme durumunu direk "Ödendi" yapabiliriz
          paymentStatus = 'Ödendi';
        }
        
        // Müşteri bilgileri
        final int? customerId = _selectedCustomer != null ? _selectedCustomer!['id'] : null;
        final String customerName = _selectedCustomer != null ? (_selectedCustomer!['displayName'] ?? _selectedCustomer!['name'] ?? '') : 'Genel Satış';
        final String customerPhone = _selectedCustomer != null ? (_selectedCustomer!['phone'] ?? '') : '';
        final String customerAddress = _selectedCustomer != null ? (_selectedCustomer!['address'] ?? '') : '';
        
        // Sipariş verilerini hazırla
        final order = {
          'customerId': customerId ?? 0,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'customerAddress': customerAddress,
          'orderDate': _dateController.text,
          'totalAmount': _totalAmount,
          'paidAmount': orderStatus == 'Satış' ? _totalAmount : 0.0, // Satış durumunda tutarın tamamı ödenmiş olarak kaydedilir
          'remainingAmount': orderStatus == 'Satış' ? 0.0 : _totalAmount, // Satış durumunda kalan tutar 0
          'orderStatus': orderStatus,
          'paymentStatus': orderStatus == 'Satış' ? 'Ödendi' : paymentStatus, // Satış durumunda ödeme durumu "Ödendi"
          'paymentMethod': paymentMethod,
          'notes': _notesController.text,
        };

        // Ürün verilerini hazırla
        final orderItems = _selectedProducts.map((product) {
          return {
            'productId': product['id'] ?? product['productId'],
            'productName': product['name'] ?? product['productName'],
            'quantity': product['quantity'],
            'unitPrice': product['unitPrice'],
            'subtotal': product['subtotal'],
          };
        }).toList();
        
        // Siparişi kaydet
        final orderId = await OrderService.instance.addOrderWithValidation(order, orderItems);
        
        // Eğer ödeme varsa ve Satış durumu DEĞİLSE bekleyen ödemelere ekle
        // (Satış durumunda zaten ödeme otomatik gerçekleşiyor)
        if (_paidAmount > 0 && orderStatus != 'Satış') {
          OrderService.instance.addPendingPayment(orderId, _paidAmount, paymentMethod);
          
          // Kullanıcıya ödeme onayı için sor
          if (mounted) {
            final shouldConfirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Ödemeyi Onayla'),
                content: Text('${_paidAmount.toStringAsFixed(2)} TL tutarında bir ödeme eklediniz. Bu ödemeyi onaylamak istiyor musunuz?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('İptal'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Onayla'),
                  ),
                ],
              ),
            ) ?? false;
            
            if (shouldConfirm) {
              final success = await OrderService.instance.confirmPendingPayments(orderId);
              if (success) {
                // Ödeme başarıyla onaylandı
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ödeme onaylanırken bir sorun oluştu. Daha sonra tekrar deneyebilirsiniz.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            } else {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ödeme onaylanmadı. Daha sonra sipariş detaylarından onaylayabilirsiniz.'),
                  backgroundColor: Colors.blue,
                ),
              );
            }
          }
        }
        
        // Başarı mesajı ve para üstü bilgisi
        String successMessage = 'Sipariş başarıyla oluşturuldu';
        
        // Satış durumunda para üstü bilgisi ekle
        if (orderStatus == 'Satış' && _paidAmount > _totalAmount) {
          double changeAmount = _paidAmount - _totalAmount;
          successMessage = 'Satış başarıyla kaydedildi. Para üstü: ${changeAmount.toStringAsFixed(2)} ₺';
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage),
              backgroundColor: Colors.green,
            ),
          );
          
          // Callback fonksiyonunu çağır
          if (widget.onOrderAdded != null) {
            widget.onOrderAdded!();
          }
          
          // Formu kapat
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
  }
  
  // Barkod okuma fonksiyonu
  Future<void> _scanBarcode() async {
    try {
      final MobileScannerController controller = MobileScannerController();
      
      final barcodeResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Barkod Tara'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.flip_camera_ios),
                  onPressed: () => controller.switchCamera(),
                ),
              ],
            ),
            body: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String code = barcodes.first.rawValue ?? '';
                  if (code.isNotEmpty) {
                    Navigator.pop(context, code);
                  }
                }
              },
            ),
          ),
        ),
      );
      
      if (!mounted) return;
      
      if (barcodeResult != null) {
        // Barkod ile ürün ara
        final product = _products.firstWhere(
          (product) => product['barcode'] == barcodeResult,
          orElse: () => {},
        );
        
        if (product.isNotEmpty) {
          _addProductToOrder(product);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Barkod ile ürün bulunamadı: $barcodeResult'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barkod okuma işlemi başarısız oldu: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    // Temalandırma renkleri
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final secondaryTextColor = isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700;
    final cardColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    final borderColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300;
    final dividerColor = isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300;
    
    // Sipariş durumu seçimi
    if (_selectedCustomer == null || _selectedCustomer!['id'] == null || _selectedCustomer!['id'] == 0) {
      // Satış durumu için özel işlemler
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Sipariş'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Müşteri seçimi
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Müşteri Bilgileri',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: textColor,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _isLoadingCustomers
                        ? const Center(child: CircularProgressIndicator())
                        : InkWell(
                            onTap: () async {
                              final selectedCustomer = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CustomersContent(
                                    isSelectionMode: true,
                                  ),
                                ),
                              );
                              
                              if (selectedCustomer != null) {
                                setState(() {
                                  _selectedCustomer = selectedCustomer;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Müşteri',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                prefixIcon: Icon(
                                  Icons.person_outline,
                                  color: secondaryTextColor,
                                ),
                                suffixIcon: Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: secondaryTextColor,
                                ),
                                labelStyle: TextStyle(color: secondaryTextColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _selectedCustomer == null
                                      ? Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              size: 16,
                                              color: isDarkMode ? AppTheme.primaryColor : Colors.orange,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Müşteri seçin',
                                              style: TextStyle(
                                                color: isDarkMode ? AppTheme.primaryColor : Colors.orange,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          _selectedCustomer!['displayName'] ?? '',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: textColor,
                                          ),
                                        ),
                                  if (_selectedCustomer != null && _selectedCustomer!['phone'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Row(
                                        children: [
                                          Icon(Icons.phone, size: 16, color: secondaryTextColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            _selectedCustomer!['phone'],
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              
              // Ürün ekleme ve barkod okuma butonları
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ürün İşlemleri',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: textColor,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          // Ürün ekleme butonu
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoadingProducts ? null : () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProductsPage(
                                      isSelectionMode: true,
                                      onProductSelected: (selectedProduct) {
                                        _addProductToOrder(selectedProduct);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ),
                                );
                                
                                // Eğer result ile dönüş yapılırsa (eski yöntem)
                                if (result != null) {
                                  _addProductToOrder(result);
                                }
                              },
                              icon: const Icon(Icons.add_shopping_cart),
                              label: const Text('Ürün Ekle'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Barkod okuma butonu
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoadingProducts ? null : _scanBarcode,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Barkod Oku'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // Ürün listesi
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sipariş Ürünleri',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: textColor,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _isLoadingProducts
                        ? const Center(child: CircularProgressIndicator())
                        : _selectedProducts.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'Henüz ürün eklenmedi',
                                    style: TextStyle(color: secondaryTextColor),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _selectedProducts.length,
                                itemBuilder: (context, index) {
                                  final product = _selectedProducts[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    color: isDarkMode ? AppTheme.darkSurfaceColor : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(color: borderColor, width: 0.5),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      product['productName'] ?? 'İsimsiz Ürün',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: TextFormField(
                                                            decoration: InputDecoration(
                                                              labelText: 'Miktar',
                                                              border: OutlineInputBorder(
                                                                borderSide: BorderSide(color: borderColor),
                                                              ),
                                                              enabledBorder: OutlineInputBorder(
                                                                borderSide: BorderSide(color: borderColor),
                                                              ),
                                                              labelStyle: TextStyle(color: secondaryTextColor),
                                                            ),
                                                            style: TextStyle(color: textColor),
                                                            keyboardType: TextInputType.number,
                                                            initialValue: product['quantity'].toString(),
                                                            onChanged: (value) {
                                                              _updateProductQuantity(
                                                                index,
                                                                double.tryParse(value) ?? 1.0,
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: TextFormField(
                                                            decoration: InputDecoration(
                                                              labelText: 'Birim Fiyat (TL)',
                                                              border: OutlineInputBorder(
                                                                borderSide: BorderSide(color: borderColor),
                                                              ),
                                                              enabledBorder: OutlineInputBorder(
                                                                borderSide: BorderSide(color: borderColor),
                                                              ),
                                                              labelStyle: TextStyle(color: secondaryTextColor),
                                                            ),
                                                            style: TextStyle(color: textColor),
                                                            keyboardType: TextInputType.number,
                                                            initialValue: product['unitPrice'].toString(),
                                                            onChanged: (value) {
                                                              _updateProductPrice(
                                                                index,
                                                                double.tryParse(value) ?? 0.0,
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.delete_outline, color: isDarkMode ? Colors.red[300] : Colors.red),
                                                onPressed: () {
                                                  setState(() {
                                                    _selectedProducts.removeAt(index);
                                                    _calculateTotal();
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isDarkMode 
                                                ? AppTheme.primaryColor.withAlpha(13005)
                                                : AppTheme.primaryColor.withAlpha(6630),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Toplam:',
                                                  style: TextStyle(color: textColor),
                                                ),
                                                Text(
                                                  '${product['subtotal'].toStringAsFixed(2)} TL',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: textColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      if (_selectedProducts.isNotEmpty) ...[
                        Divider(color: dividerColor),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Toplam Tutar:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                '${_totalAmount.toStringAsFixed(2)} TL',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Ödeme alanı
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ödeme Bilgileri',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: textColor,
                            ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _paymentController,
                        decoration: InputDecoration(
                          labelText: 'Ödeme Tutarı (TL)',
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: borderColor),
                          ),
                          prefixIcon: Icon(Icons.payments, color: secondaryTextColor),
                          labelStyle: TextStyle(color: secondaryTextColor),
                        ),
                        style: TextStyle(color: textColor),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        onChanged: _updatePayment,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                            ? (_remainingAmount > 0 ? Colors.orange.withAlpha(51) : Colors.green.withAlpha(51))
                            : (_remainingAmount > 0 ? Colors.orange.withAlpha(26) : Colors.green.withAlpha(26)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Kalan Tutar:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _remainingAmount > 0 
                                  ? (isDarkMode ? Colors.orange[300] : Colors.orange[700])
                                  : (isDarkMode ? Colors.green[300] : Colors.green[700]),
                              ),
                            ),
                            Text(
                              '${_remainingAmount.toStringAsFixed(2)} TL',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _remainingAmount > 0 
                                  ? (isDarkMode ? Colors.orange[300] : Colors.orange[700])
                                  : (isDarkMode ? Colors.green[300] : Colors.green[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Notlar
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notlar',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: textColor,
                            ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          labelText: 'Sipariş Notları',
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: borderColor),
                          ),
                          prefixIcon: Icon(Icons.note, color: secondaryTextColor),
                          labelStyle: TextStyle(color: secondaryTextColor),
                        ),
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Butonlar
              SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    // Fiş yazdır butonu
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _isPrinting ? null : _printReceipt,
                          icon: _isPrinting 
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.print),
                          label: Text(_isPrinting ? 'Yazdırılıyor...' : 'Fiş Yazdır'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Kaydet butonu
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _saveOrder,
                          icon: const Icon(Icons.save),
                          label: const Text('Siparişi Kaydet'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 
