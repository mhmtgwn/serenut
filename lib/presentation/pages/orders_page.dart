// lib/presentation/pages/orders_page.dart
// Serenut OS — Sipariş Yönetimi
// Phase 6 UI Redesign — Square/Loyverse POS Stili
// Revized: 22 Jun 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/presentation/widgets/pos_filter_bar.dart';

import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';
import 'package:serenutos/presentation/pages/order_details_page.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/mixins/barcode_scanner_mixin.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';


part 'orders/components/orders_status_meta.dart';
part 'orders/components/order_card.dart';
part 'orders/components/orders_views.dart';
part 'orders/components/order_date_group_header.dart';

// ── Tema Sabitleri ────────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kRed = POSColors.red;
const _kSurface = POSColors.surface;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;

String _formatGroupTitle(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;

  const dayNames = ['Pzt', 'Sal', 'Çrş', 'Per', 'Cum', 'Cts', 'Paz'];
  final dayName = dayNames[date.weekday - 1];
  final dateFormatted =
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} $dayName';

  if (diff == 0) {
    return 'Bugün • $dateFormatted';
  } else if (diff == 1) {
    return 'Dün • $dateFormatted';
  } else {
    return dateFormatted;
  }
}

List<OrderDayGroup> _groupOrdersByDay(List<OrderEntity> orders) {
  final Map<DateTime, List<OrderEntity>> grouped = {};
  for (final order in orders) {
    final d = order.createdAt;
    final dayKey = DateTime(d.year, d.month, d.day);
    grouped.putIfAbsent(dayKey, () => []).add(order);
  }

  final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return sortedKeys.map((k) {
    final list = grouped[k]!;
    final total = list.fold<double>(0.0, (sum, o) => sum + o.totalAmount);
    return OrderDayGroup(
      date: k,
      title: _formatGroupTitle(k),
      orders: list,
      totalAmount: total,
    );
  }).toList();
}



