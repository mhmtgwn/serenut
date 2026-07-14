// lib/presentation/pages/customers_page.dart
// Serenut POS — Müşteriler Sayfası
// Yeşil + Sarı + Premium POS Teması
// Generated: 21 Jun 2026 (v2)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';

// ── POS Tema Renkleri ─────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber = Color(0xFFEAB308);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

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

    return PosPageLayout(
      title: 'Müşteriler',
      isSearching: _isSearching,
      onSearchToggled: (val) => setState(() => _isSearching = val),
      searchController: _searchController,
      searchHint: 'Müşteri adı veya telefon ile ara...',
      onSearchChanged: (val) {
        ref.read(customerSearchQueryProvider.notifier).state = val;
        setState(() {});
      },
      showRefresh: true,
      onRefresh: () => ref.read(customersControllerProvider.notifier).refresh(),
      body: customersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(_kGreen)),
        ),
        error: (err, _) => Center(
          child: Text('Müşteriler yüklenirken hata oluştu: $err'),
        ),
        data: (customersList) {
          if (customersList.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline_rounded,
                      size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text('Müşteri bulunamadı.',
                      style: TextStyle(color: _kTextSecondary)),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildSummaryBar(customersList),
              Expanded(
                child: ListView.builder(
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
                                backgroundColor:
                                    isDebt ? _kRedLight : _kGreenLight,
                                child: Text(
                                  customer.name.isNotEmpty
                                      ? customer.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: isDebt ? _kRed : _kGreenDark,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                              size: 13, color: _kTextSecondary),
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
                                              size: 13, color: _kTextSecondary),
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
                                      color: isDebt ? _kRedLight : _kGreenLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isDebt ? 'Vadeli Borç' : 'Alacak',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  isDebt ? _kRed : _kGreenDark,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '₺${absBalance.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: isDebt ? _kRed : _kGreenDark,
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
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_customers',
        onPressed: () => context.push('/customers/add'),
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Yeni Müşteri',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSummaryBar(List<CustomerEntity> customers) {
    final totalDebt = customers
        .where((c) => c.balance < 0)
        .fold(0.0, (sum, c) => sum + c.balance.abs());
    final totalCredit = customers
        .where((c) => c.balance > 0)
        .fold(0.0, (sum, c) => sum + c.balance);
    final debtorCount = customers.where((c) => c.balance < 0).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _SummaryChip(
              label: 'Toplam Borç',
              value: '₺${totalDebt.toStringAsFixed(2)}',
              count: '$debtorCount borçlu',
              color: _kRed,
              bg: _kRedLight,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryChip(
              label: 'Alacaklar',
              value: '₺${totalCredit.toStringAsFixed(2)}',
              count: '${customers.length} toplam',
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
