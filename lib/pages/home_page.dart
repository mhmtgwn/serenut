import 'package:flutter/material.dart';
import 'orders_page.dart';
import 'customers_page.dart';
import 'products_page.dart';
import 'finance_page.dart';
import '../services/order_service.dart';
import '../services/customer_service.dart';
import '../services/product_service.dart';
import '../widgets/modern_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const DashboardPage(),
    const OrdersPage(),
    const CustomersPage(),
    const ProductsPage(),
    const FinancePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart),
            label: 'Siparişler',
          ),
          NavigationDestination(
            icon: Icon(Icons.people),
            label: 'Müşteriler',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory),
            label: 'Ürünler',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Finans',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _orderCount = 0;
  double _totalSales = 0;
  int _customerCount = 0;
  int _productCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final orderService = OrderService();
      final customerService = CustomerService();
      final productService = ProductService();

      final today = DateTime.now().toIso8601String().split('T')[0];
      final summary = await orderService.getDailySummary(today);
      final customers = await customerService.getAll();
      final products = await productService.getAll();

      setState(() {
        _orderCount = summary['order_count'] ?? 0;
        _totalSales = summary['total_amount'] ?? 0.0;
        _customerCount = customers.length;
        _productCount = products.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SHAMAN POS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bugün',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    Text(
                      DateTime.now().toString().split(' ')[0],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'Satışlar',
                            value: '₺${_totalSales.toStringAsFixed(2)}',
                            icon: Icons.trending_up_rounded,
                            color: const Color(0xFF4CAF50),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatCard(
                            title: 'Siparişler',
                            value: '$_orderCount',
                            icon: Icons.shopping_bag_rounded,
                            color: const Color(0xFF2196F3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'Müşteriler',
                            value: '$_customerCount',
                            icon: Icons.people_rounded,
                            color: const Color(0xFFFF9800),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatCard(
                            title: 'Ürünler',
                            value: '$_productCount',
                            icon: Icons.inventory_2_rounded,
                            color: const Color(0xFF9C27B0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
