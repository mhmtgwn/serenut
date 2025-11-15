import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/datasources/order_service.dart';
import '../../shared/constants/theme_provider.dart';
import '../../shared/utils/debug_config.dart';

// Para birimini formatlayan yardımcı fonksiyon
String formatCurrency(double amount) {
  if (amount == amount.toInt().toDouble()) {
    return '${amount.toInt()} ₺';
  } else {
    return '${amount.toStringAsFixed(2)} ₺';
  }
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  double _totalSales = 0;
  double _totalDebt = 0;
  double _totalPaid = 0;
  final double _totalExpenses = 0;
  List<Map<String, dynamic>> _recentPayments = [];
  List<Map<String, dynamic>> _debtsList = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFinanceData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFinanceData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      DebugConfig.logDebug('Finans verileri yükleniyor...');

      // Siparişleri al
      final orders = await OrderService.instance.getAllOrders();

      // Toplam satış
      _totalSales = 0;
      _totalPaid = 0;
      _totalDebt = 0;

      for (var order in orders) {
        final total = (order['total'] as num?)?.toDouble() ?? 0;
        final paid = (order['paid'] as num?)?.toDouble() ?? 0;
        final debt = total - paid;

        _totalSales += total;
        _totalPaid += paid;
        if (debt > 0) {
          _totalDebt += debt;
        }
      }

      // Son ödemeleri al (ödeme geçmişi olan siparişler)
      _recentPayments = orders
          .where((order) {
            final paid = (order['paid'] as num?)?.toDouble() ?? 0;
            return paid > 0;
          })
          .take(20)
          .toList();

      // Borçlu müşterileri al
      _debtsList = orders.where((order) {
        final total = (order['total'] as num?)?.toDouble() ?? 0;
        final paid = (order['paid'] as num?)?.toDouble() ?? 0;
        return total > paid;
      }).toList();

      DebugConfig.logSuccess(
          'Finans verileri yüklendi: Satış=${formatCurrency(_totalSales)}, Ödenen=${formatCurrency(_totalPaid)}, Borç=${formatCurrency(_totalDebt)}');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      DebugConfig.logError('Finans verileri yükleme hatası', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finans'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Özet'),
            Tab(text: 'Ödemeler'),
            Tab(text: 'Borçlar'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFinanceData,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(isDarkMode),
                _buildPaymentsTab(isDarkMode),
                _buildDebtsTab(isDarkMode),
              ],
            ),
    );
  }

  Widget _buildSummaryTab(bool isDarkMode) {
    return RefreshIndicator(
      onRefresh: _loadFinanceData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(
            'Toplam Satış',
            _totalSales,
            Icons.shopping_cart,
            Colors.blue,
            isDarkMode,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Ödenen',
            _totalPaid,
            Icons.check_circle,
            Colors.green,
            isDarkMode,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Borç',
            _totalDebt,
            Icons.warning,
            Colors.orange,
            isDarkMode,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Net Gelir',
            _totalPaid - _totalExpenses,
            Icons.account_balance_wallet,
            Colors.purple,
            isDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    IconData icon,
    Color color,
    bool isDarkMode,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatCurrency(amount),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentsTab(bool isDarkMode) {
    if (_recentPayments.isEmpty) {
      return const Center(
        child: Text('Henüz ödeme kaydı yok'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFinanceData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _recentPayments.length,
        itemBuilder: (context, index) {
          final payment = _recentPayments[index];
          final customerName = payment['customer_name'] ?? 'Bilinmeyen';
          final paid = (payment['paid'] as num?)?.toDouble() ?? 0;
          final date = payment['date'] ?? '';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.1),
                child: const Icon(Icons.payment, color: Colors.green),
              ),
              title: Text(customerName),
              subtitle: Text(date),
              trailing: Text(
                formatCurrency(paid),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDebtsTab(bool isDarkMode) {
    if (_debtsList.isEmpty) {
      return const Center(
        child: Text('Borç kaydı yok'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFinanceData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _debtsList.length,
        itemBuilder: (context, index) {
          final debt = _debtsList[index];
          final customerName = debt['customer_name'] ?? 'Bilinmeyen';
          final total = (debt['total'] as num?)?.toDouble() ?? 0;
          final paid = (debt['paid'] as num?)?.toDouble() ?? 0;
          final remaining = total - paid;
          final date = debt['date'] ?? '';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.orange.withOpacity(0.1),
                child: const Icon(Icons.warning, color: Colors.orange),
              ),
              title: Text(customerName),
              subtitle: Text(
                  '$date\nToplam: ${formatCurrency(total)} | Ödenen: ${formatCurrency(paid)}'),
              isThreeLine: true,
              trailing: Text(
                formatCurrency(remaining),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
