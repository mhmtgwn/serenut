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
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/presentation/widgets/pos_filter_bar.dart';

import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';
import 'package:serenutos/config/theme.dart';

// ── Tema Sabitleri ────────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kAmber = POSColors.amber;
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
  String _timeFilter = 'all';
  bool _overdueOnly = false;
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
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 250) {
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

  Future<void> _applyAdvancedFilter(String period, bool overdueOnly) async {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    switch (period) {
      case 'today':
        from = DateTime(now.year, now.month, now.day);
        to = from.add(const Duration(days: 1));
        break;
      case '7d':
        from = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        to =
            DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        break;
      case '30d':
        from = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
        to =
            DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        break;
    }
    setState(() {
      _timeFilter = period;
      _overdueOnly = overdueOnly;
    });
    await ref.read(ordersControllerProvider.notifier).applyAdvancedFilter(
          dateFrom: from,
          dateTo: to,
          overdueOnly: overdueOnly,
        );
    await _refreshCounts();
  }

  Future<void> _showAdvancedFilterSheet() async {
    var period = _timeFilter;
    var overdue = _overdueOnly;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Siparişleri filtrele',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Tümü')),
                    ButtonSegment(value: 'today', label: Text('Bugün')),
                    ButtonSegment(value: '7d', label: Text('7 Gün')),
                    ButtonSegment(value: '30d', label: Text('30 Gün')),
                  ],
                  selected: {period},
                  onSelectionChanged: (value) =>
                      setSheetState(() => period = value.first),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Yalnızca gecikenler'),
                  subtitle: const Text(
                      'Teslim tarihi geçen açık siparişleri gösterir'),
                  value: overdue,
                  activeColor: _kGreen,
                  onChanged: (value) => setSheetState(() => overdue = value),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _applyAdvancedFilter(period, overdue);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Filtreyi Uygula'),
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
    final customerMapVal = ref.watch(customerLookupMapProvider);

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
              Badge(
                isLabelVisible: _timeFilter != 'all' || _overdueOnly,
                backgroundColor: _kAmber,
                child: IconButton(
                  tooltip: 'Tarih ve gecikme filtresi',
                  onPressed: _showAdvancedFilterSheet,
                  icon: const Icon(Icons.tune_rounded),
                ),
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
          body: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () =>
                    ref.read(ordersControllerProvider.notifier).refresh(),
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
                    : LayoutBuilder(
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
                              itemCount: filtered.length + 1,
                              itemBuilder: (context, index) {
                                if (index == filtered.length) {
                                  final notifier =
                                      ref.read(ordersControllerProvider.notifier);
                                  if (!notifier.hasMore) {
                                    return const SizedBox.shrink();
                                  }
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    notifier.loadNextPage();
                                  });
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation(_kGreen),
                                      ),
                                    ),
                                  );
                                }
                                final order = filtered[index];
                                final customerName = customerMapVal.maybeWhen(
                                  data: (map) =>
                                      map[order.customerId] ??
                                      'Bilinmeyen Müşteri',
                                  orElse: () => '...',
                                );
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
                                  onDetail: () =>
                                      context.push('/orders/detail/${order.id}'),
                                );
                              },
                            );
                          }

                          return ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length + 1,
                            itemBuilder: (context, index) {
                              if (index == filtered.length) {
                                final notifier =
                                    ref.read(ordersControllerProvider.notifier);
                                if (!notifier.hasMore) {
                                  return const SizedBox.shrink();
                                }
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  notifier.loadNextPage();
                                });
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      valueColor:
                                          AlwaysStoppedAnimation(_kGreen),
                                    ),
                                  ),
                                );
                              }
                              final order = filtered[index];
                              final customerName = customerMapVal.maybeWhen(
                                data: (map) =>
                                    map[order.customerId] ??
                                    'Bilinmeyen Müşteri',
                                orElse: () => '...',
                              );
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
                                onDetail: () =>
                                    context.push('/orders/detail/${order.id}'),
                              );
                            },
                          );
                        },
                      ),
              ),
              if (ordersAsync.isLoading)
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
              : FloatingActionButton(
                  heroTag: 'fab_orders',
                  tooltip: 'Yeni sipariş',
                  onPressed: () => _showOrderForm(context),
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  child: const Icon(Icons.add_shopping_cart_rounded),
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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

// ── Filtre Chip ───────────────────────────────────────────────────────────────

// ── Sipariş Kartı ─────────────────────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final OrderEntity order;
  final String customerName;
  final VoidCallback onDetail;
  final bool isGrid;
  final bool isSelecting;
  final bool isSelected;
  final bool isSelectable;
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback? onLongPress;

  const _OrderCard({
    required this.order,
    required this.customerName,
    required this.onDetail,
    this.isGrid = false,
    this.isSelecting = false,
    this.isSelected = false,
    this.isSelectable = true,
    this.onSelectChanged,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(order.status);
    final dateStr = DateFormat('dd.MM.yy HH:mm').format(order.createdAt);
    final subtotal = (order.items.fold<double>(0.0, (sum, item) {
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      return sum + price * qty;
    }));
    final totalAmount = order.totalAmount > 0 || order.discountAmount > 0
        ? order.totalAmount
        : subtotal;
    final itemCount = order.items.length;

    final card = Container(
      margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? _kGreen : _kBorder,
          width: isSelected ? 2 : 1,
        ),
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
          onTap: isSelecting
              ? () {
                  if (isSelectable) {
                    onSelectChanged?.call(!isSelected);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Teslim edilmiş siparişler toplu işlemden etkilenmez.'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                }
              : onDetail,
          onLongPress: !isSelecting ? onLongPress : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // ── Çoklu Seçim Durumu ─────────────────────────────────────
                if (isSelecting) ...[
                  if (!isSelectable)
                    const Tooltip(
                      message:
                          'Teslim edilmiş siparişler toplu işleme kapalıdır',
                      child: Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: isSelected,
                        activeColor: _kGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: onSelectChanged,
                      ),
                    ),
                ],

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
                            'Sipariş #${order.displayNumber}',
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
                    if (order.discountAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '₺${subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                            color: _kTextSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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

    if (isSelecting && !isSelectable) {
      return Opacity(
        opacity: 0.6,
        child: card,
      );
    }
    return card;
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
