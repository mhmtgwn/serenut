import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/datasources/order_service.dart';
import '../../data/datasources/customer_service.dart';
import '../../shared/constants/app_theme.dart';
import '../pages/customers.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../shared/constants/theme_provider.dart';

class EditOrderForm extends StatefulWidget {
  final int orderId;
  final Function? onOrderUpdated;

  const EditOrderForm({
    Key? key,
    required this.orderId,
    this.onOrderUpdated,
  }) : super(key: key);

  @override
  State<EditOrderForm> createState() => _EditOrderFormState();
}

class _EditOrderFormState extends State<EditOrderForm> {
  final _formKey = GlobalKey<FormState>();
  
  // Sipariş verileri
  List<Map<String, dynamic>> _orderItems = [];
  List<Map<String, dynamic>> _paymentHistory = [];
  
  // Müşteri bilgileri
  Map<String, dynamic>? _selectedCustomer;
  
  // Form alanları
  final TextEditingController _dateController = TextEditingController();
  String _orderStatus = 'Bekliyor';
  final TextEditingController _notesController = TextEditingController();
  
  // Toplam tutar
  double _totalAmount = 0.0;
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;
  String _paymentStatus = 'Ödenmedi';
  
  // Ödeme alanı
  final TextEditingController _paymentController = TextEditingController();
  String _paymentMethod = 'Nakit';
  
  // Yükleme durumu
  bool _isLoading = true;
  bool _isSaving = false;
  
  // Sipariş durumu seçenekleri
  final List<String> _orderStatusOptions = ['Bekliyor', 'Hazırlanıyor', 'Tamamlandı', 'Teslim Edildi', 'Satış'];
  
  // Ödeme yöntemi seçenekleri
  final List<String> _paymentMethodOptions = ['Nakit', 'Banka/Kredi Kartı', 'Havale/EFT', 'Diğer'];
  
  @override
  void initState() {
    super.initState();
    _loadOrderData();
  }
  
  // Sipariş verilerini yükle
  Future<void> _loadOrderData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Sipariş verilerini getir
      final orderService = OrderService.instance;
      final orderData = await orderService.getOrder(widget.orderId);
      
