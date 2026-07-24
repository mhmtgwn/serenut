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

import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';

// ── Tema Sabitleri ────────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmberLight = Color(0xFFFEF9C3);
const _kAmberDark = Color(0xFFB45309);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

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
  bool _showFilters = false;
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

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'created':
        return 'Yeni';
      case 'preparing':
        return 'Hazırlanıyor';
      case 'ready':
        return 'Hazır';
      case 'delivered':
        return 'Teslim Edildi';
      case 'cancelled':
        return 'İptal';
      default:
        return 'Tümü';
    }
  }

  Widget _buildFilterRow(
    BuildContext context, {
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    required Color statusColor,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? statusColor.withValues(alpha: 0.05)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? statusColor : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Colored left bar indicator
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                // Status icon
                Icon(
                  icon,
                  color: isSelected ? statusColor : const Color(0xFF64748B),
                  size: 20,
                ),
                const SizedBox(width: 12),
                // Status label
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? statusColor : const Color(0xFF334155),
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                // Item count badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? statusColor.withValues(alpha: 0.15)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? statusColor : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          filterWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _showFilters = !_showFilters),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list_rounded,
                          size: 16, color: _kGreenDark),
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
                      Icon(
                        _showFilters
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: _kTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
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
                  child: Column(
                    children: [
                      _buildFilterRow(
                        context,
                        label: 'Tümü',
                        count: counts['all'] ?? 0,
                        isSelected: _statusFilter == 'all',
                        onTap: () {
                          setState(() {
                            _statusFilter = 'all';
                            _showFilters = false;
                          });
                          ref
                              .read(ordersControllerProvider.notifier)
                              .applyFilter('all');
                          _refreshCounts();
                        },
                        statusColor: const Color(0xFF64748B),
                        icon: Icons.grid_view_rounded,
                      ),
                      _buildFilterRow(
                        context,
                        label: 'Yeni',
                        count: counts['created'] ?? 0,
                        isSelected: _statusFilter == 'created',
                        onTap: () {
                          setState(() {
                            _statusFilter = 'created';
                            _showFilters = false;
                          });
                          ref
                              .read(ordersControllerProvider.notifier)
                              .applyFilter('created');
                          _refreshCounts();
                        },
                        statusColor: const Color(0xFF3B82F6),
                        icon: Icons.fiber_new_rounded,
                      ),
                      _buildFilterRow(
                        context,
                        label: 'Hazırlanıyor',
                        count: counts['preparing'] ?? 0,
                        isSelected: _statusFilter == 'preparing',
                        onTap: () {
                          setState(() {
                            _statusFilter = 'preparing';
                            _showFilters = false;
                          });
                          ref
                              .read(ordersControllerProvider.notifier)
                              .applyFilter('preparing');
                          _refreshCounts();
                        },
                        statusColor: const Color(0xFFFF9500),
                        icon: Icons.soup_kitchen_rounded,
                      ),
                      _buildFilterRow(
                        context,
                        label: 'Hazır',
                        count: counts['ready'] ?? 0,
                        isSelected: _statusFilter == 'ready',
                        onTap: () {
                          setState(() {
                            _statusFilter = 'ready';
                            _showFilters = false;
                          });
                          ref
                              .read(ordersControllerProvider.notifier)
                              .applyFilter('ready');
                          _refreshCounts();
                        },
                        statusColor: const Color(0xFF10B981),
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      _buildFilterRow(
                        context,
                        label: 'Teslim Edildi',
                        count: counts['delivered'] ?? 0,
                        isSelected: _statusFilter == 'delivered',
                        onTap: () {
                          setState(() {
                            _statusFilter = 'delivered';
                            _showFilters = false;
                          });
                          ref
                              .read(ordersControllerProvider.notifier)
                              .applyFilter('delivered');
                          _refreshCounts();
                        },
                        statusColor: const Color(0xFF6366F1),
                        icon: Icons.local_shipping_rounded,
                      ),
                      _buildFilterRow(
                        context,
                        label: 'İptal',
                        count: counts['cancelled'] ?? 0,
                        isSelected: _statusFilter == 'cancelled',
                        onTap: () {
                          setState(() {
                            _statusFilter = 'cancelled';
                            _showFilters = false;
                          });
                          ref
                              .read(ordersControllerProvider.notifier)
                              .applyFilter('cancelled');
                          _refreshCounts();
                        },
                        statusColor: const Color(0xFFEF4444),
                        icon: Icons.cancel_rounded,
                      ),
                    ],
                  ),
                ),
                crossFadeState: _showFilters
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
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
