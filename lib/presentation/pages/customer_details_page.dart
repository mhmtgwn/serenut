// lib/presentation/pages/customer_details_page.dart
// Serenut POS — Müşteri Detay Sayfası (Bankacılık Stili)
// UX Redesign v3: Hero gradient card, bank-statement transaction list, 
// full-screen collection push (no dialog). Uses existing providers — zero backend changes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/widgets/export_bottom_sheet.dart';
import 'package:serenutos/presentation/pages/customer/ledger_explainability_sheet.dart';

const _kGreen      = Color(0xFF16A34A);
const _kGreenDark  = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kRed        = Color(0xFFDC2626);
const _kRedLight   = Color(0xFFFEE2E2);
const _kAmber      = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kSurface    = Color(0xFFF8FAFC);
const _kText       = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder     = Color(0xFFE2E8F0);

class CustomerDetailsPage extends ConsumerWidget {
  final String customerId;
  const CustomerDetailsPage({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersVal   = ref.watch(customersControllerProvider);
    final transactionsVal = ref.watch(customerTransactionsProvider(customerId));
    final balanceVal     = ref.watch(customerBalanceDetailsProvider(customerId));

    final customer = customersVal.maybeWhen(
      data: (list) {
        try { return list.firstWhere((c) => c.id == customerId); } catch (_) { return null; }
      },
      orElse: () => null,
    );

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: _kGreenDark),
          title: const Text('Müşteri Detayı',
              style: TextStyle(color: _kText, fontWeight: FontWeight.bold)),
        ),
        body: const Center(child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen))),
      );
    }

    final isDebt = customer.balance < 0;

    return Scaffold(
      backgroundColor: _kSurface,
      body: CustomScrollView(
        slivers: [
          // ── Hero AppBar + Gradient Card ─────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDebt ? _kRed : _kGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
                tooltip: 'Düzenle',
                onPressed: () =>
                    context.push('/customers/edit/${customer.id}', extra: customer),
              ),
              if (customer.id.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  tooltip: 'Sil',
                  onPressed: () => _confirmDelete(context, ref, customer),
                ),
              // ── Phase 4: PDF / Excel / SMS Export Button ──
              IconButton(
                icon: const Icon(Icons.upload_rounded, color: Colors.white),
                tooltip: 'Dışa Aktar',
                onPressed: () {
                  final txs = transactionsVal.maybeWhen(
                    data: (list) => list,
                    orElse: () => <FinancialTransactionEntity>[],
                  );
                  ExportBottomSheet.show(
                    context,
                    customer: customer,
                    transactions: txs,
                  );
                },
              ),
              // ── Phase 4: Ledger Explainability & Verification Button ──
              IconButton(
                icon: const Icon(Icons.history_toggle_off_rounded, color: Colors.white),
                tooltip: 'Bakiye Analiz & Doğrulama',
                onPressed: () => LedgerExplainabilitySheet.show(context, customer),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDebt
                        ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                        : [const Color(0xFF16A34A), const Color(0xFF15803D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      // Avatar
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          customer.name.isNotEmpty
                              ? customer.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 28),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        customer.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customer.phone.isNotEmpty
                            ? customer.phone
                            : customer.email.isNotEmpty
                                ? customer.email
                                : 'Kayıt: ${DateFormat('dd.MM.yyyy').format(customer.createdAt)}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bakiye Özet Satırı ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: balanceVal.when(
                loading: () => const SizedBox(height: 80,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                error: (e, _) => Text('Bakiye yüklenemedi: $e',
                    style: const TextStyle(color: _kRed)),
                data: (details) => _buildBalanceRow(customer, details),
              ),
            ),
          ),

          // ── Tahsilat Butonu ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      context.push('/customers/$customerId/collect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.price_check_rounded, size: 22),
                  label: const Text(
                    'Tahsilat Yap',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),

          // ── Banka Ekstresi: İşlem Geçmişi ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: _kGreenLight, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.receipt_long_rounded,
                        size: 14, color: _kGreenDark),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Hareket Geçmişi',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, color: _kText),
                  ),
                ],
              ),
            ),
          ),

          transactionsVal.when(
            loading: () => const SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_kGreen)),
                  )),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Hareketler yüklenemedi: $e',
                    style: const TextStyle(color: _kRed)),
              ),
            ),
            data: (txns) {
              if (txns.isEmpty) {
                return SliverToBoxAdapter(child: _buildEmptyState());
              }
              // Group by month
              final grouped = _groupByMonth(txns);
              final months = grouped.keys.toList();

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final month = months[idx];
                    final items = grouped[month]!;
                    return _buildMonthGroup(month, items);
                  },
                  childCount: months.length,
                ),
              );
            },
          ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── Bakiye Özet Satırı ────────────────────────────────────────────────────

  Widget _buildBalanceRow(
      CustomerEntity customer, Map<String, double> details) {
    final isDebt = customer.balance < 0;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Net Bakiye',
            value: '₺${customer.balance.abs().toStringAsFixed(2)}',
            sub: isDebt ? 'Borçlu' : 'Alacaklı',
            bg: isDebt ? _kRedLight : _kGreenLight,
            fg: isDebt ? _kRed : _kGreenDark,
            icon: isDebt
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Toplam Borç',
            value: '₺${(details['totalDebt'] ?? 0).toStringAsFixed(2)}',
            sub: 'Vadeli satışlar',
            bg: _kAmberLight,
            fg: _kAmber,
            icon: Icons.warning_amber_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Toplam Ödeme',
            value: '₺${(details['totalPaid'] ?? 0).toStringAsFixed(2)}',
            sub: 'Tahsilatlar',
            bg: _kGreenLight,
            fg: _kGreenDark,
            icon: Icons.check_circle_rounded,
          ),
        ),
      ],
    );
  }

  // ── Aylara Göre Gruplama ──────────────────────────────────────────────────

  Map<String, List<FinancialTransactionEntity>> _groupByMonth(
      List<FinancialTransactionEntity> txns) {
    final sorted = List.of(txns)..sort((a, b) => b.date.compareTo(a.date));
    final map = <String, List<FinancialTransactionEntity>>{};
    for (final txn in sorted) {
      final key = DateFormat('MMMM yyyy', 'tr_TR').format(txn.date);
      map.putIfAbsent(key, () => []).add(txn);
    }
    return map;
  }

  Widget _buildMonthGroup(String month, List<FinancialTransactionEntity> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              month.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _kTextSecondary,
                  letterSpacing: 0.8),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _TransactionRow(txn: items[i]),
                  if (i < items.length - 1)
                    const Divider(height: 1, indent: 56, endIndent: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 52, color: _kBorder),
          SizedBox(height: 12),
          Text(
            'Henüz hareket yok',
            style: TextStyle(
                color: _kTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'İlk satış veya tahsilat yapıldığında burada görünür.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTextSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, CustomerEntity customer) {
    requireAdminAccess(
      context,
      title: 'Müşteri Silme Yetkisi',
      requirePin: true,
      onGranted: (approvedByUserId, approvedByUserName) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Müşteriyi Sil'),
              content: Text('"${customer.name}" müşterisini sistemden silmek istediğinize emin misiniz?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await ref.read(customersControllerProvider.notifier).deleteCustomer(
                      customer.id,
                      approvedByUserId: approvedByUserId,
                      approvedByUserName: approvedByUserName,
                    );
                  final state = ref.read(customersControllerProvider);
                  if (state.hasError) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Müşteri silinemedi: Bu müşteriye ait satış veya işlem kayıtları bulunmaktadır.'),
                          backgroundColor: _kRed,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } else {
                    ref.invalidate(dashboardProvider);
                    if (context.mounted) {
                      context.pop();
                    }
                  }
                },
                child: const Text('Sil'),
              ),
            ],
          );
        },
      );
    });
  }
}

