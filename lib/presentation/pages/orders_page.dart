// lib/presentation/pages/orders_page.dart
// Serenut POS — Sipariş Yönetimi
// Phase 6 UI Redesign — Square/Loyverse POS Stili
// Revized: 22 Jun 2026

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/presentation/widgets/auth/pin_gate_dialog.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';

import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';
// ── Tema Sabitleri ────────────────────────────────────────────────────────────
const _kGreen      = Color(0xFF16A34A);
const _kGreenDark  = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber      = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kAmberDark  = Color(0xFFB45309);
const _kRed        = Color(0xFFDC2626);
const _kRedLight   = Color(0xFFFEE2E2);
const _kSurface    = Color(0xFFF8FAFC);
const _kText       = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder     = Color(0xFFE2E8F0);

// ── Durum Meta ────────────────────────────────────────────────────────────────
class _StatusMeta {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;
  const _StatusMeta({required this.color, required this.bg, required this.icon, required this.label});
}

_StatusMeta _statusMeta(String status) {
  switch (status.toLowerCase()) {
    case 'created':    return const _StatusMeta(color: Color(0xFF64748B), bg: Color(0xFFF1F5F9), icon: Icons.fiber_new_rounded,        label: 'Yeni');
    case 'preparing':  return const _StatusMeta(color: _kAmberDark,             bg: _kAmberLight,      icon: Icons.hourglass_top_rounded,      label: 'Hazırlanıyor');
    case 'ready':      return const _StatusMeta(color: _kGreen,           bg: _kGreenLight,      icon: Icons.check_circle_outline_rounded, label: 'Hazır');
    case 'delivered':  return const _StatusMeta(color: _kGreenDark,             bg: _kGreenLight,      icon: Icons.local_shipping_rounded,     label: 'Teslim Edildi');
    case 'cancelled':  return const _StatusMeta(color: _kRed,                   bg: _kRedLight,        icon: Icons.cancel_outlined,            label: 'İptal');
    default:           return const _StatusMeta(color: Color(0xFF64748B), bg: Color(0xFFF1F5F9), icon: Icons.help_outline_rounded,       label: 'Bilinmiyor');
  }
}