      if (orderData != null && mounted) {
        setState(() {
          // Sipariş öğelerini ayarla
          if (orderData.containsKey('items')) {
            _orderItems = List<Map<String, dynamic>>.from(orderData['items']);
          }
          
          // Müşteri bilgilerini ayarla
          _selectedCustomer = {
            'id': orderData['customerId'],
            'displayName': orderData['customerName'],
            'phone': orderData['customerPhone'],
            'address': orderData['customerAddress'],
          };
          
          // Sipariş bilgilerini ayarla
          _dateController.text = orderData['orderDate'] ?? '';
          _orderStatus = orderData['orderStatus'] ?? 'Bekliyor';
          _notesController.text = orderData['notes'] ?? '';
          
          // Tutar bilgilerini ayarla
          _totalAmount = orderData['totalAmount'] ?? 0.0;
          _paidAmount = orderData['paidAmount'] ?? 0.0;
          _remainingAmount = orderData['remainingAmount'] ?? 0.0;
          _paymentStatus = orderData['paymentStatus'] ?? 'Ödenmedi';
          
          // Ödeme yöntemini ayarla
          _paymentMethod = orderData['paymentMethod'] ?? 'Nakit';
          
          _isLoading = false;
        });
        
        // Ödeme geçmişini yükle
        _loadPaymentHistory();
      }
    } catch (e) {
      debugPrint('Sipariş verilerini yüklerken hata: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sipariş verilerini yüklerken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Ödeme geçmişini yükle
  Future<void> _loadPaymentHistory() async {
    if (!mounted) return;
    
    try {
      final orderService = OrderService.instance;
      // final payments = await OrderService.instance.getPaymentHistory(widget.orderId); // Method eksik - geçici comment
      
      if (mounted) {
        setState(() {
          _paymentHistory = []; // payments;
        });
      }
    } catch (e) {
      debugPrint('Ödeme geçmişini yüklerken hata: $e');
    }
  }

  // Siparişi güncelle
  Future<void> _updateOrder() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Satış durumu kontrolü
    if (_orderStatus == 'Satış') {
      // Yeni ödeme miktarını kontrol et
      final String paymentText = _paymentController.text.trim();
      double newPayment = 0.0;
      
      if (paymentText.isNotEmpty) {
        newPayment = double.tryParse(paymentText.replaceAll(',', '.')) ?? 0.0;
      }
      
      final double totalPaid = _paidAmount + newPayment;
      
      // Eğer toplam ödeme hala toplam tutardan azsa
      if (totalPaid < _totalAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Satış işlemlerinde tutarın tamamı ödenmelidir'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Para üstü hesaplama (ödeme tutarı sipariş tutarından büyükse)
      double changeAmount = totalPaid - _totalAmount;
      if (changeAmount > 0 && newPayment > 0) {
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
                Text('Toplam Ödenen: ${totalPaid.toStringAsFixed(2)} ₺'),
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
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Satış durumunda otomatik olarak tüm tutarı ödenmiş yap
      if (_orderStatus == 'Satış') {
        _paidAmount = _totalAmount;
        _remainingAmount = 0.0;
        _paymentStatus = 'Ödendi';
      }
      
      // Sipariş verilerini hazırla
      final orderData = {
        'id': widget.orderId,
        'customerId': _selectedCustomer?['id'],
        'customerName': _selectedCustomer?['displayName'],
        'customerPhone': _selectedCustomer?['phone'],
        'customerAddress': _selectedCustomer?['address'],
        'orderDate': _dateController.text,
        'orderStatus': _orderStatus,
        'totalAmount': _totalAmount,
        'paidAmount': _paidAmount,
        'remainingAmount': _remainingAmount,
        'paymentStatus': _orderStatus == 'Satış' ? 'Ödendi' : _paymentStatus,
        'paymentMethod': _paymentMethod,
        'notes': _notesController.text,
      };
      
      // Siparişi güncelle
      await OrderService.instance.updateOrder(orderData, _orderItems);
      
      // Yeni ödeme eklediyse ve sipariş "Satış" ise otomatik ödeme kaydı oluştur
      final String paymentText = _paymentController.text.trim();
      if (paymentText.isNotEmpty && _orderStatus == 'Satış') {
        final double newPayment = double.tryParse(paymentText.replaceAll(',', '.')) ?? 0.0;
        if (newPayment > 0) {
          // Bekleyen ödeme ekle
          // OrderService.instance.addPendingPayment(widget.orderId, newPayment, _paymentMethod); // Method eksik
          // Ödemeyi hemen onayla
          // await OrderService.instance.confirmPendingPayments(widget.orderId); // Method eksik
          _paymentController.clear(); // Ödeme alanını temizle
        }
      }
      
      // Başarı mesajı ve para üstü bilgisi
      String successMessage = 'Sipariş başarıyla güncellendi';
      
      // Satış durumunda para üstü bilgisi ekle
      if (_orderStatus == 'Satış' && paymentText.isNotEmpty) {
        final double newPayment = double.tryParse(paymentText.replaceAll(',', '.')) ?? 0.0;
        if (newPayment > _totalAmount) {
          final double changeAmount = newPayment - _totalAmount;
          successMessage = 'Satış başarıyla güncellendi. Para üstü: ${changeAmount.toStringAsFixed(2)} ₺';
        }
      }
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
      
      // Callback fonksiyonunu çağır
      if (widget.onOrderUpdated != null) {
        widget.onOrderUpdated!();
      }
      
      Navigator.pop(context);
      
    } catch (e) {
      debugPrint('Sipariş güncellenirken hata: $e');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sipariş güncellenirken hata oluştu: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
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
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Müşteri bilgileri
          Card(
            margin: EdgeInsets.zero,
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: borderColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        color: secondaryTextColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Müşteri Bilgileri',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Müşteri: ${_selectedCustomer?['displayName'] ?? 'Belirtilmemiş'}',
                    style: TextStyle(
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Telefon: ${_selectedCustomer?['phone'] ?? 'Belirtilmemiş'}',
                    style: TextStyle(
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Sipariş bilgileri
          Card(
            margin: EdgeInsets.zero,
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: borderColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_bag,
                        color: secondaryTextColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Sipariş Bilgileri',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Tarih
                  TextFormField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      labelText: 'Tarih',
                      hintText: 'DD/MM/YYYY',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen tarih girin';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Durum seçimi
                  DropdownButtonFormField<String>(
                    value: _orderStatus,
                    decoration: const InputDecoration(
                      labelText: 'Sipariş Durumu',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.article),
                    ),
                    items: _orderStatusOptions.map((String status) {
                      return DropdownMenuItem<String>(
                        value: status,
                        child: Text(status),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _orderStatus = newValue;
                        });
                      }
                    },
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
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Sipariş öğeleri
          Card(
            margin: EdgeInsets.zero,
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: borderColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_cart,
                        color: secondaryTextColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Ürünler',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          // Ürün ekleme fonksiyonu
                        },
                        tooltip: 'Ürün Ekle',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Ürün listesi
                  _orderItems.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('Henüz ürün eklenmemiş'),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _orderItems.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final item = _orderItems[index];
                            return ListTile(
                              title: Text(item['productName'] ?? 'Ürün'),
                              subtitle: Text('${item['quantity'] ?? 0} x ${item['price'] ?? 0} TL'),
                              trailing: Text('${((item['quantity'] ?? 0) * (item['price'] ?? 0)).toStringAsFixed(2)} TL'),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Ödeme bilgileri
          Card(
            margin: EdgeInsets.zero,
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: borderColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.payments,
                        color: secondaryTextColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Ödeme Bilgileri',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Ödeme özetleri
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Toplam Tutar',
                              style: TextStyle(
                                color: secondaryTextColor,
                              ),
                            ),
                            Text(
                              '${_totalAmount.toStringAsFixed(2)} TL',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ödenen Tutar',
                              style: TextStyle(
                                color: secondaryTextColor,
                              ),
                            ),
                            Text(
                              '${_paidAmount.toStringAsFixed(2)} TL',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kalan Tutar',
                              style: TextStyle(
                                color: secondaryTextColor,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _remainingAmount > 0
                                    ? (isDarkMode ? Colors.orange.withAlpha(51) : Colors.orange.withAlpha(26))
                                    : (isDarkMode ? Colors.green.withAlpha(51) : Colors.green.withAlpha(26)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_remainingAmount.toStringAsFixed(2)} TL',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _remainingAmount > 0
                                      ? (isDarkMode ? Colors.orange[300] : Colors.orange[700])
                                      : (isDarkMode ? Colors.green[300] : Colors.green[700]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Yeni ödeme ekleme
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _paymentController,
                          decoration: const InputDecoration(
                            labelText: 'Ödeme Tutarı',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Ödeme Yöntemi',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.payment),
                          ),
                          items: _paymentMethodOptions.map((String method) {
                            return DropdownMenuItem<String>(
                              value: method,
                              child: Text(method),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _paymentMethod = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Ödeme ekle butonu
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Ödeme ekleme fonksiyonu
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Ödeme Ekle'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: AppTheme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Ödeme geçmişi
                  Text(
                    'Ödeme Geçmişi',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  _paymentHistory.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('Henüz ödeme yapılmamış'),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _paymentHistory.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final payment = _paymentHistory[index];
                            final date = payment['date'] ?? DateTime.now();
                            final formattedDate = '${date.day}/${date.month}/${date.year}';
                            
                            return ListTile(
                              title: Text('${payment['amount']?.toStringAsFixed(2) ?? '0.00'} TL'),
                              subtitle: Text('${payment['method'] ?? 'Nakit'} - $formattedDate'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  // Ödeme silme fonksiyonu
                                },
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Kaydet butonu
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _updateOrder,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Siparişi Güncelle',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 