// ── Yardımcı Veri Sınıfları ────────────────────────────────────────────────────

class _TxnStyle {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color fgColor;
  const _TxnStyle({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.fgColor,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color bg;
  final Color fg;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: fg),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: fg),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
          Text(sub,
              style: TextStyle(
                  fontSize: 9, color: fg.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _TransactionRow extends ConsumerWidget {
  final FinancialTransactionEntity txn;
  const _TransactionRow({required this.txn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _TxnStyle style = _txnStyle(txn.type);
    final isCredit = txn.type == 'collection' || txn.type == 'payment';
    final itemsVal = ref.watch(transactionItemsProvider(txn));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: style.bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 17, color: style.fgColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13, color: _kText),
                    ),
                    Text(
                      DateFormat('dd.MM.yyyy HH:mm').format(txn.date),
                      style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isCredit ? '+' : '-'}₺${txn.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: isCredit ? _kGreenDark : _kRed),
                  ),
                  if (txn.debtAmount > 0)
                    Text(
                      'Borç: ₺${txn.debtAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 10,
                          color: _kRed.withValues(alpha: 0.7)),
                    ),
                ],
              ),
            ],
          ),
          itemsVal.when(
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 8, left: 48),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 12, color: _kTextSecondary.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        const Text(
                          'Detaylar:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...items.map((item) {
                      final name = item['name'] as String;
                      final qty = item['quantity'];
                      final price = item['unit_price'] as double;
                      final qtyStr = _formatQuantity(qty);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '• $name',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _kText,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '$qtyStr adet x ₺${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _kTextSecondary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 8, left: 48),
              child: SizedBox(
                height: 12,
                width: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(_kGreen),
                ),
              ),
            ),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _formatQuantity(dynamic qty) {
    if (qty == null) return '0';
    if (qty is num) {
      if (qty % 1 == 0) {
        return qty.toInt().toString();
      }
      return qty.toStringAsFixed(2);
    }
    return qty.toString();
  }

  _TxnStyle _txnStyle(String type) {
    switch (type) {
      case 'sale':
        return const _TxnStyle(
            icon: Icons.shopping_cart_rounded,
            label: 'Vadeli Satış',
            bgColor: _kRedLight,
            fgColor: _kRed);
      case 'collection':
      case 'payment':
        return const _TxnStyle(
            icon: Icons.price_check_rounded,
            label: 'Tahsilat',
            bgColor: _kGreenLight,
            fgColor: _kGreenDark);
      case 'refund':
        return const _TxnStyle(
            icon: Icons.undo_rounded,
            label: 'İade',
            bgColor: _kAmberLight,
            fgColor: _kAmber);
      case 'cancellation':
        return _TxnStyle(
            icon: Icons.cancel_rounded,
            label: 'İptal',
            bgColor: Colors.grey[100]!,
            fgColor: _kTextSecondary);
      default:
        return _TxnStyle(
            icon: Icons.receipt_rounded,
            label: type,
            bgColor: Colors.grey[100]!,
            fgColor: _kTextSecondary);
    }
  }
}
