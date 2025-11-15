import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/payment_service.dart';
import '../services/expense_service.dart';
import '../services/database_helper.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

// Para birimini formatlayan yardımcı fonksiyon
String formatCurrency(double amount) {
  // Eğer tam sayı ise ondalık kısmı gösterme
  if (amount == amount.toInt().toDouble()) {
    return '${amount.toInt()} ₺';
  } else {
    return '${amount.toStringAsFixed(2)} ₺';
  }
}

class FinancePage extends StatefulWidget {
  const FinancePage({Key? key}) : super(key: key);

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  double _totalSales = 0;
  double _totalDebt = 0;
  double _totalPaid = 0;
  double _totalExpenses = 0;
  List<Map<String, dynamic>> _recentPayments = [];
  List<Map<String, dynamic>> _debtsList = [];
  List<Expense> _expensesList = [];
  late TabController _tabController;
  final TextEditingController _expenseSearchController = TextEditingController();
  final PaymentService _paymentService = PaymentService.instance;
  final ExpenseService _expenseService = ExpenseService.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadFinanceData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _expenseSearchController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging || _tabController.index != _tabController.previousIndex) {
      setState(() {
        // Tab changed
      });
    }
  }

  Future<void> _loadFinanceData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      
      // Veritabanı bağlantısını kontrol et ve yeniden aç
      await _dbHelper.ordersDatabase;
      
      // Kısa bir bekleme süresi ekleyerek veritabanı bağlantısının tam olarak açılmasını sağlayalım
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Finansal özet bilgilerini al
      final financialSummary = await _paymentService.getFinancialSummary();
      
      _totalSales = financialSummary['totalSales'] ?? 0;
      _totalPaid = financialSummary['totalPaid'] ?? 0;
      _totalDebt = financialSummary['totalDebt'] ?? 0;
      _totalExpenses = financialSummary['totalExpenses'] ?? 0;
      
      
      // Son ödemeleri al
      _recentPayments = await _paymentService.getRecentPayments(limit: 20);
      
      // Eğer ödemeler boşsa, doğrudan veritabanından almayı deneyelim
      if (_recentPayments.isEmpty) {
        final paymentHistory = await _dbHelper.getPaymentHistory();
        
        if (paymentHistory.isNotEmpty) {
          
          // Ödemeleri dönüştür
          _recentPayments = await _convertPaymentHistory(paymentHistory);
        }
      }
      
      // Borçlu müşterileri al
      _debtsList = await _paymentService.getCustomersWithDebt();
      
      // Giderleri al
      _expensesList = await _expenseService.getAllExpenses();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      // Hata mesajı göster
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Finans verileri yüklenirken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Ödeme geçmişini dönüştür
  Future<List<Map<String, dynamic>>> _convertPaymentHistory(List<Map<String, dynamic>> paymentHistory) async {
    final List<Map<String, dynamic>> result = [];
    
    for (var payment in paymentHistory) {
      try {
        final orderId = payment['orderId'] as int;
        
        // Sipariş bilgilerini al
        final db = await _dbHelper.ordersDatabase;
        final orderInfo = await db.query(
          'orders',
          where: 'id = ?',
          whereArgs: [orderId],
        );
        
        String customerName = 'Bilinmeyen Müşteri';
        if (orderInfo.isNotEmpty) {
          customerName = orderInfo.first['customerName'] as String? ?? 'Bilinmeyen Müşteri';
        }
        
        result.add({
          'id': payment['id'] as int,
          'orderId': orderId,
          'customerName': customerName,
          'amount': (payment['amount'] as num).toDouble(),
          'date': DateTime.parse(payment['paymentDate'] as String),
          'method': payment['method'] as String? ?? 'Nakit',
        });
      } catch (e) {
      }
    }
    
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFinanceData,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: isDarkMode ? Colors.white60 : Colors.grey,
              indicatorColor: AppTheme.primaryColor,
              tabs: const [
                Tab(
                  icon: Icon(Icons.dashboard_outlined),
                  text: 'Özet',
                ),
                Tab(
                  icon: Icon(Icons.trending_up),
                  text: 'Gelir',
                ),
                Tab(
                  icon: Icon(Icons.account_balance_wallet),
                  text: 'Alacak',
                ),
                Tab(
                  icon: Icon(Icons.money_off),
                  text: 'Gider',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSummaryTab(),
                  _buildPaymentsTab(),
                  _buildDebtsTab(),
                  _buildExpensesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTab() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 24),
          Text(
            'Finansal Özet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildFinancialSummaryChart(),
          const SizedBox(height: 24),
          Text(
            'Son İşlemler',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildRecentTransactions(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: isDarkMode ? AppTheme.darkSurfaceColor : Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Toplam Satış',
                  value: formatCurrency(_totalSales),
                  icon: Icons.shopping_cart,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Toplam Gelir',
                  value: formatCurrency(_totalPaid),
                  icon: Icons.payments,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Toplam Alacak',
                  value: formatCurrency(_totalDebt),
                  icon: Icons.account_balance_wallet,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Toplam Gider',
                  value: formatCurrency(_totalExpenses),
                  icon: Icons.money_off,
                  color: Colors.orange,
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
    final cardBackgroundColor = isDarkMode ? AppTheme.darkCardColor : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.grey[800];
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDarkMode ? Colors.black.withAlpha(77) : Colors.black.withAlpha(26),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: isDarkMode ? Colors.grey.withAlpha(51) : Colors.grey.withAlpha(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDarkMode ? color.withAlpha(51) : color.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isDarkMode ? color.withAlpha(230) : color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.white70 : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSummaryChart() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final borderColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : Colors.white;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildChartLegendItem(
                color: AppTheme.primaryColor, 
                label: 'Toplam Satış', 
                isDarkMode: isDarkMode
              ),
              _buildChartLegendItem(
                color: Colors.green, 
                label: 'Gelir', 
                isDarkMode: isDarkMode
              ),
              _buildChartLegendItem(
                color: Colors.red, 
                label: 'Alacak', 
                isDarkMode: isDarkMode
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Center(
              child: Text(
                'Grafik burada gösterilecek',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegendItem({required Color color, required String label, required bool isDarkMode}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.white70 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactions() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final borderColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : Colors.white;
    
    if (_recentPayments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Center(
          child: Text(
            'Henüz işlem kaydı bulunmuyor',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.grey,
            ),
          ),
        ),
      );
    }
    
    // Son 5 ödemeyi göster
    final recentTransactions = _recentPayments.take(5).toList();
    
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recentTransactions.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: borderColor,
        ),
        itemBuilder: (context, index) {
          final payment = recentTransactions[index];
          final DateTime date = payment['date'] ?? DateTime.now();
          final formattedDate = '${date.day}/${date.month}/${date.year}';
          
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.green.withAlpha(51) : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.payments,
                color: isDarkMode ? Colors.green.shade300 : Colors.green,
                size: 18,
              ),
            ),
            title: Text(
              payment['customerName'].toString(),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              '$formattedDate • ${payment['method']}',
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.white60 : Colors.grey[600],
              ),
            ),
            trailing: Text(
              formatCurrency(payment['amount'] as double),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.green.shade300 : Colors.green,
                fontSize: 14,
              ),
            ),
            onTap: () {
              _showPaymentDetails(payment);
            },
          );
        },
      ),
    );
  }

  Widget _buildPaymentsTab() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white70 : Colors.grey[600];
    final iconColor = isDarkMode ? Colors.white54 : Colors.grey[400];
    
    if (_recentPayments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              'Henüz gelir kaydı bulunmuyor',
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Yeni bir gelir eklemek için + butonuna tıklayın',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white54 : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFinanceData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _recentPayments.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final payment = _recentPayments[index];
          return _buildPaymentItem(payment);
        },
      ),
    );
  }

  Widget _buildDebtsTab() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white70 : Colors.grey[600];
    final iconColor = isDarkMode ? Colors.white54 : Colors.grey[400];
    
    if (_debtsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              'Alacak kaydı bulunmuyor',
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadFinanceData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _debtsList.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final debt = _debtsList[index];
          return _buildDebtItem(debt);
        },
      ),
    );
  }

  Widget _buildExpensesTab() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final textColor = isDarkMode ? Colors.white70 : Colors.grey[600];
    final iconColor = isDarkMode ? Colors.white54 : Colors.grey[400];
    
    if (_expensesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.money_off_outlined, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              'Henüz gider kaydı bulunmuyor',
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Yeni bir gider eklemek için + butonuna tıklayın',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white54 : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFinanceData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _expensesList.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final expense = _expensesList[index];
          return _buildExpenseItem(expense);
        },
      ),
    );
  }

  Widget _buildPaymentItem(Map<String, dynamic> payment) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final DateTime date = payment['date'] ?? DateTime.now();
    final formattedDate = '${date.day}/${date.month}/${date.year}';
          
          return Dismissible(
      key: Key('payment_${payment['id']}'),
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(
                Icons.delete,
                color: Colors.white,
              ),
            ),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Geliri Sil'),
            content: const Text('Bu gelir kaydını silmek istediğinizden emin misiniz?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('İptal'),
                    ),
              TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sil', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
      onDismissed: (direction) async {
        await _paymentService.deletePayment(payment['id'] as int);
        setState(() {
          _recentPayments.removeWhere((p) => p['id'] == payment['id']);
        });
        
        if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Gelir kaydı silindi'),
                  action: SnackBarAction(
                    label: 'Geri Al',
                    onPressed: () {
                      // Geri alma işlemi burada yapılabilir
                      _loadFinanceData();
                    },
                  ),
                ),
              );
        }
            },
            child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
            color: isDarkMode ? Colors.green.withAlpha(51) : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
          child: Icon(
                  Icons.payments,
            color: isDarkMode ? Colors.green.shade300 : Colors.green,
                  size: 20,
                ),
              ),
              title: Text(
                payment['customerName'].toString(),
          style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
            color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                'Sipariş #${payment['orderId']} • $formattedDate • ${payment['method']}',
                style: TextStyle(
                  fontSize: 12,
            color: isDarkMode ? Colors.white60 : Colors.grey[600],
                ),
              ),
              trailing: Text(
                formatCurrency(payment['amount'] as double),
          style: TextStyle(
                  fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.green.shade300 : Colors.green,
                  fontSize: 14,
                ),
              ),
              onTap: () {
                // Ödeme detayını göster
                _showPaymentDetails(payment);
        },
      ),
    );
  }

  Widget _buildDebtItem(Map<String, dynamic> debt) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final date = debt['lastOrderDate'] != null 
        ? debt['lastOrderDate'] is DateTime 
            ? debt['lastOrderDate'] 
            : DateTime.parse(debt['lastOrderDate'].toString())
        : DateTime.now();
    final formattedDate = '${date.day}/${date.month}/${date.year}';
          
          return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
          color: isDarkMode ? Colors.red.withAlpha(51) : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
        child: Icon(
                Icons.account_balance_wallet,
          color: isDarkMode ? Colors.red.shade300 : Colors.red,
                size: 20,
              ),
            ),
            title: Text(
        debt['customerName'] as String,
        style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
          color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
        'Müşteri #${debt['customerId']} • $formattedDate',
              style: TextStyle(
                fontSize: 12,
          color: isDarkMode ? Colors.white60 : Colors.grey[600],
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
            formatCurrency(debt['totalDebt'] as double),
            style: TextStyle(
                    fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.red.shade300 : Colors.red,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            onTap: () {
        // Borç detayını göster
        _showDebtDetails(debt);
            },
    );
  }

  Widget _buildExpenseItem(Expense expense) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final date = expense.date;
    final formattedDate = '${date.day}/${date.month}/${date.year}';
    final borderColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : Colors.white;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.orange.withAlpha(51) : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.money_off,
            color: isDarkMode ? Colors.orange.shade300 : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(
          expense.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          '${expense.category} • $formattedDate',
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.white60 : Colors.grey[600],
          ),
        ),
        trailing: Text(
          formatCurrency(expense.amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.orange.shade300 : Colors.orange,
            fontSize: 14,
          ),
        ),
        onTap: () {
          _showExpenseDetails(expense);
        },
      ),
    );
  }

  void _showPaymentDetails(Map<String, dynamic> payment) {
    final paymentDate = payment['date'] ?? DateTime.now();
    final formattedDate = '${paymentDate.day}/${paymentDate.month}/${paymentDate.year}';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gelir Detayı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Sipariş No', '#${payment['orderId']}'),
            _buildDetailRow('Müşteri', payment['customerName'].toString()),
            _buildDetailRow('Tutar', formatCurrency(payment['amount'] as double)),
            _buildDetailRow('Tarih', formattedDate),
            _buildDetailRow('Ödeme Yöntemi', payment['method'].toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void showAddExpenseDialog(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    // Form için controller'lar
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    
    // Form anahtarı
    final formKey = GlobalKey<FormState>();
    
    // Form doğrulama
    bool isFormValid() {
      return formKey.currentState?.validate() ?? false;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gider Ekle'),
        backgroundColor: isDarkMode ? AppTheme.darkCardColor : Colors.white,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Tutar',
                  hintText: 'Örn: 100.50',
                  suffixText: '₺',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Örn: Kira Ödemesi',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (isFormValid()) {
                try {
                  // Yeni gider ekle
                  await _expenseService.addExpense(
                    descriptionController.text,
                    double.parse(amountController.text),
                    'Diğer',
                    ''
                  );
                  
                  // Verileri yeniden yükle
                  await _loadFinanceData();
                  
                  // Önce mounted kontrolü yap
                  if (!mounted) return;
                  
                  // ignore: use_build_context_synchronously
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Gider başarıyla eklendi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  // Önce mounted kontrolü yap
                  if (!mounted) return;
                  
                  // ignore: use_build_context_synchronously
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Gider eklenirken hata oluştu: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen geçerli değerler girin'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _showDebtDetails(Map<String, dynamic> debt) {
    final date = debt['lastOrderDate'] != null 
        ? debt['lastOrderDate'] is DateTime 
            ? debt['lastOrderDate'] 
            : DateTime.parse(debt['lastOrderDate'].toString())
        : DateTime.now();
    final formattedDate = '${date.day}/${date.month}/${date.year}';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alacak Detayı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Müşteri', debt['customerName'].toString()),
            _buildDetailRow('Toplam Alacak', formatCurrency(debt['totalDebt'] as double)),
            _buildDetailRow('Son İşlem', formattedDate),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showAddPaymentForDebtDialog(context, debt);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Ödeme Al'),
          ),
        ],
      ),
    );
  }

  void _showExpenseDetails(Expense expense) {
    final date = expense.date;
    final formattedDate = '${date.day}/${date.month}/${date.year}';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gider Detayı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Başlık', expense.title),
            _buildDetailRow('Kategori', expense.category),
            _buildDetailRow('Tutar', formatCurrency(expense.amount)),
            _buildDetailRow('Tarih', formattedDate),
            if (expense.note.isNotEmpty) _buildDetailRow('Notlar', expense.note),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Gider silme işlemi
              try {
                await _expenseService.deleteExpense(expense.id);
                setState(() {
                  _expensesList.removeWhere((e) => e.id == expense.id);
                  _totalExpenses -= expense.amount;
                });
                
                // Mounted kontrolü
                if (!mounted) return;
                
                // ignore: use_build_context_synchronously
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Gider silindi'),
                    backgroundColor: Colors.red,
                  ),
                );
              } catch (e) {
                // Mounted kontrolü
                if (!mounted) return;
                
                // ignore: use_build_context_synchronously
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Gider silinirken hata oluştu: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddPaymentForDebtDialog(BuildContext context, Map<String, dynamic> debt) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkMode = themeProvider.isDarkMode;
    final customerName = debt['customerName'] as String;
    final totalDebt = debt['totalDebt'] as double;
    
    final amountController = TextEditingController();
    amountController.text = totalDebt.toString(); // Varsayılan olarak toplam alacak tutarını göster
    
    String paymentMethod = 'Nakit';
    final paymentMethods = ['Nakit', 'Banka/Kredi Kartı', 'Havale/EFT', 'Diğer'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Alacak Tahsilatı: $customerName'),
        backgroundColor: isDarkMode ? AppTheme.darkCardColor : Colors.white,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Toplam Alacak: ${formatCurrency(totalDebt)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Tahsilat Tutarı',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Ödeme Yöntemi',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payment),
                ),
                items: paymentMethods.map((String method) {
                  return DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    paymentMethod = newValue;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // Tutarı kontrol et
                final amountText = amountController.text.trim();
                if (amountText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen bir tutar girin')),
                  );
                  return;
                }
                
                final amount = double.tryParse(amountText.replaceAll(',', '.'));
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Geçerli bir tutar girin')),
                  );
                  return;
                }
                
                // Ödeme ekle
                await _paymentService.addPayment(0, amount, 'Alacak tahsilatı: $customerName', paymentMethod);
                
                // Borç güncelleme işlemi burada yapılabilir
                
                Navigator.pop(context);
                
                // Verileri yeniden yükle
                _loadFinanceData();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tahsilat başarıyla kaydedildi'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Tahsilat kaydedilirken hata oluştu: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Tahsil Et'),
          ),
        ],
      ),
    );
  }


}
