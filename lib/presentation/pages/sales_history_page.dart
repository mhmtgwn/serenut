// lib/presentation/pages/sales_history_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/config/theme.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kBlue = POSColors.blue;
const _kBlueLight = POSColors.blueLight;
const _kOrange = POSColors.orange;
const _kOrangeLight = POSColors.orangeLight;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kSurface = POSColors.surface;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _paymentFilter;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      final hasMore =
          ref.read(salesHistoryControllerProvider.notifier).hasMore;
      final loadingMore = ref.read(salesHistoryLoadingMoreProvider);
      if (hasMore && !loadingMore) {
        ref.read(salesHistoryControllerProvider.notifier).loadNextPage();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesHistoryControllerProvider);
    final isLoadingMore = ref.watch(salesHistoryLoadingMoreProvider);
    final hasMore = ref.watch(salesHistoryControllerProvider.notifier).hasMore;
    final customerMapVal = ref.watch(customerLookupMapProvider);

    // Build customer map for fast lookups
    final customerMap = customerMapVal.valueOrNull ?? const <String, String>{};

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        title: const Text(
          'Satış Geçmişi',
          style: TextStyle(
              fontWeight: FontWeight.w800, color: _kText, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _kText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kGreen),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() => _searchQuery = val);
                ref
                    .read(salesHistoryControllerProvider.notifier)
                    .applySearch(val);
              },
              decoration: InputDecoration(
                hintText: 'Satış no veya müşteri adı ara...',
                hintStyle:
                    const TextStyle(color: _kTextSecondary, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    size: 20, color: _kTextSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            size: 18, color: _kTextSecondary),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          ref
                              .read(salesHistoryControllerProvider.notifier)
                              .applySearch(null);
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kGreen, width: 1.5),
                ),
                filled: true,
                fillColor: _kSurface,
              ),
            ),
          ),
          const Divider(height: 1, color: _kBorder),
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(
                    'Tümü',
                    _paymentFilter == null && _statusFilter == null,
                    () => _applyFilters(null, null)),
                _filterChip('Nakit', _paymentFilter == 'cash',
                    () => _applyFilters('cash', null)),
                _filterChip('Kart', _paymentFilter == 'card',
                    () => _applyFilters('card', null)),
                _filterChip('Vadeli', _paymentFilter == 'debt',
                    () => _applyFilters('debt', null)),
                _filterChip('İptal', _statusFilter == 'cancelled',
                    () => _applyFilters(null, 'cancelled')),
              ],
            ),
          ),

          // Sales List
          Expanded(
            child: Builder(
              builder: (context) {
                final cachedSales = salesAsync.valueOrNull;
                if (cachedSales == null && salesAsync.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_kGreen)),
                  );
                }
                if (salesAsync.hasError && cachedSales == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Hata: ${salesAsync.error}',
                          style: const TextStyle(color: _kRed)),
                    ),
                  );
                }

                final filteredSales = cachedSales ?? const <SaleEntity>[];

                if (filteredSales.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_rounded,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        const Text(
                          'Kayıtlı satış bulunamadı.',
                          style: TextStyle(
                              color: _kTextSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 400) {
                      if (hasMore && !isLoadingMore) {
                        ref
                            .read(salesHistoryControllerProvider.notifier)
                            .loadNextPage();
                      }
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: () => ref
                        .read(salesHistoryControllerProvider.notifier)
                        .refresh(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredSales.length + (isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == filteredSales.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation(_kGreen)),
                            ),
                          );
                        }
                      final sale = filteredSales[index];
                      final customerName = sale.customerId.isEmpty
                          ? 'Genel Müşteri'
                          : (customerMap[sale.customerId] ?? 'Bilinmeyen Müşteri');
                      final dateStr = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR')
                          .format(sale.createdAt);

                      // Color and labels for payments
                      final paymentLabel = {
                            'cash': 'Nakit',
                            'nakit': 'Nakit',
                            'card': 'Kart',
                            'kart': 'Kart',
                            'debt': 'Vadeli',
                            'vadeli': 'Vadeli',
                            'mixed': 'Karma',
                            'karma': 'Karma',
                          }[sale.paymentMethod.toLowerCase()] ??
                          sale.paymentMethod;

                      final paymentColor = {
                            'cash': _kGreen,
                            'nakit': _kGreen,
                            'card': _kBlue,
                            'kart': _kBlue,
                            'debt': _kOrange,
                            'vadeli': _kOrange,
                            'mixed': _kGreenDark,
                            'karma': _kGreenDark,
                          }[sale.paymentMethod.toLowerCase()] ??
                          _kTextSecondary;

                      final paymentBg = {
                            'cash': _kGreenLight,
                            'nakit': _kGreenLight,
                            'card': _kBlueLight,
                            'kart': _kBlueLight,
                            'debt': _kOrangeLight,
                            'vadeli': _kOrangeLight,
                            'mixed': _kGreenLight,
                            'karma': _kGreenLight,
                          }[sale.paymentMethod.toLowerCase()] ??
                          _kSurface;

                      final isCancelled = sale.status == 'cancelled';
                      final isDebt = sale.paymentMethod.toLowerCase() == 'debt' ||
                          sale.paymentMethod.toLowerCase() == 'vadeli';
                      final Color accentColor = isCancelled
                          ? _kRed
                          : (isDebt ? const Color(0xFFD97706) : _kGreen);
                      final Color cardBg = isCancelled
                          ? const Color(0xFFFFF5F5)
                          : (isDebt
                              ? const Color(0xFFFFFDF5)
                              : const Color(0xFFF4FAF5));
                      final Color cardBorder = isCancelled
                          ? const Color(0xFFFCA5A5).withValues(alpha: 0.55)
                          : (isDebt
                              ? const Color(0xFFFCD34D).withValues(alpha: 0.55)
                              : const Color(0xFF86EFAC).withValues(alpha: 0.55));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cardBorder, width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: () => context.push('/sales/detail/${sale.id}'),
                          borderRadius: BorderRadius.circular(14),
                          splashColor: accentColor.withValues(alpha: 0.08),
                          highlightColor: accentColor.withValues(alpha: 0.04),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                // ── Sol Dikey Renk Vurgusu ─────────────────
                                Container(
                                  width: 4,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Icon
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        isCancelled ? _kRedLight : _kGreenLight,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isCancelled
                                        ? Icons.cancel_rounded
                                        : Icons.receipt_long_rounded,
                                    color: isCancelled ? _kRed : _kGreen,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '#${sale.id.toShortId}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: _kText,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (isCancelled) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _kRedLight,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'İPTAL',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w800,
                                                  color: _kRed,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        customerName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _kTextSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        dateStr,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Payment info & amount
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₺${sale.totalAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: isCancelled ? _kRed : _kText,
                                        decoration: isCancelled
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: paymentBg,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        paymentLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: paymentColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  void _applyFilters(String? paymentMethod, String? status) {
    setState(() {
      _paymentFilter = paymentMethod;
      _statusFilter = status;
    });
    ref.read(salesHistoryControllerProvider.notifier).applyFilters(
          paymentMethod: paymentMethod,
          status: status,
        );
  }
}
