import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_nav.dart';
import '../services/product_service.dart';
import '../services/customer_service.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'package:intl/intl.dart';
import 'customers.dart';
import 'products.dart';
import 'settings.dart';
import 'orders.dart';
import 'finance.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

// Para birimini formatla
String formatCurrency(double amount) {
  final formatter = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  return formatter.format(amount);
}

class HomePage extends StatefulWidget {
  final int initialIndex;
  final ThemeProvider themeProvider;
  
  const HomePage({super.key, this.initialIndex = 0, required this.themeProvider});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  
  // Sayfa GlobalKey'lerini bir kez tanımlıyoruz
  final _customersContentKey = GlobalKey<CustomersContentState>();
  final _ordersContentKey = GlobalKey<OrdersContentState>();
  final _productsContentKey = GlobalKey<ProductsContentState>();
  final _financeContentKey = GlobalKey<State<FinancePage>>();
  
  // Sayfa içeriklerini tutacak değişkenler
  late Widget _homeContent;
  late Widget _ordersContent;
  late Widget _productsContent;
  late Widget _customersContent;
  late Widget _financeContent;
  
  // Her sayfa için ayrı arama kontrolcüleri
  final TextEditingController _ordersSearchController = TextEditingController();
  final TextEditingController _productsSearchController = TextEditingController();
  final TextEditingController _customersSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    
    // Sayfa içeriklerini önceden oluştur
    _homeContent = const HomeContent();
    _ordersContent = OrdersContent(key: _ordersContentKey);
    _productsContent = ProductsContent(key: _productsContentKey);
    _customersContent = CustomersContent(key: _customersContentKey);
    _financeContent = FinancePage(key: _financeContentKey);
    
