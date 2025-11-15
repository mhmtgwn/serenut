import 'package:flutter/material.dart';
import '../widgets/add_order_form.dart';
import '../../data/datasources/order_service.dart';
import '../widgets/edit_order_form.dart';
import '../../data/datasources/customer_service.dart';
import '../../shared/constants/app_theme.dart';
import 'package:provider/provider.dart';
// ImageFilter için gerekli import
import '../../shared/constants/theme_provider.dart';
// Removed unnecessary import: dart:ui

class OrdersContent extends StatefulWidget {
  const OrdersContent({Key? key}) : super(key: key);

  @override
  State<OrdersContent> createState() => OrdersContentState();
}

class OrdersContentState extends State<OrdersContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  // Public erişim için getter
  TextEditingController get searchController => _searchController;
  
  // Sipariş durumu seçenekleri
  final List<String> _orderStatusOptions = ['Bekliyor', 'Hazırlanıyor', 'Tamamlandı', 'Teslim Edildi', 'Satış'];
  
  // Sipariş listesi
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filteredOrders = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      // Set loading state
    });
    
    try {
      final orders = await OrderService.instance.getAllOrders();
      
      setState(() {
        _orders = orders;
        _filterOrders(_searchQuery);
      });
    } catch (e) {
      
      setState(() {
        // Handle error state
      });
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Siparişler yüklenirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Arama sorgusuna göre siparişleri filtrele
  void _filterOrders(String query) {
    setState(() {
      _searchQuery = query;
      
      if (query.isEmpty) {
        _filteredOrders = List.from(_orders);
      } else {
        _filteredOrders = _orders.where((order) {
          final customerName = order['customerName']?.toString().toLowerCase() ?? '';
          final orderStatus = order['orderStatus']?.toString().toLowerCase() ?? '';
          final orderId = order['id']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();
          
          return customerName.contains(searchLower) || 
                 orderStatus.contains(searchLower) ||
                 orderId.contains(searchLower);
        }).toList();
      }
    });
  }

  // Sipariş durumuna göre filtrele
  List<Map<String, dynamic>> _getOrdersByStatus(String status) {
    return _filteredOrders.where((order) => 
      order['orderStatus']?.toString() == status
    ).toList();
  }

  // Format date function removed as it was unused

  void _showAddOrderDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => AddOrderForm(
          onOrderAdded: () {
            _loadOrders();
          },
        ),
      ),
    );
  }

  void _showEditOrderForm(Map<String, dynamic> order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditOrderForm(
          orderId: order['id'],
          onOrderUpdated: () {
            _loadOrders();
          },
        ),
      ),
    );
  }

  // Delete confirmation dialog removed as it was unused


  // Barkod okuma metodu
  void _scanBarcode() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Barkod tarama özelliği yakında eklenecek'),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackgroundColor : Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              // Tab Bar
              Container(
                color: isDarkMode ? AppTheme.darkSurfaceColor : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  labelColor: AppTheme.primaryColor,
                  unselectedLabelColor: isDarkMode ? Colors.white60 : Colors.black54,
                  indicatorColor: AppTheme.primaryColor,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
                  indicator: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.primaryColor,
                        width: 3,
                      ),
                    ),
                  ),
                  tabs: [
                    _buildTab('Bekliyor', Icons.hourglass_empty),
                    _buildTab('Hazır', Icons.pending_actions),
                    _buildTab('Tamam', Icons.check_circle_outline),
                    _buildTab('Teslim', Icons.local_shipping_outlined),
                    _buildTab('Satış', Icons.shopping_cart_outlined),
                  ],
                ),
              ),
              
              // Tab Bar View
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _orderStatusOptions.map((status) => _buildOrderList(status)).toList(),
                ),
              ),
            ],
          ),
          
          // Alt kısımdaki arama kutusu ve butonlar - NavBar'a taşındığı için kaldırıyoruz
        ],
      ),
    );
  }

  // Tab widget'ı oluşturan yardımcı metod
  Widget _buildTab(String label, IconData icon) {
    final int currentIndex = _tabController.index;
    final int tabIndex = _orderStatusOptions.indexOf(label);
    final bool isSelected = currentIndex == tabIndex;
    
    final Color activeColor = AppTheme.primaryColor;
    final Color inactiveColor = Theme.of(context).brightness == Brightness.dark 
        ? Colors.white60 
        : Colors.black54;
    
    return Tab(
      height: 60,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 22,
            color: isSelected ? activeColor : inactiveColor,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? activeColor : inactiveColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(String status) {
    final filteredOrders = _getOrdersByStatus(status);
    
    return filteredOrders.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey.shade600
                      : Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  '$status durumunda sipariş bulunamadı',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80), // Alt kısımda arama kutusu için boşluk bırak
            itemCount: filteredOrders.length,
            itemBuilder: (context, index) {
              final order = filteredOrders[index];
              return _buildOrderCard(order);
            },
          );
  }
  
  // Sipariş kartı widget'ı
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    
    // Müşteri ID'sini al
    final customerId = order['customerId'];
    
    // Sipariş öğelerini al
    final orderItems = order['items'] != null 
        ? List<Map<String, dynamic>>.from(order['items'])
        : <Map<String, dynamic>>[];
    
    // Sipariş durumu
    final status = order['orderStatus'] ?? 'Bekliyor';
    
    // Tutarları formatla
    String formatCurrency(double amount) {
      if (amount == amount.toInt()) {
        // Eğer tam sayı ise (örn: 100.0), sadece tam kısmı göster
        return '${amount.toInt()} ₺';
      } else {
        // Ondalık kısmı varsa, 2 basamak göster
        return '${amount.toStringAsFixed(2)} ₺';
      }
    }
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: 1,
          ),
        ),
        color: backgroundColor,
        child: InkWell(
          onTap: () => _showOrderDetails(order),
          onLongPress: () => _showOrderDeleteDialog(order),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst kısım: Sipariş numarası, tarih ve durum
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sipariş numarası ve tarih
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDarkMode 
                                ? AppTheme.primaryColor.withAlpha(51)
                                : AppTheme.accentColor.withAlpha(51),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#${order['id'] ?? ''}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDarkMode 
                                  ? AppTheme.primaryColor
                                  : AppTheme.secondaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: isDarkMode 
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              order['orderDate'] ?? '',
                              style: TextStyle(
                                color: isDarkMode 
                                    ? Colors.grey.shade300
                                    : Colors.grey[700],
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    // Durum göstergesi
                    InkWell(
                      onTap: () => _showStatusChangeDialog(order),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDarkMode 
                              ? getStatusColor(status).withAlpha(38)
                              : getStatusColor(status).withAlpha(38),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDarkMode 
                                ? getStatusColor(status).withAlpha(77)
                                : getStatusColor(status).withAlpha(77),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode 
                                    ? getStatusColor(status)
                                    : getStatusColor(status),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: isDarkMode 
                                  ? getStatusColor(status)
                                  : getStatusColor(status),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Müşteri bilgileri
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDarkMode 
                        ? Colors.black.withAlpha(77)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode 
                          ? Colors.white.withAlpha(26)
                          : Colors.grey.shade200,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Müşteri adı ve telefon numarası
                      Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 16,
                            color: isDarkMode 
                                ? Colors.grey.shade300
                                : AppTheme.secondaryColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order['customerName'] ?? 'Müşteri Yok',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode 
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (order['customerPhone'] != null && order['customerPhone'].toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 16,
                              color: isDarkMode 
                                  ? Colors.grey.shade300
                                  : AppTheme.secondaryColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              order['customerPhone'],
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode 
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade800,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // İlk ürün bilgisi (eğer varsa)
                if (orderItems.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDarkMode 
                          ? AppTheme.accentColor.withAlpha(38)
                          : AppTheme.accentColor.withAlpha(13),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDarkMode 
                            ? Colors.white.withAlpha(26)
                            : Colors.transparent,
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shopping_bag,
                          size: 18,
                          color: isDarkMode 
                              ? AppTheme.accentColor
                              : AppTheme.secondaryColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${orderItems.first['quantity']} x ${orderItems.first['productName']}',
                            style: TextStyle(
                              fontSize: 15,
                              color: isDarkMode 
                                  ? Colors.white
                                  : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (orderItems.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDarkMode 
                                  ? AppTheme.accentColor.withAlpha(77)
                                  : AppTheme.accentColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '+${orderItems.length - 1}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode 
                                    ? Colors.white
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                ],
                
                // Alt kısım: Finansal bilgiler
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDarkMode 
                        ? Colors.black.withAlpha(77)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode 
                          ? Colors.white.withAlpha(26)
                          : Colors.grey.shade200,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Müşteri borcu
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.account_balance_wallet,
                                  size: 16,
                                  color: Colors.red.shade400,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Borç',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode 
                                        ? Colors.grey.shade300
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            FutureBuilder<double>(
                              future: _calculateCustomerDebt(customerId),
                              builder: (context, snapshot) {
                                final debt = snapshot.data ?? 0.0;
                                return Text(
                                  formatCurrency(debt),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: debt > 0 
                                        ? isDarkMode 
                                            ? Colors.red.shade300 
                                            : Colors.red.shade700
                                        : isDarkMode 
                                            ? Colors.grey.shade300 
                                            : Colors.grey.shade700,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      // Sipariş tutarı
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shopping_cart,
                                  size: 16,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Sipariş',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode 
                                        ? Colors.grey.shade300
                                        : Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency(order['totalAmount'] ?? 0.0),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode 
                                    ? AppTheme.primaryColor.withAlpha(52020)
                                    : AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Kalan tutar
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.payments,
                                  size: 16,
                                  color: (order['remainingAmount'] ?? 0.0) > 0 
                                      ? isDarkMode 
                                          ? Colors.orange.shade400 
                                          : Colors.orange.shade700
                                      : isDarkMode 
                                          ? Colors.green.shade400 
                                          : Colors.green.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Kalan',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode 
                                        ? Colors.grey.shade300
                                        : Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency((order['remainingAmount'] ?? 0.0) > 0 
                                  ? (order['remainingAmount'] ?? 0.0) 
                                  : (order['totalAmount'] != null && order['paidAmount'] != null 
                                      ? order['totalAmount'] - order['paidAmount'] 
                                      : 0.0)),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: ((order['remainingAmount'] ?? 0.0) > 0 || 
                                        (order['totalAmount'] != null && order['paidAmount'] != null && 
                                         order['totalAmount'] - order['paidAmount'] > 0))
                                    ? isDarkMode 
                                        ? Colors.orange.shade400 
                                        : Colors.orange.shade700
                                    : isDarkMode 
                                        ? Colors.green.shade400 
                                        : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Müşteri toplam borcunu hesaplayan metot
  Future<double> _calculateCustomerDebt(int? customerId) async {
    if (customerId == null) return 0.0;
    
    try {
      // Müşterinin tüm siparişlerini al
      return await CustomerService.instance.getCustomerTotalDebt(customerId);
    } catch (e) {
      debugPrint('Müşteri borcu hesaplanırken hata: $e');
      return 0.0;
    }
  }

  // Sipariş durumuna göre renk döndüren yardımcı metod
  Color getStatusColor(String? status) {
    if (status == null) return Colors.orange;
    
    switch (status) {
      case 'Bekliyor':
        return Colors.orange;
      case 'Teslim Edildi':
        return Colors.purple;
      case 'Hazırlanıyor':
        return AppTheme.primaryColor;
      case 'Satış':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  // Payment status color helper method removed as it was unused

  void _showOrderDetails(Map<String, dynamic> order) {
    // Sipariş detayları yerine düzenleme formunu açıyoruz
    _showEditOrderForm(order);
  }

  // Durum değiştirme dialog'unu gösteren metot
  void _showStatusChangeDialog(Map<String, dynamic> order) {
    final currentStatus = order['orderStatus'] as String? ?? 'Bekliyor';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sipariş Durumunu Değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _orderStatusOptions.map((status) {
            return ListTile(
              title: Text(status),
              leading: Radio<String>(
                value: status,
                groupValue: currentStatus,
                onChanged: (value) {
                  Navigator.pop(context, value);
                },
              ),
              onTap: () {
                Navigator.pop(context, status);
              },
            );
          }).toList(),
        ),
      ),
    ).then((newStatus) async {
      if (newStatus != null && newStatus != currentStatus) {
        try {
          // Sipariş durumunu güncelle
          final updatedOrder = Map<String, dynamic>.from(order);
          updatedOrder['orderStatus'] = newStatus;
          
          // Veritabanında güncelle
          await OrderService.instance.updateOrderStatus(order['id'], newStatus);
          
          // Siparişleri yeniden yükle
          await _loadOrders();
          
          // Bildirim göster
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sipariş durumu güncellendi: $newStatus'),
                backgroundColor: AppTheme.primaryColor,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          // Hata mesajı göster
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sipariş durumu güncellenirken hata oluştu: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    });
  }

  // Search bar widget removed as it was unused

  // Public erişim için metotlar
  void filterOrders(String query) {
    _filterOrders(query);
  }

  void scanBarcode() {
    _scanBarcode();
  }

  void showAddOrderDialog() {
    _showAddOrderDialog();
  }

  // Sipariş silme dialog'unu gösteren metot
  void _showOrderDeleteDialog(Map<String, dynamic> order) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode ? AppTheme.darkBackgroundColor : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: Text(
          'Siparişi Sil',
          style: TextStyle(color: textColor),
        ),
        content: Text(
          'Bu siparişi silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              try {
                // Siparişi sil
                await OrderService.instance.deleteOrder(order['id']);
                
                if (!mounted) return;
                Navigator.pop(context);
                
                // Siparişleri yeniden yükle
                _loadOrders();
                
                // Başarılı mesajı göster
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sipariş başarıyla silindi'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(context);
                
                // Hata mesajı göster
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sipariş silinirken hata oluştu: ${e.toString()}'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
