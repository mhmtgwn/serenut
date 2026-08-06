// lib/presentation/pages/customers_page.dart
// Serenut OS — Müşteriler Sayfası
// Yeşil + Sarı + Premium POS Teması
// Generated: 21 Jun 2026 (v2)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/config/theme.dart';

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
const _kBorder = POSColors.border;

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.text = ref.read(customerSearchQueryProvider);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(customersControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersControllerProvider);
    final hasMore = ref.watch(customersControllerProvider.notifier).hasMoreData;
    final balanceFilter = ref.watch(customerBalanceFilterProvider);
    final balanceSummary = ref.watch(customerBalanceSummaryProvider);

    return PosPageLayout(
      title: 'Müşteriler',
      isSearching: _isSearching,
      onSearchToggled: (val) => setState(() => _isSearching = val),
      searchController: _searchController,
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
            child: customersAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_kGreen)),
              ),
              error: (err, _) => Center(
                child: Text('Müşteriler yüklenirken hata oluştu: $err'),
              ),
              data: (customersList) {
                if (customersList.isEmpty) {
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
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: customersList.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == customersList.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(_kGreen),
                            ),
                          ),
                        );
                      }
                      final customer = customersList[index];
                      final isDebt = customer.balance < 0;
                      final isClear = customer.balance == 0;
                      final absBalance = customer.balance.abs();

                      return GestureDetector(
                        onTap: () =>
                            context.push('/customers/detail/${customer.id}'),
                        child: Card(
                          color: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: _kBorder),
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: isDebt
                                      ? _kAmberLight
                                      : isClear
                                          ? POSColors.surfaceMuted
                                          : _kGreenLight,
                                  child: Text(
                                    customer.name.isNotEmpty
                                        ? customer.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: isDebt
                                          ? _kAmberDark
                                          : isClear
                                              ? _kTextSecondary
                                              : _kGreenDark,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: _kText),
                                      ),
                                      const SizedBox(height: 4),
                                      if (customer.phone.isNotEmpty)
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_rounded,
                                                size: 13,
                                                color: _kTextSecondary),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                customer.phone,
                                                style: const TextStyle(
                                                    color: _kTextSecondary,
                                                    fontSize: 12),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (customer.email.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.email_rounded,
                                                size: 13,
                                                color: _kTextSecondary),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                customer.email,
                                                style: const TextStyle(
                                                    color: _kTextSecondary,
                                                    fontSize: 12),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDebt
                                            ? _kAmberLight
                                            : isClear
                                                ? POSColors.surfaceMuted
                                                : _kGreenLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            isDebt
                                                ? 'Vadeli Borç'
                                                : isClear
                                                    ? 'Bakiye yok'
                                                    : 'Alacak',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: isDebt
                                                    ? _kAmberDark
                                                    : isClear
                                                        ? _kTextSecondary
                                                        : _kGreenDark,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '₺${absBalance.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              color: isDebt
                                                  ? _kAmberDark
                                                  : isClear
                                                      ? _kTextSecondary
                                                      : _kGreenDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Icon(Icons.chevron_right_rounded,
                                        color: _kTextSecondary, size: 18),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_customers',
        tooltip: 'Yeni müşteri',
        onPressed: () => context.push('/customers/add'),
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_rounded),
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
      default:
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
