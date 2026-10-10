// lib/presentation/pages/customers_page.dart
// Serenut OS — Müşteriler Sayfası
// Yeşil + Sarı + Premium POS Teması
// Generated: 21 Jun 2026 (v2)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/presentation/widgets/common/country_code_picker.dart';
import 'package:serenutos/presentation/controllers/installment_controller.dart';
import 'package:intl/intl.dart';

// ── POS Tema Renkleri ─────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kAmberDark = POSColors.amberDark;
const _kAmberLight = POSColors.amberLight;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.text = ref.read(customerSearchQueryProvider);
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged([String? value]) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final text = (value ?? _searchController.text).trim();
      ref.read(customerSearchQueryProvider.notifier).state = text;
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      final hasMore =
          ref.read(customersControllerProvider.notifier).hasMoreData;
      final loadingMore = ref.read(customerLoadingMoreProvider);
      if (hasMore && !loadingMore) {
        ref.read(customersControllerProvider.notifier).loadNextPage();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersControllerProvider);
    final isLoadingMore = ref.watch(customerLoadingMoreProvider);
    final balanceFilter = ref.watch(customerBalanceFilterProvider);
    final balanceSummary = ref.watch(customerBalanceSummaryProvider);
    final dueSummaryVal = ref.watch(dueInstallmentsSummaryProvider);
    final overdue = dueSummaryVal.valueOrNull?['overdue'] ?? 0;
    final today = dueSummaryVal.valueOrNull?['today'] ?? 0;

    return PosPageLayout(
      title: 'Müşteriler',
      isSearching: _isSearching,
      onSearchToggled: (val) {
        setState(() {
          _isSearching = val;
          if (!val) {
            _searchDebounce?.cancel();
            _searchController.clear();
            ref.read(customerSearchQueryProvider.notifier).state = '';
          }
        });
      },
      searchController: _searchController,
      onSearchChanged: (val) => _onSearchChanged(val),
      searchHint: 'Müşteri adı veya telefon ile ara...',
      actions: [
        Semantics(
          label: balanceFilter == CustomerBalanceFilter.all
              ? 'Bakiye filtresi'
              : 'Bakiye filtresi: ${_balanceFilterLabel(balanceFilter)}',
          button: true,
          child: Badge(
            isLabelVisible: balanceFilter != CustomerBalanceFilter.all,
            backgroundColor: _kAmberDark,
            smallSize: 8,
            child: IconButton(
              tooltip: balanceFilter == CustomerBalanceFilter.all
                  ? 'Bakiye filtresi'
                  : 'Filtre: ${_balanceFilterLabel(balanceFilter)}',
              onPressed: () => _showFilterSheet(balanceFilter),
              icon: Icon(
                Icons.filter_list_rounded,
                color: balanceFilter == CustomerBalanceFilter.all
                    ? _kTextSecondary
                    : _kGreen,
              ),
            ),
          ),
        ),
      ],
      body: Column(
        children: [
          _buildSummaryBar(balanceSummary),
          if (overdue > 0)
            InkWell(
              onTap: _showDueInstallmentsSheet,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: _kRedLight,
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: _kRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$overdue adet taksit vadesi gecikmiştir! Detaylar ve hatırlatma için tıklayın.',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _kRed),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: _kRed),
                  ],
                ),
              ),
            ),
          SizedBox(
            height: 46,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              children: [
                _balanceChip('Tümü', 'all'),
                _balanceChip('Borçlu', 'debt'),
                _balanceChip('Alacaklı', 'credit'),
                _balanceChip('Bakiyesi yok', 'clear'),
                if (overdue > 0 || today > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: Icon(
                        Icons.alarm_rounded,
                        size: 16,
                        color: overdue > 0 ? _kRed : _kAmberDark,
                      ),
                      label: Text(
                        overdue > 0
                            ? '$overdue Vadesi Geçmiş Taksit'
                            : '$today Bugün Vadeli Taksit',
                        style: TextStyle(
                          color: overdue > 0 ? _kRed : _kAmberDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor:
                          overdue > 0 ? _kRedLight : _kAmberLight,
                      side: BorderSide(
                        color: overdue > 0
                            ? _kRed.withValues(alpha: 0.5)
                            : _kAmberDark.withValues(alpha: 0.5),
                      ),
                      onPressed: _showDueInstallmentsSheet,
                    ),
                  ),
                if (balanceFilter != CustomerBalanceFilter.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Filtreyi temizle'),
                      onPressed: () => ref
                          .read(customerBalanceFilterProvider.notifier)
                          .state = CustomerBalanceFilter.all,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final customersList = customersAsync.valueOrNull ??
                    (ref.watch(customerSearchQueryProvider).isEmpty &&
                            ref.watch(customerBalanceFilterProvider) ==
                                CustomerBalanceFilter.all
                        ? ref
                            .watch(salesCustomersControllerProvider)
                            .valueOrNull
                        : null);

                if (customersList == null && customersAsync.isLoading) {
                  return Column(
                    children: [
                      const LinearProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_kGreen),
                        backgroundColor: _kGreenLight,
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: 6,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, __) => Container(
                            height: 68,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: POSColors.border),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (customersList == null && customersAsync.hasError) {
                  return Center(
                    child: Text(
                        'Müşteriler yüklenirken hata oluştu: ${customersAsync.error}'),
                  );
                }

                if (customersList == null || customersList.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => ref
                        .read(customersControllerProvider.notifier)
                        .refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.45,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline_rounded,
                                  size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              const Text('Müşteri bulunamadı.',
                                  style: TextStyle(color: _kTextSecondary)),
                              if (balanceFilter !=
                                  CustomerBalanceFilter.all) ...[
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: () => ref
                                      .read(customerBalanceFilterProvider
                                          .notifier)
                                      .state = CustomerBalanceFilter.all,
                                  icon: const Icon(Icons.filter_alt_off_rounded,
                                      size: 18),
                                  label: const Text('Filtreyi Temizle'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(customersControllerProvider.notifier).refresh(),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (scrollInfo) {
                      if (scrollInfo.metrics.pixels >=
                          scrollInfo.metrics.maxScrollExtent - 400) {
                        final canLoad = ref
                            .read(customersControllerProvider.notifier)
                            .hasMoreData;
                        final loading = ref.read(customerLoadingMoreProvider);
                        if (canLoad && !loading) {
                          ref
                              .read(customersControllerProvider.notifier)
                              .loadNextPage();
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
                            itemCount:
                                customersList.length + (isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == customersList.length) {
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
                              final customer = customersList[index];
                              return _CustomerCard(
                                customer: customer,
                                isGrid: true,
                                onTap: () => context.push(
                                    '/customers/detail/${customer.id}'),
                              );
                            },
                          );
                        }

                        return ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount:
                              customersList.length + (isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == customersList.length) {
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
                            final customer = customersList[index];
                            return _CustomerCard(
                              customer: customer,
                              isGrid: false,
                              onTap: () => context.push(
                                  '/customers/detail/${customer.id}'),
                            );
                          },
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
      floatingActionButton: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = MediaQuery.of(context).size.width >= 900;
          if (isDesktop) {
            return FloatingActionButton.extended(
              heroTag: 'fab_customers',
              tooltip: 'Yeni müşteri oluştur',
              onPressed: () => context.push('/customers/add'),
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Yeni Müşteri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            );
          }
          return FloatingActionButton(
            heroTag: 'fab_customers',
            tooltip: 'Yeni müşteri',
            onPressed: () => context.push('/customers/add'),
            backgroundColor: _kGreen,
            foregroundColor: Colors.white,
            child: const Icon(Icons.person_add_rounded),
          );
        },
      ),
    );
  }

  String _balanceFilterLabel(CustomerBalanceFilter filter) {
    switch (filter) {
      case CustomerBalanceFilter.debt:
        return 'Borçlu';
      case CustomerBalanceFilter.credit:
        return 'Alacaklı';
      case CustomerBalanceFilter.clear:
        return 'Bakiyesi yok';
      case CustomerBalanceFilter.all:
        return 'Tümü';
    }
  }

  Future<void> _showFilterSheet(CustomerBalanceFilter currentFilter) async {
    var pendingFilter = currentFilter;

    final result = await showModalBottomSheet<CustomerBalanceFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: .52,
          minChildSize: .35,
          maxChildSize: .80,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return Material(
                  color: POSColors.card,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadii.lg),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.sm,
                          AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Müşteri Bakiye Filtresi',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Kapat',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          children: [
                            RadioListTile<CustomerBalanceFilter>(
                              value: CustomerBalanceFilter.all,
                              groupValue: pendingFilter,
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() => pendingFilter = val);
                                }
                              },
                              secondary: const Icon(Icons.people_rounded),
                              title: const Text('Tüm Müşteriler'),
                            ),
                            RadioListTile<CustomerBalanceFilter>(
                              value: CustomerBalanceFilter.debt,
                              groupValue: pendingFilter,
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() => pendingFilter = val);
                                }
                              },
                              secondary: const Icon(
                                Icons.arrow_downward_rounded,
                                color: POSColors.red,
                              ),
                              title: const Text('Borçlu Müşteriler'),
                            ),
                            RadioListTile<CustomerBalanceFilter>(
                              value: CustomerBalanceFilter.credit,
                              groupValue: pendingFilter,
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() => pendingFilter = val);
                                }
                              },
                              secondary: const Icon(
                                Icons.arrow_upward_rounded,
                                color: POSColors.greenDark,
                              ),
                              title: const Text('Alacaklı Müşteriler'),
                            ),
                            RadioListTile<CustomerBalanceFilter>(
                              value: CustomerBalanceFilter.clear,
                              groupValue: pendingFilter,
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() => pendingFilter = val);
                                }
                              },
                              secondary: const Icon(
                                  Icons.remove_circle_outline_rounded),
                              title: const Text('Bakiyesi Olmayanlar'),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: const BoxDecoration(
                          color: POSColors.card,
                          border: Border(
                            top: BorderSide(color: POSColors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(
                                  context,
                                  CustomerBalanceFilter.all,
                                ),
                                child: const Text('Temizle'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(
                                  context,
                                  pendingFilter,
                                ),
                                child: const Text('Uygula'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    ref.read(customerBalanceFilterProvider.notifier).state = result;
  }

  Future<void> _showDueInstallmentsSheet() async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (sheetCtx, scrollCtrl) {
            return Material(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: Consumer(
                builder: (context, ref, _) {
                  final upcomingAsync =
                      ref.watch(upcomingInstallmentsProvider);
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                color: _kAmberDark),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Vadesi Gelen ve Geciken Taksitler',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _kText,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(sheetCtx),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: upcomingAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation(_kGreen)),
                          ),
                          error: (e, _) => Center(
                            child: Text('Yüklenemedi: $e',
                                style: const TextStyle(color: _kRed)),
                          ),
                          data: (items) {
                            if (items.isEmpty) {
                              return const Center(
                                child: Text(
                                    'Yakın zamanda vadesi gelen taksit bulunmuyor.'),
                              );
                            }
                            return ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final inst = items[idx];
                                final isOverdue = inst.isOverdue;
                                final isToday = inst.isDueToday;
                                final dateStr = inst.parsedDueDate != null
                                    ? DateFormat('dd.MM.yyyy')
                                        .format(inst.parsedDueDate!)
                                    : inst.dueDate;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 8),
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isOverdue
                                          ? _kRedLight
                                          : (isToday
                                              ? _kAmberLight
                                              : const Color(0xFFF1F5F9)),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      isOverdue
                                          ? Icons.warning_amber_rounded
                                          : Icons.event_rounded,
                                      size: 18,
                                      color: isOverdue
                                          ? _kRed
                                          : (isToday
                                              ? _kAmberDark
                                              : _kTextSecondary),
                                    ),
                                  ),
                                  title: Text(
                                    '${inst.installmentNo}. Taksit • $dateStr',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isOverdue ? _kRed : _kText,
                                    ),
                                  ),
                                  subtitle: Text(
                                    isOverdue
                                        ? 'Gecikti! Kalan: ₺${inst.remainingAmount.toStringAsFixed(2)}'
                                        : (isToday
                                            ? 'Bugün Son Gün! Kalan: ₺${inst.remainingAmount.toStringAsFixed(2)}'
                                            : 'Kalan: ₺${inst.remainingAmount.toStringAsFixed(2)}'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isOverdue
                                          ? _kRed
                                          : _kTextSecondary,
                                    ),
                                  ),
                                  trailing: const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                      color: _kTextSecondary),
                                  onTap: () {
                                    Navigator.pop(sheetCtx);
                                    context.push(
                                        '/customers/${inst.customerId}');
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _balanceChip(String label, String value) {
    final filter = _balanceFilterFromValue(value);
    final selected = ref.watch(customerBalanceFilterProvider) == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          ref.read(customerBalanceFilterProvider.notifier).state = filter;
        },
      ),
    );
  }

  CustomerBalanceFilter _balanceFilterFromValue(String value) =>
      switch (value) {
        'debt' => CustomerBalanceFilter.debt,
        'credit' => CustomerBalanceFilter.credit,
        'clear' => CustomerBalanceFilter.clear,
        _ => CustomerBalanceFilter.all,
      };

  Widget _buildSummaryBar(AsyncValue<CustomerBalanceSummary> summaryValue) {
    final summary = summaryValue.valueOrNull;
    final totalDebt = summary?.totalDebt ?? 0;
    final totalCredit = summary?.totalCredit ?? 0;
    final debtorCount = summary?.debtorCount ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _SummaryChip(
              label: '$debtorCount borçlu',
              value: '₺${totalDebt.toStringAsFixed(2)}',
              count: '',
              color: _kRed,
              bg: _kRedLight,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryChip(
              label: 'Alacak',
              value: '₺${totalCredit.toStringAsFixed(2)}',
              count: '',
              color: _kGreenDark,
              bg: _kGreenLight,
              icon: Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Özet Chip Widget ─────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final String count;
  final Color color;
  final Color bg;
  final IconData icon;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
    required this.bg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600)),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        color: color,
                        fontWeight: FontWeight.w900)),
                if (count.isNotEmpty)
                  Text(count,
                      style: TextStyle(
                          fontSize: 10, color: color.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Müşteri Kartı (Square/Loyverse POS Tasarımı) ───────────────────────────────
class _CustomerCard extends StatelessWidget {
  final CustomerEntity customer;
  final bool isGrid;
  final VoidCallback onTap;

  const _CustomerCard({
    required this.customer,
    required this.onTap,
    this.isGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDebt = customer.balance < 0;
    final isClear = customer.balance == 0;
    final absBalance = customer.balance.abs();
    final initial = customer.name.trim().isNotEmpty
        ? customer.name.trim()[0].toUpperCase()
        : '?';

    final Color cardBg;
    final Color cardBorder;
    final Color accentColor;
    final Color balanceBg;
    final Color balanceText;
    final Color avatarBg;
    final Color avatarText;

    if (isDebt) {
      // Borçlu: Mercan / Kırmızı
      cardBg = const Color(0xFFFFF5F5);
      cardBorder = const Color(0xFFFCA5A5).withValues(alpha: 0.55);
      accentColor = const Color(0xFFDC2626);
      balanceBg = const Color(0xFFFEE2E2);
      balanceText = const Color(0xFFDC2626);
      avatarBg = const Color(0xFFFEE2E2);
      avatarText = const Color(0xFFB91C1C);
    } else if (isClear) {
      // 0 Bakiye / Dengede: Dingin Nötr Gri
      cardBg = const Color(0xFFF8FAFC);
      cardBorder = const Color(0xFFCBD5E1).withValues(alpha: 0.55);
      accentColor = const Color(0xFF94A3B8);
      balanceBg = const Color(0xFFF1F5F9);
      balanceText = const Color(0xFF64748B);
      avatarBg = const Color(0xFFF1F5F9);
      avatarText = const Color(0xFF64748B);
    } else {
      // Alacaklı: Dingin Zümrüt Yeşili
      cardBg = const Color(0xFFF2FBF5);
      cardBorder = const Color(0xFF6EE7B7).withValues(alpha: 0.55);
      accentColor = const Color(0xFF059669);
      balanceBg = const Color(0xFFD1FAE5);
      balanceText = const Color(0xFF059669);
      avatarBg = const Color(0xFFD1FAE5);
      avatarText = const Color(0xFF047857);
    }

    return Container(
      margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cardBorder,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          splashColor: accentColor.withValues(alpha: 0.08),
          highlightColor: accentColor.withValues(alpha: 0.04),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // ── Sol Dikey Renk Vurgusu ──────────────────────────────────
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),

                // ── Sol Kısım: Avatar ─────────────────────────────────
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: avatarBg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: avatarText,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Orta Kısım: Detaylar ─────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        customer.name.toTurkishUpperCase,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _kText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      if (customer.phone.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined,
                                size: 13, color: _kTextSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                formatPhoneForDisplay(customer.phone),
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
                      if (customer.address != null &&
                          customer.address!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 13, color: _kTextSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  customer.address!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _kTextSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // ── Sağ Kısım: Bakiye ve Yönlendirme Ok ────────────────────────
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: balanceBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '₺${absBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: balanceText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