    // Arama kontrolcülerini sayfa state'lerine bağla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectSearchControllers();
    });
  }
  
  @override
  void dispose() {
    // Arama kontrolcülerini temizle
    _ordersSearchController.dispose();
    _productsSearchController.dispose();
    _customersSearchController.dispose();
    super.dispose();
  }
  
  // Arama kontrolcülerini sayfa state'lerine bağla
  void _connectSearchControllers() {
    if (_ordersContentKey.currentState != null) {
      _ordersContentKey.currentState!.searchController.addListener(() {
        if (_currentIndex == 1) {
          final text = _ordersContentKey.currentState!.searchController.text;
          if (_ordersSearchController.text != text) {
            _ordersSearchController.text = text;
          }
        }
      });
    }
    
    if (_productsContentKey.currentState != null) {
      _productsContentKey.currentState!.searchController.addListener(() {
        if (_currentIndex == 2) {
          final text = _productsContentKey.currentState!.searchController.text;
          if (_productsSearchController.text != text) {
            _productsSearchController.text = text;
          }
        }
      });
    }
    
    if (_customersContentKey.currentState != null) {
      _customersContentKey.currentState!.searchController.addListener(() {
        if (_currentIndex == 3) {
          final text = _customersContentKey.currentState!.searchController.text;
          if (_customersSearchController.text != text) {
            _customersSearchController.text = text;
          }
        }
      });
    }
  }

  void _onNavigationTap(int index) {
    if (_currentIndex == index) {
      // Aynı sayfaya tekrar tıklandığında arama kutusunu temizle
      _clearSearchText();
    } else {
      setState(() {
        _currentIndex = index;
        // Sayfa değiştiğinde arama kutusunu temizle
        _clearSearchText();
      });
    }
  }
  
  // Arama kutusunu temizle
  void _clearSearchText() {
    switch (_currentIndex) {
      case 1:
        _ordersSearchController.clear();
        if (_ordersContentKey.currentState != null) {
          _ordersContentKey.currentState!.filterOrders('');
        }
        break;
      case 2:
        _productsSearchController.clear();
        if (_productsContentKey.currentState != null) {
          _productsContentKey.currentState!.applyFiltersAndSort(searchQuery: '');
        }
        break;
      case 3:
        _customersSearchController.clear();
        if (_customersContentKey.currentState != null) {
          _customersContentKey.currentState!.filterCustomers('');
        }
        break;
    }
  }

  Widget getBody() {
    switch (_currentIndex) {
      case 0:
        return _homeContent;
      case 1:
        return _ordersContent;
      case 2:
        return _productsContent;
      case 3:
        return _customersContent;
      case 4:
        return _financeContent;
      default:
        return _homeContent;
    }
  }

  String getTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Kontrol Paneli';
      case 1:
        return 'Siparişler';
      case 2:
        return 'Ürünler';
      case 3:
        return 'Müşteriler';
      case 4:
        return 'Finans';
      default:
        return 'Shaman';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode ? AppTheme.darkBackgroundColor : AppTheme.lightBackgroundColor;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: CustomAppBar(
        title: getTitle(),
        showSearch: _currentIndex >= 1 && _currentIndex <= 3,
        onSearchChanged: getSearchFunction(),
        searchHintText: _currentIndex == 1 ? 'Sipariş ara...' : 
                        _currentIndex == 2 ? 'Ürün ara...' : 
                        _currentIndex == 3 ? 'Müşteri ara...' : null,
        actions: [
          // Ayarlar butonu
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: getBody(),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavigationTap,
        searchController: getSearchController(),
        onSearchChanged: getSearchFunction(),
        onScanPressed: _currentIndex == 1 ? () => _ordersContentKey.currentState?.scanBarcode() : null,
        onAddPressed: getAddFunction(),
        onSyncPressed: _currentIndex == 3 ? () => _customersContentKey.currentState?.syncContacts() : null,
        onFilterPressed: getFilterFunction(),
        searchHintText: _currentIndex == 1 ? 'Sipariş Ara...' : 
                        _currentIndex == 2 ? 'Ürün Ara...' : 
                        _currentIndex == 3 ? 'Müşteri Ara...' : 'Ara...',
      ),
    );
  }

  // Arama kontrolcüsünü almak için yardımcı fonksiyon
  TextEditingController? getSearchController() {
    switch (_currentIndex) {
      case 1: // Siparişler
        return _ordersSearchController;
      case 2: // Ürünler
        return _productsSearchController;
      case 3: // Müşteriler
        return _customersSearchController;
      default:
        return null;
    }
  }

  // Arama fonksiyonunu almak için yardımcı fonksiyon
  Function(String)? getSearchFunction() {
    switch (_currentIndex) {
      case 1: // Siparişler
        return (String value) {
          if (_ordersContentKey.currentState != null) {
            _ordersContentKey.currentState!.filterOrders(value);
          }
        };
      case 2: // Ürünler
        return (String value) {
          if (_productsContentKey.currentState != null) {
            _productsContentKey.currentState!.applyFiltersAndSort(searchQuery: value);
          }
        };
      case 3: // Müşteriler
        return (String value) {
          if (_customersContentKey.currentState != null) {
            _customersContentKey.currentState!.filterCustomers(value);
          }
        };
      default:
        return null;
    }
  }

  // Filtre fonksiyonunu almak için yardımcı fonksiyon
  Function()? getFilterFunction() {
    switch (_currentIndex) {
      case 1: // Siparişler
        return () {
          if (_ordersContentKey.currentState != null) {
            _ordersContentKey.currentState!.filterOrders('');
          }
        };
      case 2: // Ürünler
        return () {
          if (_productsContentKey.currentState != null) {
            _productsContentKey.currentState!.applyFiltersAndSort();
          }
        };
      case 3: // Müşteriler
        return () {
          if (_customersContentKey.currentState != null) {
            _customersContentKey.currentState!.filterCustomers('');
          }
        };
      default:
        return null;
    }
  }

  // Ekleme fonksiyonunu almak için yardımcı fonksiyon
  Function()? getAddFunction() {
    switch (_currentIndex) {
      case 1: // Siparişler
        return () {
          if (_ordersContentKey.currentState != null) {
            _ordersContentKey.currentState!.showAddOrderDialog();
          }
        };
      case 2: // Ürünler
        return () {
          if (_productsContentKey.currentState != null) {
            _productsContentKey.currentState!.showAddProductDialog();
          }
        };
      case 3: // Müşteriler
        return () {
          if (_customersContentKey.currentState != null) {
            _customersContentKey.currentState!.showAddCustomerDialog();
          }
        };
      default:
        return null;
    }
  }
}

class HomeContent extends StatefulWidget {
  const HomeContent({Key? key}) : super(key: key);

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  bool _isLoading = true;
  int _totalOrders = 0;
  int _pendingOrders = 0;
  double _totalSales = 0;
  double _totalDebt = 0;
  // Removed unused field: _lowStockProducts
  int _totalCustomers = 0;
  int _totalProducts = 0;
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _lowStockProductsList = [];
  List<double> _weeklySales = List.filled(7, 0);

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Sipariş verilerini yükle
      final orderService = OrderService.instance;
      final allOrders = await orderService.getAllOrders();
      
      if (!mounted) return; // Mounted kontrolü eklendi
      
      // Toplam sipariş sayısı
      _totalOrders = allOrders.length;
      
      // Bekleyen siparişler
      _pendingOrders = allOrders.where((order) => 
        order['orderStatus'] == 'Bekliyor' || 
        order['orderStatus'] == 'Hazırlanıyor'
      ).length;
      
      // Toplam satış tutarı
      _totalSales = allOrders.fold(0, (sum, order) => 
        sum + (order['totalAmount'] as double? ?? 0)
      );
      
