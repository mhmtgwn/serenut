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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Müşteri Bilgileri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person, size: 20),
                const SizedBox(width: 8),
                Text(_currentOrder.customerName),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone, size: 20),
                const SizedBox(width: 8),
                Text(_currentOrder.customerPhone),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.payment, size: 20),
                const SizedBox(width: 8),
                Text(_currentOrder.paymentMethod == 'cash' ? 'Nakit' : 'Kart'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sipariş Durumu',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Chip(
              label: Text(_getStatusText(_currentOrder.status)),
              backgroundColor:
                  _getStatusColor(_currentOrder.status).withOpacity(0.2),
              avatar: Icon(
                Icons.circle,
                color: _getStatusColor(_currentOrder.status),
                size: 12,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Durum Güncelle:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (_currentOrder.status == 'pending')
                  ElevatedButton(
                    onPressed: () => _updateStatus('preparing'),
                    child: const Text('Hazırlanıyor'),
                  ),
                if (_currentOrder.status == 'preparing')
                  ElevatedButton(
                    onPressed: () => _updateStatus('ready'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Hazır'),
                  ),
                if (_currentOrder.status == 'ready')
                  ElevatedButton(
                    onPressed: () => _updateStatus('delivered'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: const Text('Teslim Edildi'),
                  ),
              ],
            ),
          ],
        ),
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
