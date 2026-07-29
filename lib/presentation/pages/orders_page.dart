// lib/presentation/pages/orders_page.dart
// Serenut OS — Sipariş Yönetimi
// Phase 6 UI Redesign — Square/Loyverse POS Stili
// Revized: 22 Jun 2026

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/presentation/widgets/pos_filter_bar.dart';

import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';
import 'package:serenutos/config/theme.dart';

// ── Tema Sabitleri ────────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kAmberLight = POSColors.amberLight;
const _kAmberDark = POSColors.amberDark;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kSurface = POSColors.surface;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

// ── Durum Meta ────────────────────────────────────────────────────────────────
class _StatusMeta {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;
  const _StatusMeta(
      {required this.color,
      required this.bg,
      required this.icon,
      required this.label});
}

_StatusMeta _statusMeta(String status) {
  switch (status.toLowerCase()) {
    case 'created':
      return const _StatusMeta(
          color: Color(0xFF64748B),
          bg: Color(0xFFF1F5F9),
          icon: Icons.fiber_new_rounded,
          label: 'Yeni');
    case 'preparing':
      return const _StatusMeta(
          color: _kAmberDark,
          bg: _kAmberLight,
          icon: Icons.hourglass_top_rounded,
          label: 'Hazırlanıyor');
    case 'ready':
      return const _StatusMeta(
          color: _kGreen,
          bg: _kGreenLight,
          icon: Icons.check_circle_outline_rounded,
          label: 'Hazır');
    case 'delivered':
      return const _StatusMeta(
          color: _kGreenDark,
          bg: _kGreenLight,
          icon: Icons.local_shipping_rounded,
          label: 'Teslim Edildi');
    case 'cancelled':
      return const _StatusMeta(
          color: _kRed,
          bg: _kRedLight,
          icon: Icons.cancel_outlined,
          label: 'İptal');
    default:
      return const _StatusMeta(
          color: Color(0xFF64748B),
          bg: Color(0xFFF1F5F9),
          icon: Icons.help_outline_rounded,
          label: 'Bilinmiyor');
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
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Map<String, int> _statusCounts = {
    'all': 0,
    'created': 0,
    'preparing': 0,
    'ready': 0,
    'delivered': 0,
    'cancelled': 0
  };

  String _barcodeBuffer = '';
  DateTime? _lastBufferTime;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _scrollController.addListener(_onScroll);
    // Load initial status counts
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCounts());
  }

  Future<void> _refreshCounts() async {
    try {
      final counts =
          await ref.read(ordersControllerProvider.notifier).getStatusCounts();
      if (mounted) setState(() => _statusCounts = counts);
    } catch (_) {}
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(ordersControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _searchController.dispose();
    _scrollController.dispose();
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
    });
    ref.read(ordersControllerProvider.notifier).applySearch(barcode);
    _refreshCounts();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersControllerProvider);
    final customersVal = ref.watch(customersControllerProvider);

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
            onRetry: () =>
                ref.read(ordersControllerProvider.notifier).refresh(),
          ),
        ),
      ),
      data: (ordersList) {
        // Status counts come from controller (server-side) — refreshed on filter/search change
        final counts = _statusCounts;
        // No client-side filtering — the controller already returned the correct page
        final filtered = ordersList;

        return PosPageLayout(
          title: 'Siparişler',
          isSearching: _isSearching,
          onSearchToggled: (val) => setState(() => _isSearching = val),
          searchController: _searchController,
          searchHint: 'Sipariş veya müşteri ara...',
          onSearchChanged: (val) {
            ref.read(ordersControllerProvider.notifier).applySearch(val);
            _refreshCounts();
          },
          showRefresh: true,
          onRefresh: () =>
              ref.read(ordersControllerProvider.notifier).refresh(),
          filterWidget: PosFilterBar(
            padding: EdgeInsets.zero,
            selectedId: _statusFilter,
            onSelected: (newFilter) {
              setState(() => _statusFilter = newFilter);
              ref
                  .read(ordersControllerProvider.notifier)
                  .applyFilter(newFilter);
              _refreshCounts();
            },
            items: [
              PosFilterChipData(
                id: 'all',
                label: 'Tümü',
                count: counts['all'] ?? 0,
                icon: Icons.grid_view_rounded,
                color: const Color(0xFF64748B),
              ),
              PosFilterChipData(
                id: 'created',
                label: 'Yeni',
                count: counts['created'] ?? 0,
                icon: Icons.fiber_new_rounded,
                color: const Color(0xFF3B82F6),
              ),
              PosFilterChipData(
                id: 'preparing',
                label: 'Hazırlanıyor',
                count: counts['preparing'] ?? 0,
                icon: Icons.soup_kitchen_rounded,
                color: const Color(0xFFFF9500),
              ),
              PosFilterChipData(
                id: 'ready',
                label: 'Hazır',
                count: counts['ready'] ?? 0,
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF10B981),
              ),
              PosFilterChipData(
                id: 'delivered',
                label: 'Teslim Edildi',
                count: counts['delivered'] ?? 0,
                icon: Icons.local_shipping_rounded,
                color: const Color(0xFF6366F1),
              ),
              PosFilterChipData(
                id: 'cancelled',
                label: 'İptal',
                count: counts['cancelled'] ?? 0,
                icon: Icons.cancel_rounded,
                color: const Color(0xFFEF4444),
              ),
            ],
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
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      // Pagination footer
                      final hasMore =
                          ref.read(ordersControllerProvider.notifier).hasMore;
                      if (!hasMore) return const SizedBox.shrink();
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final order = filtered[index];
                    final customerName = customersVal.maybeWhen(
                      data: (list) {
                        final c = list.firstWhere(
                          (c) => c.id == order.customerId,
                          orElse: () => CustomerEntity(
                              id: '',
                              name: 'Bilinmeyen',
                              email: '',
                              phone: '',
                              balance: 0,
                              createdAt: DateTime.now()),
                        );
                        return c.name;
                      },
                      orElse: () => '...',
                    );
                    return _OrderCard(
                      order: order,
                      customerName: customerName,
                      onDetail: () =>
                          context.push('/orders/detail/${order.id}'),
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
            label: const Text('Yeni Sipariş',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
}

// ── Filtre Chip ───────────────────────────────────────────────────────────────

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
    final meta = _statusMeta(order.status);
    final dateStr = DateFormat('dd.MM.yy HH:mm').format(order.createdAt);
    final totalAmount = (order.items.fold<double>(0.0, (sum, item) {
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
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
                          const Icon(Icons.person_outline_rounded,
                              size: 13, color: _kTextSecondary),
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
                              const Icon(Icons.calendar_month_outlined,
                                  size: 13, color: _kTextSecondary),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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
      decoration: BoxDecoration(
          color: meta.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(meta.label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: meta.color)),
    );
  }
}

// ── Yardımcı State Widget'ları ────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen)),
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
              const Text('Siparişler yüklenemedi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(message,
                  style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
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
            Text(message,
                style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      );
}