      // Toplam alacak tutarı
      _totalDebt = allOrders.fold(0, (sum, order) {
        final totalAmount = order['totalAmount'] as double? ?? 0;
        final paidAmount = order['paidAmount'] as double? ?? 0;
        return sum + (totalAmount - paidAmount);
      });
      
      // Müşteri sayısını yükle
      final customerService = CustomerService.instance;
      final allCustomers = await customerService.getAllCustomers();
      
      if (!mounted) return; // Mounted kontrolü eklendi
      
      _totalCustomers = allCustomers.length;

      // Ürün sayısını yükle
      final productService = ProductService.instance;
      final allProducts = await productService.getAllProducts();
      
      if (!mounted) return; // Mounted kontrolü eklendi
      
      _totalProducts = allProducts.length;
      
      // Son siparişler (en son 5 sipariş)
      _recentOrders = allOrders.take(5).map((order) => {
        'id': order['id'],
        'customerName': order['customerName'],
        'date': DateTime.parse(order['orderDate']),
        'amount': order['totalAmount'] as double? ?? 0,
        'status': order['orderStatus'],
      }).toList();
      
      // Haftalık satışlar
      _weeklySales = await _calculateWeeklySales();
      
      if (!mounted) return; // Mounted kontrolü eklendi
      
      // Kritik stok ürünleri
      final lowStockProducts = await productService.getLowStockProducts();
      
      if (!mounted) return; // Mounted kontrolü eklendi
      
      // Removed reference to unused field _lowStockProducts
      _lowStockProductsList = lowStockProducts.map((product) => {
        'id': product['id'],
        'name': product['name'],
        'stock': product['stock'] as double? ?? 0,
        'criticalStock': product['criticalStock'] as double? ?? 0,
      }).toList();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<List<double>> _calculateWeeklySales() async {
    final orderService = OrderService.instance;
    final allOrders = await orderService.getAllOrders();
    
    // Son 7 gün için satış verilerini hesapla
    final List<double> weeklySales = List.filled(7, 0);
    final now = DateTime.now();
    
    for (var order in allOrders) {
      try {
        final orderDate = DateTime.parse(order['orderDate']);
        final difference = now.difference(orderDate).inDays;
        
        // Son 7 gün içindeki siparişleri hesapla
        if (difference >= 0 && difference < 7) {
          weeklySales[difference] += order['totalAmount'] as double? ?? 0;
        }
      } catch (e) {
        // Hata durumunda sessizce devam et
      }
    }
    
    // Eğer tüm değerler sıfırsa, grafik çiziminde hata oluşmaması için varsayılan değerler ata
    bool allZeros = weeklySales.every((value) => value == 0);
    if (allZeros) {
      // Varsayılan değerler ata (1'den 7'ye kadar)
      for (int i = 0; i < 7; i++) {
        weeklySales[i] = 1.0 + i;
      }
    }
    
    // Günleri ters çevir (en eski gün solda olacak şekilde)
    return weeklySales.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadDashboardData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Özet bilgiler
                  _buildSummaryCards(),
                  
                  const SizedBox(height: 16),
                  
                  // Son siparişler
                  _buildRecentOrders(),
                  
                  const SizedBox(height: 16),
                  
                  // Kritik stok uyarıları
                  _buildLowStockWarnings(),
                  
                  const SizedBox(height: 16),
                  
                  // Satış grafiği
                  _buildSalesChart(),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
  }

