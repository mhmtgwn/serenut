import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/customer_service.dart';
import 'order_detail_page.dart';

class CustomerDetailPage extends StatefulWidget {
  final Customer customer;

  const CustomerDetailPage({super.key, required this.customer});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage>
    with SingleTickerProviderStateMixin {
  final OrderService _orderService = OrderService();
  final CustomerService _customerService = CustomerService();
  List<Order> _orders = [];
  double _totalDebt = 0;
  double _totalSpent = 0;
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final allOrders = await _orderService.getAll();
    final customerOrders =
        allOrders.where((o) => o.customerId == widget.customer.id).toList();

    final debt = customerOrders.fold<double>(
        0, (sum, order) => sum + order.remainingAmount);
    final spent =
        customerOrders.fold<double>(0, (sum, order) => sum + order.total);

    setState(() {
      _orders = customerOrders;
      _totalDebt = debt;
      _totalSpent = spent;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_rounded),
            onPressed: _showPaymentDialog,
            style: IconButton.styleFrom(
              backgroundColor: _totalDebt > 0
                  ? Colors.orange.withOpacity(0.1)
                  : const Color(0xFFF1F5F9),
            ),
            tooltip: 'Ödeme/Borç İşlemi',
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: _showEditDialog,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1F5F9),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Özet'),
            Tab(text: 'Siparişler'),
            Tab(text: 'Hareketler'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(),
                _buildOrdersTab(),
                _buildTransactionsTab(),
              ],
            ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // İletişim Bilgileri
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'İletişim Bilgileri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(Icons.phone_rounded, widget.customer.phone),
                if (widget.customer.address != null &&
                    widget.customer.address!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(
                      Icons.location_on_rounded, widget.customer.address!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // İstatistikler
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Toplam Borç',
                  '₺${_totalDebt.toStringAsFixed(2)}',
                  Icons.account_balance_wallet_rounded,
                  _totalDebt > 0 ? Colors.orange : const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Toplam Harcama',
                  '₺${_totalSpent.toStringAsFixed(2)}',
                  Icons.shopping_bag_rounded,
                  const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Sipariş Sayısı',
                  '${_orders.length}',
                  Icons.receipt_long_rounded,
                  const Color(0xFF9C27B0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Ortalama Sipariş',
                  _orders.isEmpty
                      ? '₺0'
                      : '₺${(_totalSpent / _orders.length).toStringAsFixed(0)}',
                  Icons.trending_up_rounded,
                  const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab() {
    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Henüz sipariş yok',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        return _buildOrderCard(order);
      },
    );
  }

  Widget _buildTransactionsTab() {
    // Tüm siparişlerden ödeme hareketlerini çıkar
    final List<Map<String, dynamic>> transactions = [];

    for (var order in _orders) {
      // Sipariş oluşturma
      transactions.add({
        'type': 'order_created',
        'date': DateTime.parse(order.createdAt),
        'amount': order.total,
        'order': order,
        'note': 'Sipariş oluşturuldu',
      });

      // Ödeme varsa
      if (order.paidAmount > 0) {
        transactions.add({
          'type': 'payment',
          'date': DateTime.parse(order
              .createdAt), // Gerçek ödeme tarihi olmalı ama şimdilik sipariş tarihi
          'amount': order.paidAmount,
          'order': order,
          'note': order.paymentStatus == 'paid' ? 'Tam ödeme' : 'Kısmi ödeme',
        });
      }
    }

    // Tarihe göre sırala (en yeni en üstte)
    transactions.sort(
        (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Henüz hareket yok',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final transaction = transactions[index];
        return _buildTransactionCard(transaction);
      },
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final type = transaction['type'] as String;
    final date = transaction['date'] as DateTime;
    final amount = transaction['amount'] as double;
    final note = transaction['note'] as String;
    final order = transaction['order'] as Order;

    final isPayment = type == 'payment';
    final isDebt = type == 'order_created' && order.paymentMethod == 'debt';

    Color color;
    IconData icon;
    String title;

    if (isPayment) {
      color = const Color(0xFF10B981);
      icon = Icons.arrow_downward_rounded;
      title = 'Ödeme Alındı';
    } else if (isDebt) {
      color = Colors.orange;
      icon = Icons.arrow_upward_rounded;
      title = 'Borç Eklendi';
    } else {
      color = const Color(0xFF3B82F6);
      icon = Icons.shopping_cart_rounded;
      title = 'Sipariş';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
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
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateTime(date),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isPayment ? '-' : '+'}₺${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.orderNumber,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    String dateStr;
    if (dateOnly == today) {
      dateStr = 'Bugün';
    } else if (dateOnly == yesterday) {
      dateStr = 'Dün';
    } else {
      dateStr = '${date.day}.${date.month}.${date.year}';
    }

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$dateStr $hour:$minute';
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF10B981)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, color: Color(0xFF475569)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderDetailPage(order: order),
              ),
            ).then((_) => _loadData());
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getStatusText(order.status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(order.status),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₺${order.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (order.hasDebt)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Borç: ₺${order.remainingAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.blue;
      case 'ready':
        return const Color(0xFF10B981);
      case 'delivered':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Bekliyor';
      case 'preparing':
        return 'Hazırlanıyor';
      case 'ready':
        return 'Hazır';
      case 'delivered':
        return 'Teslim Edildi';
      default:
        return status;
    }
  }

  Future<void> _showEditDialog() async {
    final nameController = TextEditingController(text: widget.customer.name);
    final phoneController = TextEditingController(text: widget.customer.phone);
    final addressController =
        TextEditingController(text: widget.customer.address);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Müşteri Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefon',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Adres',
                  prefixIcon: Icon(Icons.location_on_rounded),
                ),
                maxLines: 3,
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
              final updatedCustomer = Customer(
                id: widget.customer.id,
                name: nameController.text,
                phone: phoneController.text,
                address: addressController.text,
                createdAt: widget.customer.createdAt,
              );

              await _customerService.update(updatedCustomer);

              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pop(context, true); // Geri dön ve refresh et
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Müşteri güncellendi'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPaymentDialog() async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String type = 'payment'; // payment (ödeme) veya debt (borç)

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('İşlem - ${widget.customer.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Toplam Borç: ₺${_totalDebt.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'payment',
                    label: Text('Ödeme Al'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                  ButtonSegment(
                    value: 'debt',
                    label: Text('Borç Ekle'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (Set<String> newSelection) {
                  setDialogState(() => type = newSelection.first);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: InputDecoration(
                  labelText: type == 'payment' ? 'Ödeme Tutarı' : 'Borç Tutarı',
                  prefixText: '₺',
                  prefixIcon: Icon(
                    type == 'payment'
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: type == 'payment'
                        ? const Color(0xFF10B981)
                        : Colors.orange,
                  ),
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Not (Opsiyonel)',
                  prefixIcon: Icon(Icons.note_rounded),
                ),
                maxLines: 2,
              ),
              if (type == 'payment' && _totalDebt > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          amountController.text = _totalDebt.toStringAsFixed(2);
                        },
                        child: const Text('Tamamını Öde'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) return;

                if (type == 'payment') {
                  // ÖDEME AL
                  if (amount > _totalDebt) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ödeme tutarı borçtan fazla olamaz!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final debtOrders = _orders.where((o) => o.hasDebt).toList();
                  double remaining = amount;

                  for (var order in debtOrders) {
                    if (remaining <= 0) break;

                    final payment = remaining >= order.remainingAmount
                        ? order.remainingAmount
                        : remaining;

                    final newPaidAmount = order.paidAmount + payment;
                    final newStatus =
                        newPaidAmount >= order.total ? 'paid' : 'partial';

                    await _orderService.updatePayment(
                        order.id!, newPaidAmount, newStatus);
                    remaining -= payment;
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('₺${amount.toStringAsFixed(2)} ödeme alındı'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                    _loadData();
                  }
                } else {
                  // BORÇ EKLE
                  // Yeni bir "borç" siparişi oluştur
                  final newOrder = Order(
                    orderNumber:
                        'BORC-${DateTime.now().millisecondsSinceEpoch}',
                    customerId: widget.customer.id!,
                    customerName: widget.customer.name,
                    customerPhone: widget.customer.phone,
                    total: amount,
                    paidAmount: 0,
                    paymentStatus: 'unpaid',
                    status: 'delivered',
                    paymentMethod: 'debt',
                    notes: noteController.text.isEmpty
                        ? 'Borç kaydı'
                        : noteController.text,
                    createdAt: DateTime.now().toIso8601String(),
                  );

                  await _orderService.create(newOrder, []);

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('₺${amount.toStringAsFixed(2)} borç eklendi'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    _loadData();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    type == 'payment' ? const Color(0xFF10B981) : Colors.orange,
              ),
              child: Text(type == 'payment' ? 'Ödeme Al' : 'Borç Ekle'),
            ),
          ],
        ),
      ),
    );
  }
}
