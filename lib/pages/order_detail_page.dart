import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/sms_service.dart';

class OrderDetailPage extends StatefulWidget {
  final Order order;

  const OrderDetailPage({super.key, required this.order});

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final OrderService _orderService = OrderService();
  final SmsService _smsService = SmsService();
  List<OrderItem> _items = [];
  bool _isLoading = true;
  late Order _currentOrder;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _loadOrderItems();
  }

  Future<void> _loadOrderItems() async {
    setState(() => _isLoading = true);
    final items = await _orderService.getOrderItems(_currentOrder.id!);
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    await _orderService.updateStatus(_currentOrder.id!, newStatus);

    // SMS gönder
    await _smsService.sendOrderSms(_currentOrder, newStatus);

    setState(() {
      _currentOrder = Order(
        id: _currentOrder.id,
        orderNumber: _currentOrder.orderNumber,
        customerId: _currentOrder.customerId,
        customerName: _currentOrder.customerName,
        customerPhone: _currentOrder.customerPhone,
        total: _currentOrder.total,
        status: newStatus,
        paymentMethod: _currentOrder.paymentMethod,
        notes: _currentOrder.notes,
        createdAt: _currentOrder.createdAt,
      );
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Durum güncellendi: ${_getStatusText(newStatus)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sipariş #${_currentOrder.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () {},
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1F5F9),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCustomerInfo(),
                  const SizedBox(height: 16),
                  _buildStatusSection(),
                  const SizedBox(height: 16),
                  _buildItemsList(),
                  const SizedBox(height: 16),
                  _buildTotalSection(),
                  if (_currentOrder.notes != null &&
                      _currentOrder.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildNotesSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildCustomerInfo() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Müşteri Bilgileri',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.person_rounded, _currentOrder.customerName),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.phone_rounded, _currentOrder.customerPhone),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.payment_rounded,
            _currentOrder.paymentMethod == 'cash' ? 'Nakit' : 'Kart',
          ),
        ],
      ),
    );
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
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    final statuses = [
      {
        'value': 'pending',
        'label': 'Beklemede',
        'icon': Icons.schedule_rounded
      },
      {
        'value': 'preparing',
        'label': 'Hazırlanıyor',
        'icon': Icons.restaurant_rounded
      },
      {'value': 'ready', 'label': 'Hazır', 'icon': Icons.check_circle_rounded},
      {
        'value': 'delivered',
        'label': 'Teslim Edildi',
        'icon': Icons.done_all_rounded
      },
      {'value': 'cancelled', 'label': 'İptal', 'icon': Icons.cancel_rounded},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sipariş Durumu',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: statuses.map((status) {
              final isSelected = _currentOrder.status == status['value'];
              final color = _getStatusColor(status['value'] as String);

              return FilterChip(
                selected: isSelected,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      status['icon'] as IconData,
                      size: 18,
                      color: isSelected ? Colors.white : color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status['label'] as String,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                onSelected: (selected) {
                  if (selected && !isSelected) {
                    _updateStatus(status['value'] as String);
                  }
                },
                backgroundColor: color.withOpacity(0.1),
                selectedColor: color,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : color,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sipariş Ürünleri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(item.productName),
                      ),
                      Text('${item.quantity}x'),
                      const SizedBox(width: 8),
                      Text('₺${item.price.toStringAsFixed(2)}'),
                      const SizedBox(width: 8),
                      Text(
                        '₺${item.subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSection() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TOPLAM',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              '₺${_currentOrder.total.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notlar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_currentOrder.notes!),
          ],
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
        return Colors.green;
      case 'delivered':
        return Colors.grey;
      default:
        return Colors.red;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Beklemede';
      case 'preparing':
        return 'Hazırlanıyor';
      case 'ready':
        return 'Hazır';
      case 'delivered':
        return 'Teslim Edildi';
      default:
        return 'İptal';
    }
  }
}
