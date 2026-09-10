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

// ── Tema Sabitleri ────────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kAmberLight = POSColors.amberLight;
const _kAmberDark = POSColors.amberDark;
const _kRed = POSColors.red;
const _kSurface = POSColors.surface;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;



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
          title: _isSelecting
              ? (_selectedIds.isEmpty
                  ? 'Sipariş Seçin'
                  : '${_selectedIds.length} Sipariş Seçildi')
              : 'Siparişler',
          isSearching: _isSearching,
          onSearchToggled: (val) => setState(() => _isSearching = val),
          searchController: _searchController,
          searchHint: 'Sipariş veya müşteri ara...',
          onSearchChanged: (val) {
            ref.read(ordersControllerProvider.notifier).applySearch(val);
            _refreshCounts();
          },
          actions: [
            if (_isSelecting) ...[
              IconButton(
                tooltip: 'Teslim hariç tümünü seç',
                icon: const Icon(Icons.select_all_rounded),
                onPressed: () {
                  final selectableIds = filtered
                      .where((o) => o.status.toLowerCase() != 'delivered')
                      .map((o) => o.id)
                      .toSet();
                  setState(() {
                    if (_selectedIds.containsAll(selectableIds) &&
                        selectableIds.isNotEmpty) {
                      _selectedIds.clear();
                    } else {
                      _selectedIds.addAll(selectableIds);
                    }
                  });
                },
              ),
              IconButton(
                tooltip: 'Seçimden Çık',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    _isSelecting = false;
                    _selectedIds.clear();
                  });
                },
              ),
            ] else ...[
              IconButton(
                tooltip: 'Toplu Seçim',
                icon: const Icon(Icons.checklist_rounded),
                onPressed: () {
                  setState(() {
                    _isSelecting = true;
                  });
                },
              ),
            ],
          ],
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
                          if (isWide) {
                            return GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 520,
                                mainAxisExtent: 110,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: filtered.length +
                                  (isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == filtered.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
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
                                  );
                                }
                                final order = filtered[index];
                                final customerName = (order.customerName != null &&
                                        order.customerName!.trim().isNotEmpty)
                                    ? order.customerName!.trim()
                                    : (order.customerId.isEmpty
                                        ? 'Genel Müşteri'
                                        : (customerMapVal.valueOrNull?[order.customerId] ??
                                            (customerMapVal.isLoading
                                                ? '...'
                                                : 'Bilinmeyen Müşteri')));
                                final isDelivered = order.status.toLowerCase() == 'delivered';
                                final isSelected = _selectedIds.contains(order.id);
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
                                        _selectedIds.remove(order.id);
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
                            );
                          }

                          return ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length +
                                (isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == filtered.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
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
                                );
                              }
                              final order = filtered[index];
                              final customerName = (order.customerName != null &&
                                      order.customerName!.trim().isNotEmpty)
                                  ? order.customerName!.trim()
                                  : (order.customerId.isEmpty
                                      ? 'Genel Müşteri'
                                      : (customerMapVal.valueOrNull?[order.customerId] ??
                                          (customerMapVal.isLoading
                                              ? '...'
                                              : 'Bilinmeyen Müşteri')));
                              final isDelivered = order.status.toLowerCase() == 'delivered';
                              final isSelected = _selectedIds.contains(order.id);
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
                                      _selectedIds.remove(order.id);
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
              // ── Toplu İşlem Çubuğu (Floating Bar) ─────────────────────────
              if (_isSelecting && _selectedIds.isNotEmpty)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(30),
                      color: const Color(0xFF1E293B),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_selectedIds.length} Seçili',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                icon: const Icon(Icons.swap_horiz_rounded,
                                    size: 18),
                                label: const Text('Durum Değiştir'),
                                onPressed: _handleBulkStatusChange,
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFFCA5A5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                icon: const Icon(Icons.cancel_outlined,
                                    size: 18),
                                label: const Text('İptal Et'),
                                onPressed: _handleBulkCancel,
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFF87171),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Sil'),
                                onPressed: _handleBulkDelete,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: _isSelecting
              ? null
              : LayoutBuilder(
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

  // ── Toplu İşlem Yöneticileri ──────────────────────────────────────────────
  Future<void> _handleBulkStatusChange() async {
    if (_selectedIds.isEmpty) return;

    final selectedTarget = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Toplu Durum Güncelle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seçilen ${_selectedIds.length} sipariş için yeni durumu belirleyin:',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Text(
                'Bilgi: Teslim edilmiş olan siparişler toplu işleme kapalıdır ve etkilenmez.',
                style: TextStyle(fontSize: 12, color: Colors.brown),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              tileColor: _kAmberLight,
              leading: const Icon(Icons.hourglass_top_rounded,
                  color: _kAmberDark),
              title: const Text('Hazırlanıyor',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(dialogCtx, 'preparing'),
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              tileColor: _kGreenLight,
              leading: const Icon(Icons.check_circle_outline_rounded,
                  color: _kGreen),
              title: const Text('Hazır',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(dialogCtx, 'ready'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );

    if (selectedTarget == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final count = await ref
          .read(ordersControllerProvider.notifier)
          .bulkUpdateStatus(_selectedIds, selectedTarget);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$count sipariş durumu güncellendi.'),
          backgroundColor: _kGreen,
        ),
      );
      setState(() {
        _selectedIds.clear();
        _isSelecting = false;
      });
      await _refreshCounts();
    } catch (e, st) {
      TelemetryService().logError(e, st, context: 'orders_page_bulk_status_update');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Durum güncellenemedi: $e'),
          backgroundColor: _kRed,
        ),
      );
    }
  }

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
