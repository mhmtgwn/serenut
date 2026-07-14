// lib/presentation/pages/sales_history_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/config/utils.dart';

const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kBlue = Color(0xFF2563EB);
const _kBlueLight = Color(0xFFDBEAFE);
const _kOrange = Color(0xFFEA580C);
const _kOrangeLight = Color(0xFFFFEDD5);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(salesHistoryControllerProvider.notifier).loadNextPage();
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
    final customersVal = ref.watch(customersControllerProvider);

    // Build customer map for fast lookups
    final customerMap = customersVal.maybeWhen(
      data: (list) => {for (final c in list) c.id: c.name},
      orElse: () => <String, String>{},
    );

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

          // Sales List
          Expanded(
            child: salesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_kGreen)),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child:
                      Text('Hata: $err', style: const TextStyle(color: _kRed)),
                ),
              ),
              data: (salesList) {
                // No Dart-side filtering: controller returns the correct page
                final filteredSales = salesList;

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

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredSales.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filteredSales.length) {
                      final hasMore = ref
                          .read(salesHistoryControllerProvider.notifier)
                          .hasMore;
                      if (!hasMore) return const SizedBox.shrink();
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final sale = filteredSales[index];
                    final customerName =
                        customerMap[sale.customerId] ?? 'Bilinmeyen Müşteri';
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

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () => context.push('/sales/detail/${sale.id}'),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