// ── Ana Sayfa ─────────────────────────────────────────────────────────────────
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});
  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  String _statusFilter = 'all';
  bool _isSearching = false;
  String _orderQuery = '';
  final _searchController = TextEditingController();

  String _barcodeBuffer = '';
  DateTime? _lastBufferTime;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _searchController.dispose();
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    try {
      final path = GoRouterState.of(context).uri.path;
      if (!path.startsWith('/orders')) return false;
    } catch (_) {}

    final now = DateTime.now();
    if (_lastBufferTime != null) {
      final diff = now.difference(_lastBufferTime!).inMilliseconds;
      if (diff > 80) {
        _barcodeBuffer = '';
      }
    }
    _lastBufferTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_barcodeBuffer.length >= 3) {
        final code = _barcodeBuffer;
        _barcodeBuffer = '';
        _onBarcodeScanned(code);
        return true;
      }
      _barcodeBuffer = '';
    } else {
      String? char = event.character;
      if (char == null) {
        final label = event.logicalKey.keyLabel;
        if (label.length == 1 && RegExp(r'[a-zA-Z0-9-]').hasMatch(label)) {
          char = label;
        }
      }
      if (char != null && char.length == 1) {
        _barcodeBuffer += char;
      }
    }
    return false;
  }

  void _onBarcodeScanned(String barcode) {
    setState(() {
      _isSearching = true;
      _searchController.text = barcode;
      _orderQuery = barcode;
    });
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'created':    return 'Yeni';
      case 'preparing':  return 'Hazırlanıyor';
      case 'ready':      return 'Hazır';
      case 'delivered':  return 'Teslim Edildi';
      case 'cancelled':  return 'İptal';
      default:           return 'Tümü';
    }
  }

  void _showStatusBottomSheet(BuildContext context, Map<String, int> counts) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Durum Filtrele',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildModalChip(
                        ctx,
                        label: 'Tümü',
                        count: counts['all']!,
                        isSelected: _statusFilter == 'all',
                        onTap: () {
                          setState(() => _statusFilter = 'all');
                          Navigator.pop(ctx);
                        },
                      ),
                      _buildModalChip(
                        ctx,
                        label: 'Yeni',
                        count: counts['created']!,
                        isSelected: _statusFilter == 'created',
                        onTap: () {
                          setState(() => _statusFilter = 'created');
                          Navigator.pop(ctx);
                        },
                      ),
                      _buildModalChip(
                        ctx,
                        label: 'Hazırlanıyor',
                        count: counts['preparing']!,
                        isSelected: _statusFilter == 'preparing',
                        onTap: () {
                          setState(() => _statusFilter = 'preparing');
                          Navigator.pop(ctx);
                        },
                      ),
                      _buildModalChip(
                        ctx,
                        label: 'Hazır',
                        count: counts['ready']!,
                        isSelected: _statusFilter == 'ready',
                        onTap: () {
                          setState(() => _statusFilter == 'ready');
                          Navigator.pop(ctx);
                        },
                      ),
                      _buildModalChip(
                        ctx,
                        label: 'Teslim Edildi',
                        count: counts['delivered']!,
                        isSelected: _statusFilter == 'delivered',
                        onTap: () {
                          setState(() => _statusFilter == 'delivered');
                          Navigator.pop(ctx);
                        },
                      ),
                      _buildModalChip(
                        ctx,
                        label: 'İptal',
                        count: counts['cancelled']!,
                        isSelected: _statusFilter == 'cancelled',
                        onTap: () {
                          setState(() => _statusFilter == 'cancelled');
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalChip(
    BuildContext context, {
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _kGreen : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kGreen : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF475569),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : _kGreenLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : _kGreenDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync   = ref.watch(ordersControllerProvider);
    final customersVal  = ref.watch(customersControllerProvider);

    return ordersAsync.when(
      loading: () => const Scaffold(
        backgroundColor: _kSurface,
        body: SafeArea(child: _LoadingView()),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: _kSurface,
        body: SafeArea(
          child: _ErrorView(
            message: err.toString(),
            onRetry: () => ref.read(ordersControllerProvider.notifier).refresh(),
          ),
        ),
      ),
      data: (ordersList) {
        // ── Sayaçlar ──
        final counts = {
          'all':       ordersList.length,
          'created':   ordersList.where((o) => o.status == 'created').length,
          'preparing': ordersList.where((o) => o.status == 'preparing').length,
          'ready':     ordersList.where((o) => o.status == 'ready').length,
          'delivered': ordersList.where((o) => o.status == 'delivered').length,
          'cancelled': ordersList.where((o) => o.status == 'cancelled').length,
        };

        final filtered = ordersList.where((o) {
          final matchesStatus = _statusFilter == 'all' || o.status == _statusFilter;
          if (_orderQuery.isEmpty) return matchesStatus;

          final query = _orderQuery.toLowerCase();
          final matchesId = o.id.toLowerCase().contains(query);

          // Find customer name
          final customerName = customersVal.maybeWhen(
            data: (list) {
              final c = list.firstWhere(
                (c) => c.id == o.customerId,
                orElse: () => CustomerEntity(id: '', name: '', email: '', phone: '', balance: 0, createdAt: DateTime.now()),
              );
              return c.name;
            },
            orElse: () => '',
          ).toLowerCase();

          final matchesCustomer = customerName.contains(query);
          return matchesStatus && (matchesId || matchesCustomer);
        }).toList();

        return PosPageLayout(
          title: 'Siparişler',
          isSearching: _isSearching,
          onSearchToggled: (val) => setState(() => _isSearching = val),
          searchController: _searchController,
          searchHint: 'Sipariş veya müşteri ara...',
          onSearchChanged: (val) => setState(() => _orderQuery = val),
          showRefresh: true,
          onRefresh: () => ref.read(ordersControllerProvider.notifier).refresh(),
          filterWidget: InkWell(
            onTap: () => _showStatusBottomSheet(context, counts),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_list_rounded, size: 16, color: _kGreenDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusFilter == 'all'
                          ? 'Durum: Tümü (${counts['all']})'
                          : 'Durum: ${_statusLabel(_statusFilter)} (${counts[_statusFilter]})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kText,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _kTextSecondary),
                ],
              ),
            ),
          ),
          body: filtered.isEmpty
              ? _EmptyView(
                  icon: Icons.receipt_long_rounded,
                  message: _statusFilter == 'all'
                      ? 'Henüz sipariş oluşturulmamış.'
                      : 'Bu kategoride sipariş yok.',
                  action: TextButton.icon(
                    onPressed: () => _showOrderForm(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Sipariş Oluştur'),
                    style: TextButton.styleFrom(foregroundColor: _kGreen),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    final customerName = customersVal.maybeWhen(
                      data: (list) {
                        final c = list.firstWhere(
                          (c) => c.id == order.customerId,
                          orElse: () => CustomerEntity(id: '', name: 'Bilinmeyen', email: '', phone: '', balance: 0, createdAt: DateTime.now()),
                        );
                        return c.name;
                      },
                      orElse: () => '...',
                    );
                    return _OrderCard(
                      order: order,
                      customerName: customerName,
                      onDetail: () => context.push('/orders/detail/${order.id}'),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab_orders',
            onPressed: () => _showOrderForm(context),
            backgroundColor: _kGreen,
            foregroundColor: Colors.white,
            elevation: 3,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Yeni Sipariş', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  // ── Sipariş Form Dialog ───────────────────────────────────────────────────
  void _showOrderForm(BuildContext context, {OrderEntity? existingOrder}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderCreationDialog(existingOrder: existingOrder),
        fullscreenDialog: true,
      ),
    );
  }

  void _confirmDelete(BuildContext context, OrderEntity order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Siparişi Sil'),
        content: const Text('Bu sipariş kaydını tamamen silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              ref.read(ordersControllerProvider.notifier).deleteOrder(order.id);
              ref.invalidate(dashboardProvider);
              ref.invalidate(productsControllerProvider);
              Navigator.pop(context);
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}

// ── Filtre Chip ───────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final String status;
  final String selected;
  final void Function(String) onTap;
  const _FilterChip({required this.label, required this.count, required this.status, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == status;
    final meta = status == 'all'
        ? const _StatusMeta(color: _kGreen, bg: _kGreenLight, icon: Icons.list_rounded, label: 'Tümü')
        : _statusMeta(status);

    return GestureDetector(
      onTap: () => onTap(status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? meta.color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? meta.color : _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : _kTextSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : meta.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : meta.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sipariş Kartı ─────────────────────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final OrderEntity order;
  final String customerName;
  final VoidCallback onDetail;

  const _OrderCard({
    required this.order,
    required this.customerName,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final meta      = _statusMeta(order.status);
    final dateStr   = DateFormat('dd.MM.yy HH:mm').format(order.createdAt);
    final totalAmount = (order.items.fold<double>(0.0, (sum, item) {
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final qty   = (item['quantity']   as num?)?.toDouble() ?? 0.0;
      return sum + price * qty;
    }));
    final itemCount = order.items.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onDetail,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // ── Sol Kısım: Durum Avatarı ─────────────────────────────────
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: meta.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    meta.icon,
                    color: meta.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),

                // ── Orta Kısım: Detaylar ─────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Sipariş #${order.id.toShortId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kText,
                            ),
                          ),
                          _StatusBadge(status: order.status),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 13, color: _kTextSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              customerName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _kText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_month_outlined, size: 13, color: _kTextSecondary),
                              const SizedBox(width: 4),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _kTextSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '•  $itemCount kalem',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _kTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // ── Sağ Kısım: Fiyat ve Yönlendirme Ok ────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _kGreenLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '₺${totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: _kGreenDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _kTextSecondary,
                      size: 20,
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
}

// ── Durum Badge ───────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: meta.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(meta.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: meta.color)),
    );
  }
}

// ── Yardımcı State Widget'ları ────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kGreen)),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 56, color: _kRed),
          const SizedBox(height: 16),
          const Text('Siparişler yüklenemedi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: _kTextSecondary, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar Dene'),
            style: ElevatedButton.styleFrom(backgroundColor: _kGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  const _EmptyView({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 72, color: Colors.grey[200]),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: _kTextSecondary, fontSize: 15, fontWeight: FontWeight.w500)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