  Widget _buildSummaryCards() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final iconColor = isDarkMode ? AppTheme.darkIconColor : AppTheme.lightIconColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: const [], // Gölgeleri kaldır
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.insights,
                    color: iconColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Genel Bakış',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Toplam Sipariş',
                  value: '$_totalOrders',
                  icon: Icons.receipt_long,
                  color: AppTheme.greenColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Bekleyen',
                  value: '$_pendingOrders',
                  icon: Icons.pending_actions,
                  color: AppTheme.greenColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Alacak',
                  value: formatCurrency(_totalDebt),
                  icon: Icons.account_balance_wallet,
                  color: AppTheme.greenColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Toplam Satış',
                  value: formatCurrency(_totalSales),
                  icon: Icons.shopping_cart,
                  color: AppTheme.greenColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Müşteriler',
                  value: '$_totalCustomers',
                  icon: Icons.people,
                  color: AppTheme.greenColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Ürünler',
                  value: '$_totalProducts',
                  icon: Icons.inventory_2,
                  color: AppTheme.greenColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode ? AppTheme.darkSurfaceColor : AppTheme.lightCardColor;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final secondaryTextColor = isDarkMode ? AppTheme.darkSecondaryTextColor : AppTheme.lightSecondaryTextColor;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final iconColor = isDarkMode ? AppTheme.darkIconColor : AppTheme.lightIconColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: const [], // Gölgeleri kaldır
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentOrders() {
    if (_recentOrders.isEmpty) {
      return const SizedBox();
    }

    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final secondaryTextColor = isDarkMode ? AppTheme.darkSecondaryTextColor : AppTheme.lightSecondaryTextColor;
    final dividerColor = isDarkMode ? AppTheme.darkDividerColor : AppTheme.lightDividerColor;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final iconColor = isDarkMode ? AppTheme.darkIconColor : AppTheme.lightIconColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      color: iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Son Siparişler',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>  const OrdersContent(),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.greenColor,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Tümünü Gör'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentOrders.length > 3 ? 3 : _recentOrders.length,
            separatorBuilder: (context, index) => Divider(
              height: 1, 
              indent: 16, 
              endIndent: 16, 
              color: dividerColor,
            ),
            itemBuilder: (context, index) {
              final order = _recentOrders[index];
              
              // Tarih formatı
              final orderDate = order['date'] as DateTime;
              final formattedDate = '${orderDate.day}/${orderDate.month}/${orderDate.year}';
              
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: AppTheme.greenColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.receipt,
                    color: iconColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Sipariş #${order['id']}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
                subtitle: Text(
                  '${order['customerName']} - $formattedDate',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryTextColor,
                  ),
                ),
                trailing: Text(
                  formatCurrency(order['amount'] as double),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.greenColor,
                  ),
                ),
                onTap: () {
                  // Sipariş detayına git
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockWarnings() {
    if (_lowStockProductsList.isEmpty) {
      return const SizedBox();
    }

    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final secondaryTextColor = isDarkMode ? AppTheme.darkSecondaryTextColor : AppTheme.lightSecondaryTextColor;
    final dividerColor = isDarkMode ? AppTheme.darkDividerColor : AppTheme.lightDividerColor;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final iconColor = isDarkMode ? AppTheme.darkIconColor : AppTheme.lightIconColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Kritik Stok (${_lowStockProductsList.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ProductsContent(),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.greenColor,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Tümünü Gör'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _lowStockProductsList.length > 3 ? 3 : _lowStockProductsList.length,
            separatorBuilder: (context, index) => Divider(
              height: 1, 
              indent: 16, 
              endIndent: 16, 
              color: dividerColor,
            ),
            itemBuilder: (context, index) {
              final product = _lowStockProductsList[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  child: Text(
                    product['name'][0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  product['name'],
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                subtitle: Text(
                  'Stok: ${product['stock'].toInt()} (Kritik: ${product['criticalStock'].toInt()})',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryTextColor,
                  ),
                ),
                trailing: ElevatedButton(
                  onPressed: () {
                    // Stok ekleme işlemi
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'Stok Ekle',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                onTap: () {
                  // Ürün detayına git
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSalesChart() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final secondaryTextColor = isDarkMode ? AppTheme.darkSecondaryTextColor : AppTheme.lightSecondaryTextColor;
    final gridColor = isDarkMode ? AppTheme.darkDividerColor : AppTheme.lightDividerColor;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final iconColor = isDarkMode ? AppTheme.darkIconColor : AppTheme.lightIconColor;
    
    // Eğer tüm değerler sıfırsa, grafik çizme
    bool allZeros = _weeklySales.every((value) => value == 0);
    if (allZeros) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.show_chart,
                  color: iconColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Haftalık Satışlar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: Text(
                'Henüz satış verisi bulunmuyor',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 14,
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      );
    }
    
    // Maksimum değeri bul (y ekseni için)
    final maxY = _weeklySales.reduce((curr, next) => curr > next ? curr : next);
    
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart,
                color: iconColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Haftalık Satışlar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 5 > 0 ? maxY / 5 : 1,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: gridColor,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        const style = TextStyle(
                          color: Color(0xff68737d),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        );
                        String text;
                        switch (value.toInt()) {
                          case 0:
                            text = 'Pzt';
                            break;
                          case 1:
                            text = 'Sal';
                            break;
                          case 2:
                            text = 'Çar';
                            break;
                          case 3:
                            text = 'Per';
                            break;
                          case 4:
                            text = 'Cum';
                            break;
                          case 5:
                            text = 'Cmt';
                            break;
                          case 6:
                            text = 'Paz';
                            break;
                          default:
                            text = '';
                            break;
                        }
                        return Text(text, style: style);
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: maxY / 5 > 0 ? maxY / 5 : 1,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: false,
                ),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY * 1.2,
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(7, (index) {
                      return FlSpot(index.toDouble(), _weeklySales[index]);
                    }),
                    isCurved: true,
                    color: AppTheme.greenColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: AppTheme.greenColor,
                          strokeWidth: 2,
                          strokeColor: backgroundColor,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      // ignore: deprecated_member_use
                      color: AppTheme.greenColor.withAlpha(265),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