// ── Ana Sayfa ─────────────────────────────────────────────────────────────────
class OrdersPage extends ConsumerStatefulWidget {
  final String? initialStatusFilter;
  const OrdersPage({super.key, this.initialStatusFilter});
  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage>
    with BarcodeScannerMixin<OrdersPage> {
  late String _statusFilter;
  bool _isSearching = false;
  bool _isSelecting = false;
  final Set<String> _selectedIds = <String>{};
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

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatusFilter ?? 'all';
    initBarcodeScanner();
    _scrollController.addListener(_onScroll);
    // Load initial status counts and apply filter if passed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialStatusFilter != null && widget.initialStatusFilter != 'all') {
        ref.read(ordersControllerProvider.notifier).applyFilter(widget.initialStatusFilter!);
      }
      _refreshCounts();
    });
  }

  Future<void> _refreshCounts() async {
    try {
      final counts =
          await ref.read(ordersControllerProvider.notifier).getStatusCounts();
      if (mounted) setState(() => _statusCounts = counts);
    } catch (_) {}
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      final notifier = ref.read(ordersControllerProvider.notifier);
      final loadingMore = ref.read(ordersLoadingMoreProvider);
      if (notifier.hasMore && !loadingMore) {
        notifier.loadNextPage();
      }
    }
  }

  @override
  void dispose() {
    disposeBarcodeScanner();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool canHandleBarcodeScan() {
    if (!super.canHandleBarcodeScan()) return false;
    try {
      final path = GoRouterState.of(context).uri.path;
      return path.startsWith('/orders');
    } catch (_) {
      return true;
    }
  }

  @override
  void onBarcodeScanned(String barcode) {
    var query = barcode.trim();
    if (query.startsWith('order|')) {
      final parts = query.split('|');
      if (parts.length > 1 && parts[1].isNotEmpty) {
        query = parts[1];
      }
    }
    setState(() {
      _isSearching = true;
      _searchController.text = query;
    });
    ref.read(ordersControllerProvider.notifier).applySearch(query);
    _refreshCounts();
  }



  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersControllerProvider);
    final customerMapVal = ref.watch(customerLookupMapProvider);
    final isLoadingMore = ref.watch(ordersLoadingMoreProvider);

    final ordersList = ordersAsync.valueOrNull;

    if (ordersList == null && ordersAsync.isLoading) {
      return const Scaffold(
        backgroundColor: _kSurface,
        body: SafeArea(child: _LoadingView()),
      );
    }

    if (ordersList == null && ordersAsync.hasError) {
      return Scaffold(
        backgroundColor: _kSurface,
        body: SafeArea(
          child: _ErrorView(
            message: ordersAsync.error.toString(),
            onRetry: () =>
                ref.read(ordersControllerProvider.notifier).refresh(),
          ),
        ),
      );
    }

    final filtered = ordersList ?? const <OrderEntity>[];
    final counts = _statusCounts;

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
          filterWidget: LayoutBuilder(
            builder: (context, constraints) {
              final isWideScreen = constraints.maxWidth >= 960;
              final filterBar = PosFilterBar(
                padding: EdgeInsets.zero,
                selectedId: _statusFilter,
                onSelected: (newFilter) {
                  setState(() => _statusFilter = newFilter);
                  ref
                      .read(ordersControllerProvider.notifier)
                      .applyFilter(newFilter);
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
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF16A34A),
                  ),
                  PosFilterChipData(
                    id: 'delivered',
                    label: 'Teslim Edildi',
                    count: counts['delivered'] ?? 0,
                    icon: Icons.task_alt_rounded,
                    color: const Color(0xFF475569),
                  ),
                  PosFilterChipData(
                    id: 'cancelled',
                    label: 'İptal',
                    count: counts['cancelled'] ?? 0,
                    icon: Icons.cancel_rounded,
                    color: const Color(0xFFEF4444),
                  ),
                ],
              );

              if (_isSelecting && _selectedIds.isNotEmpty) {
                if (isWideScreen) {
                  return Row(
                    children: [
                      Expanded(child: filterBar),
                      const SizedBox(width: 12),
                      _buildQuickActionBar(),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    filterBar,
                    const SizedBox(height: 8),
                    _buildQuickActionBar(),
                  ],
                );
              }

              return filterBar;
            },
          ),
          body: Stack(
            children: [
              RefreshIndicator(
                color: _kGreen,
                onRefresh: () async {
                  await ref.read(ordersControllerProvider.notifier).refresh();
                  await _refreshCounts();
                },
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * .55,
                            child: _EmptyView(
                              icon: Icons.receipt_long_rounded,
                              message: _statusFilter == 'all'
                                  ? 'Henüz sipariş oluşturulmamış.'
                                  : 'Bu kategoride sipariş yok.',
                              action: TextButton.icon(
                                onPressed: () => _showOrderForm(context),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Sipariş Oluştur'),
                                style:
                                    TextButton.styleFrom(foregroundColor: _kGreen),
                              ),
                            ),
                          ),
                        ],
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (scrollInfo) {
                          if (scrollInfo.metrics.pixels >=
                              scrollInfo.metrics.maxScrollExtent - 400) {
                            final notifier =
                                ref.read(ordersControllerProvider.notifier);
                            final loadingMore =
                                ref.read(ordersLoadingMoreProvider);
                            if (notifier.hasMore && !loadingMore) {
                              notifier.loadNextPage();
                            }
                          }
                          return false;
                        },
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 720;
                            final dayGroups = _groupOrdersByDay(filtered);

                            return CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              controller: _scrollController,
                              slivers: [
                                for (final group in dayGroups) ...[
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: _OrderDateGroupHeader(
                                        group: group,
                                        isSelecting: _isSelecting,
                                        isAllSelected: group
                                                .selectableIds.isNotEmpty &&
                                            group.selectableIds.every((id) =>
                                                _selectedIds.contains(id)),
                                        onToggleSelectAll: () {
                                          final selectable =
                                              group.selectableIds;
                                          final allSelected = selectable
                                                  .isNotEmpty &&
                                              selectable.every((id) =>
                                                  _selectedIds.contains(id));
                                          setState(() {
                                            if (allSelected) {
                                              _selectedIds
                                                  .removeAll(selectable);
                                              if (_selectedIds.isEmpty) {
                                                _isSelecting = false;
                                              }
                                            } else {
                                              _selectedIds.addAll(selectable);
                                              _isSelecting = true;
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  if (isWide)
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 4, 16, 12),
                                      sliver: SliverGrid(
                                        gridDelegate:
                                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 520,
                                          mainAxisExtent: 110,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                        ),
                                        delegate:
                                            SliverChildBuilderDelegate(
                                          (context, index) {
                                            final order =
                                                group.orders[index];
                                            final customerName =
                                                (order.customerName != null &&
                                                        order.customerName!
                                                            .trim()
                                                            .isNotEmpty)
                                                    ? order.customerName!.trim()
                                                    : (order.customerId.isEmpty
                                                        ? 'Genel Müşteri'
                                                        : (customerMapVal
                                                                .valueOrNull?[
                                                            order
                                                                .customerId] ??
                                                            (customerMapVal
                                                                    .isLoading
                                                                ? '...'
                                                                : 'Bilinmeyen Müşteri')));
                                            final isDelivered =
                                                order.status.toLowerCase() ==
                                                    'delivered';
                                            final isSelected = _selectedIds
                                                .contains(order.id);
                                            return _OrderCard(
                                              order: order,
                                              customerName: customerName,
                                              isGrid: true,
                                              isSelecting: _isSelecting,
                                              isSelected: isSelected,
                                              isSelectable: !isDelivered,
                                              onSelectChanged: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedIds.add(order.id);
                                                  } else {
                                                    _selectedIds
                                                        .remove(order.id);
                                                  }
                                                });
                                              },
                                              onLongPress: () {
                                                if (!isDelivered) {
                                                  setState(() {
                                                    _isSelecting = true;
                                                    _selectedIds.add(order.id);
                                                  });
                                                }
                                              },
                                              onDetail: () {
                                                OrderDetailsPage.show(context,
                                                        orderId: order.id)
                                                    .then((_) {
                                                  if (mounted) _refreshCounts();
                                                });
                                              },
                                            );
                                          },
                                          childCount: group.orders.length,
                                        ),
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 4, 16, 12),
                                      sliver: SliverList(
                                        delegate:
                                            SliverChildBuilderDelegate(
                                          (context, index) {
                                            final order =
                                                group.orders[index];
                                            final customerName =
                                                (order.customerName != null &&
                                                        order.customerName!
                                                            .trim()
                                                            .isNotEmpty)
                                                    ? order.customerName!.trim()
                                                    : (order.customerId.isEmpty
                                                        ? 'Genel Müşteri'
                                                        : (customerMapVal
                                                                .valueOrNull?[
                                                            order
                                                                .customerId] ??
                                                            (customerMapVal
                                                                    .isLoading
                                                                ? '...'
                                                                : 'Bilinmeyen Müşteri')));
                                            final isDelivered =
                                                order.status.toLowerCase() ==
                                                    'delivered';
                                            final isSelected = _selectedIds
                                                .contains(order.id);
                                            return _OrderCard(
                                              order: order,
                                              customerName: customerName,
                                              isGrid: false,
                                              isSelecting: _isSelecting,
                                              isSelected: isSelected,
                                              isSelectable: !isDelivered,
                                              onSelectChanged: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedIds.add(order.id);
                                                  } else {
                                                    _selectedIds
                                                        .remove(order.id);
                                                  }
                                                });
                                              },
                                              onLongPress: () {
                                                if (!isDelivered) {
                                                  setState(() {
                                                    _isSelecting = true;
                                                    _selectedIds.add(order.id);
                                                  });
                                                }
                                              },
                                              onDetail: () {
                                                OrderDetailsPage.show(context,
                                                        orderId: order.id)
                                                    .then((_) {
                                                  if (mounted) _refreshCounts();
                                                });
                                              },
                                            );
                                          },
                                          childCount: group.orders.length,
                                        ),
                                      ),
                                    ),
                                ],
                                if (isLoadingMore)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 16),
                                      child: Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor:
                                                AlwaysStoppedAnimation(_kGreen),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
              if (ordersAsync.isLoading && filtered.isEmpty)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2.5,
                    valueColor: AlwaysStoppedAnimation(_kGreen),
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ],
          ),
          floatingActionButton: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = MediaQuery.of(context).size.width >= 900;
                    if (isDesktop) {
                      return FloatingActionButton.extended(
                        heroTag: 'fab_orders',
                        tooltip: 'Yeni sipariş oluştur',
                        onPressed: () => _showOrderForm(context),
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('Yeni Sipariş',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      );
                    }
                    return FloatingActionButton(
                      heroTag: 'fab_orders',
                      tooltip: 'Yeni sipariş',
                      onPressed: () => _showOrderForm(context),
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      elevation: 3,
                      child: const Icon(Icons.add_shopping_cart_rounded),
                    );
                  },
                ),
        );
  }

  Widget _buildQuickActionBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Text(
              '${_selectedIds.length} Seçildi',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kText,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildBatchButton(
            label: 'Tümünü Seç',
            icon: Icons.select_all_rounded,
            color: const Color(0xFF3B82F6),
            onTap: () {
              final orders =
                  ref.read(ordersControllerProvider).valueOrNull ?? [];
              final selectableIds = orders
                  .where((o) => o.status.toLowerCase() != 'delivered')
                  .map((o) => o.id)
                  .toSet();
              setState(() {
                if (_selectedIds.containsAll(selectableIds) &&
                    selectableIds.isNotEmpty) {
                  _selectedIds.clear();
                  _isSelecting = false;
                } else {
                  _selectedIds.addAll(selectableIds);
                }
              });
            },
          ),
          const SizedBox(width: 8),
          _buildBatchButton(
            label: 'Hazırlanıyor',
            icon: Icons.soup_kitchen_rounded,
            color: const Color(0xFFFF9500),
            onTap: () => _handleBulkDirectStatusChange('preparing'),
          ),
          const SizedBox(width: 6),
          _buildBatchButton(
            label: 'Hazır',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF16A34A),
            onTap: () => _handleBulkDirectStatusChange('ready'),
          ),
          const SizedBox(width: 6),
          _buildBatchButton(
            label: 'Teslim Edildi',
            icon: Icons.task_alt_rounded,
            color: const Color(0xFF475569),
            onTap: () => _handleBulkDirectStatusChange('delivered'),
          ),
          const SizedBox(width: 6),
          _buildBatchButton(
            label: 'İptal',
            icon: Icons.cancel_rounded,
            color: const Color(0xFFEF4444),
            onTap: _handleBulkCancel,
          ),
          const SizedBox(width: 6),
          _buildBatchButton(
            label: 'Sil',
            icon: Icons.delete_outline_rounded,
            color: const Color(0xFFEF4444),
            onTap: _handleBulkDelete,
          ),
          const SizedBox(width: 6),
          _buildBatchButton(
            label: 'Vazgeç',
            icon: Icons.close_rounded,
            color: const Color(0xFF64748B),
            onTap: () {
              setState(() {
                _isSelecting = false;
                _selectedIds.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBatchButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color == const Color(0xFF64748B) ? _kText : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBulkDirectStatusChange(String targetStatus) async {
    if (_selectedIds.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final count = await ref
          .read(ordersControllerProvider.notifier)
          .bulkUpdateStatus(_selectedIds, targetStatus);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$count sipariş durumu güncellendi.'),
          backgroundColor: _kGreen,
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {
        _selectedIds.clear();
        _isSelecting = false;
      });
      await _refreshCounts();
    } catch (e, st) {
      TelemetryService().logError(e, st, context: 'orders_page_bulk_direct_status');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Durum güncellenemedi: $e'),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  // ── Toplu İşlem Yöneticileri ──────────────────────────────────────────────

  Future<void> _handleBulkCancel() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Toplu Sipariş İptali'),
        content: Text(
          'Seçilen ${_selectedIds.length} siparişi iptal etmek istiyor musunuz?\n\n'
          '• Ayrılan stok miktarları otomatik olarak iade edilecektir.\n'
          '• Teslim edilmiş siparişler iptal edilemez ve korunur.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kRed),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final count = await ref
          .read(ordersControllerProvider.notifier)
          .bulkCancelOrders(_selectedIds);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$count sipariş başarıyla iptal edildi.'),
          backgroundColor: _kGreen,
        ),
      );
      setState(() {
        _selectedIds.clear();
        _isSelecting = false;
      });
      await _refreshCounts();
    } catch (e, st) {
      TelemetryService().logError(e, st, context: 'orders_page_bulk_cancel');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Siparişler iptal edilemedi: $e'),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  Future<void> _handleBulkDelete() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Toplu Sipariş Silme'),
        content: Text(
          'Seçilen ${_selectedIds.length} siparişi kalıcı olarak silmek istediğinizden emin misiniz?\n\n'
          '⚠️ Bu işlem geri alınamaz!\n'
          '⚠️ Teslim edilmiş siparişler korunur ve silinmez.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kRed),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Kalıcı Olarak Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final count = await ref
          .read(ordersControllerProvider.notifier)
          .bulkDeleteOrders(_selectedIds);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$count sipariş başarıyla silindi.'),
          backgroundColor: _kGreen,
        ),
      );
      setState(() {
        _selectedIds.clear();
        _isSelecting = false;
      });
      await _refreshCounts();
    } catch (e, st) {
      TelemetryService().logError(e, st, context: 'orders_page_bulk_delete');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Siparişler silinemedi: $e'),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  // ── Sipariş Form Dialog ───────────────────────────────────────────────────
  void _showOrderForm(BuildContext context, {OrderEntity? existingOrder}) {
    OrderCreationDialog.show(context, existingOrder: existingOrder);
  }
}
