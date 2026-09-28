// lib/presentation/pages/end_of_day_page.dart
// Kasa Sayımı & Gün Sonu Kapatma Sayfası
// Created: 28 Sep 2026

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/repositories/end_of_day_repository.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/presentation/controllers/end_of_day_controller.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

class EndOfDayPage extends ConsumerStatefulWidget {
  const EndOfDayPage({super.key});

  @override
  ConsumerState<EndOfDayPage> createState() => _EndOfDayPageState();
}

class _EndOfDayPageState extends ConsumerState<EndOfDayPage> {
  DateTime _selectedDate = DateTime.now();
  final _cashCountController = TextEditingController();
  bool _isPrinting = false;

  @override
  void dispose() {
    _cashCountController.dispose();
    super.dispose();
  }

  // Yalnızca tarih kısmını karşılaştır (saat farkı görmezden gel)
  DateTime get _dateKey =>
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _printReport(EndOfDayReport report) async {
    setState(() => _isPrinting = true);
    try {
      final hasPrinter = await ref
          .read(printingRepositoryProvider)
          .hasUsableDevice(PrintDocumentKind.receipt);
      if (!mounted) return;

      if (!hasPrinter) {
        _snack('Yazıcı tanımlı değil. Ayarlar → Yazıcı bölümünü kontrol edin.',
            error: true);
        return;
      }

      // Settings yükle
      var settings = ref.read(settingsNotifierProvider).valueOrNull;
      if (settings == null) {
        try {
          final repo = await ref.read(settingsRepositoryProvider.future);
          settings = await repo.getSettings();
        } catch (_) {}
      }
      if (!mounted) return;
      if (settings == null) {
        _snack('Ayarlar yüklenemedi.', error: true);
        return;
      }

      // EndOfDayReport → mevcut ReportSummary DTO'suna dönüştür
      final debtLine = report.salesBreakdown
          .firstWhere((l) => l.label.contains('Vadeli'),
              orElse: () => const PaymentTypeLine(
                  label: 'Vadeli', count: 0, total: 0));

      final range = DateRange.today();
      final summary = ReportSummary(
        totalRevenue: report.totalRevenue,
        totalSales: report.totalSaleCount,
        totalDebt: debtLine.total,
        totalCollected: report.cashFlow.expectedCash + report.cashFlow.totalPosCard,
        avgBasket: report.totalSaleCount == 0
            ? 0
            : report.totalRevenue / report.totalSaleCount,
        newCustomers: 0,
        range: range,
      );

      // Kategori listesi yerine ödeme tipi kırılımını kategori olarak gönder
      final categories = report.salesBreakdown
          .map((l) => CategoryRevenue(
                categoryId: l.label.toLowerCase(),
                categoryName: l.label,
                totalAmount: l.total,
                saleCount: l.count,
                percentage: report.totalRevenue == 0
                    ? 0
                    : l.total / report.totalRevenue * 100,
              ))
          .toList();

      await ref
          .read(printingApplicationServiceProvider)
          .queueReport('end_of_day', summary, categories, settings);

      if (mounted) _snack('Yazdırma kuyruğuna eklendi.');
    } catch (e) {
      if (mounted) _snack('Yazdırma başlatılamadı: $e', error: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }


  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? POSColors.red : POSColors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(endOfDayReportProvider(_dateKey));
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: POSColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Gün Sonu Raporu',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          // Tarih seçici
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              DateFormat('dd MMM yyyy', 'tr_TR').format(_selectedDate),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: POSColors.green,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          // Yenile
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
            onPressed: () =>
                ref.invalidate(endOfDayReportProvider(_dateKey)),
          ),
          // Yazdır
          report.when(
            data: (data) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _isPrinting ? null : () => _printReport(data),
                icon: _isPrinting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.print_rounded, size: 18),
                label: const Text('Yazdır'),
                style: FilledButton.styleFrom(
                  backgroundColor: POSColors.darkSurface,
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: report.when(
        skipLoadingOnReload: true,
        data: (data) => _Body(
          report: data,
          compact: compact,
          cashCountController: _cashCountController,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: POSColors.red, size: 44),
              const SizedBox(height: 12),
              Text('Rapor yüklenemedi',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('$e',
                  style: const TextStyle(color: POSColors.textSecondary)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(endOfDayReportProvider(_dateKey)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Body
// ════════════════════════════════════════════════════════════

class _Body extends StatelessWidget {
  const _Body({
    required this.report,
    required this.compact,
    required this.cashCountController,
  });

  final EndOfDayReport report;
  final bool compact;
  final TextEditingController cashCountController;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'tr_TR', symbol: '', decimalDigits: 2);

    return RefreshIndicator(
      onRefresh: () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(compact ? 12 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Satış özeti ──────────────────────────────
                _SectionHeader(
                  icon: Icons.point_of_sale_rounded,
                  label: 'Satış Özeti',
                  eyebrow: DateFormat('dd MMMM yyyy', 'tr_TR')
                      .format(report.date),
                ),
                const SizedBox(height: 10),
                _SalesSummaryPanel(report: report, fmt: fmt),

                const SizedBox(height: 20),

                // ── Ödeme tipi kırılımı ──────────────────────
                const _SectionHeader(
                  icon: Icons.receipt_long_rounded,
                  label: 'Ödeme Tipi Kırılımı',
                  eyebrow: 'Satışlar',
                ),
                const SizedBox(height: 10),
                _PaymentBreakdownPanel(
                    report: report, fmt: fmt, compact: compact),

                const SizedBox(height: 20),

                // ── Kasa sayımı ──────────────────────────────
                const _SectionHeader(
                  icon: Icons.calculate_outlined,
                  label: 'Kasa Sayımı',
                  eyebrow: 'Nakit Kontrol',
                ),
                const SizedBox(height: 10),
                _CashCountPanel(
                    report: report,
                    fmt: fmt,
                    controller: cashCountController,
                    date: report.date),

                const SizedBox(height: 20),

                // ── Sipariş kırılımı ─────────────────────────
                const _SectionHeader(
                  icon: Icons.local_shipping_outlined,
                  label: 'Sipariş Özeti',
                  eyebrow: 'Siparişler',
                ),
                const SizedBox(height: 10),
                _OrderPanel(orders: report.orders, fmt: fmt, compact: compact),

                const SizedBox(height: 20),

                // ── Alacak durumu ────────────────────────────
                const _SectionHeader(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Alacak Durumu',
                  eyebrow: 'Vadeli & Piyasa',
                ),
                const SizedBox(height: 10),
                _ReceivablesPanel(
                  recv: report.receivables,
                  fmt: fmt,
                  collectionsList: report.cashFlow.collectionsList,
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.eyebrow,
  });

  final IconData icon;
  final String label;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 18, color: POSColors.greenDark),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null)
              Text(
                eyebrow!.toUpperCase(),
                style: const TextStyle(
                  color: POSColors.green,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Kart çerçevesi ───────────────────────────────────────────
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
        boxShadow: const [
          BoxShadow(
              color: POSColors.shadowColor, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }
}

// ── Satış Özeti Paneli ───────────────────────────────────────
class _SalesSummaryPanel extends StatelessWidget {
  const _SalesSummaryPanel({required this.report, required this.fmt});

  final EndOfDayReport report;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth >= 600 ? 4 : 2;
          const gap = 12.0;
          final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
          final items = [
            _MetricTile(
              label: 'Toplam Ciro',
              value: '${fmt.format(report.totalRevenue)} TL',
              icon: Icons.payments_outlined,
              color: POSColors.green,
              sub:
                  'Tezgah: ₺${fmt.format(report.directSalesRevenue)} | Sipariş: ₺${fmt.format(report.deliveredOrdersRevenue)}',
            ),
            _MetricTile(
              label: 'İndirim',
              value: '${fmt.format(report.totalDiscount)} TL',
              icon: Icons.discount_outlined,
              color: POSColors.amber,
            ),
            _MetricTile(
              label: 'İade',
              value: '${fmt.format(report.totalRefunds)} TL',
              icon: Icons.undo_rounded,
              color: POSColors.orange,
            ),
            _MetricTile(
              label: 'Net Ciro',
              value: '${fmt.format(report.netRevenue)} TL',
              icon: Icons.trending_up_rounded,
              color: POSColors.greenDark,
              highlighted: true,
            ),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items
                .map((m) => SizedBox(width: w, child: m))
                .toList(),
          );
        },
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted
            ? color.withValues(alpha: .08)
            : POSColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted ? color.withValues(alpha: .25) : POSColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: POSColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: highlighted ? color : POSColors.text,
                  ),
                ),
                if (sub != null)
                  Text(sub!,
                      style: const TextStyle(
                          color: POSColors.textDisabled, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ödeme Tipi Paneli ────────────────────────────────────────
class _PaymentBreakdownPanel extends StatefulWidget {
  const _PaymentBreakdownPanel({
    required this.report,
    required this.fmt,
    required this.compact,
  });

  final EndOfDayReport report;
  final NumberFormat fmt;
  final bool compact;

  @override
  State<_PaymentBreakdownPanel> createState() => _PaymentBreakdownPanelState();
}

class _PaymentBreakdownPanelState extends State<_PaymentBreakdownPanel> {
  bool _showSalesList = false;

  Color _getColor(String label) {
    if (label.contains('Nakit')) return POSColors.green;
    if (label.contains('Kart')) return POSColors.blue;
    if (label.contains('Karma')) return Colors.purple.shade600;
    return POSColors.orange;
  }

  IconData _getIcon(String label) {
    if (label.contains('Nakit')) return Icons.payments_outlined;
    if (label.contains('Kart')) return Icons.credit_card_rounded;
    if (label.contains('Karma')) return Icons.pie_chart_outline_rounded;
    return Icons.schedule_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final fmt = widget.fmt;
    final grandTotal = report.salesBreakdown.fold(0.0, (s, l) => s + l.total);

    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ...report.salesBreakdown.asMap().entries.map((entry) {
            final i = entry.key;
            final line = entry.value;
            final color = _getColor(line.label);
            final icon = _getIcon(line.label);
            final pct = grandTotal == 0 ? 0.0 : line.total / grandTotal;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, size: 18, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    line.label,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  '${line.count} adet',
                                  style: const TextStyle(
                                    color: POSColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  '${fmt.format(line.total)} TL',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: color,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            if (line.subNote != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                line.subNote!,
                                style: const TextStyle(
                                  color: POSColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 5,
                                color: color,
                                backgroundColor: POSColors.surfaceMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < report.salesBreakdown.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            );
          }),

          // Satış detaylarını incele butonu
          if (report.salesList.isNotEmpty) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => setState(() => _showSalesList = !_showSalesList),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadii.md)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _showSalesList ? Icons.expand_less : Icons.list_alt_rounded,
                      size: 18,
                      color: POSColors.greenDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _showSalesList
                            ? 'Satış Detaylarını Gizle'
                            : 'Günün Satışlarını Listele (${report.salesList.length} işlem)',
                        style: const TextStyle(
                          color: POSColors.greenDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      _showSalesList ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 20,
                      color: POSColors.greenDark,
                    ),
                  ],
                ),
              ),
            ),
            if (_showSalesList)
              Container(
                color: POSColors.surface,
                padding: const EdgeInsets.all(12),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: report.salesList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final s = report.salesList[idx];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: POSColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: POSColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                s.id.length > 14 ? s.id.substring(0, 14) : s.id,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: POSColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${fmt.format(s.totalAmount)} TL',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (s.cashPortion > 0)
                                    _PaymentBadge(
                                      label: 'Nakit: ₺${fmt.format(s.cashPortion)}',
                                      color: POSColors.green,
                                    ),
                                  if (s.cardPortion > 0)
                                    _PaymentBadge(
                                      label: 'Kart: ₺${fmt.format(s.cardPortion)}',
                                      color: POSColors.blue,
                                    ),
                                  if (s.debtPortion > 0.01)
                                    _PaymentBadge(
                                      label: 'Vadeli: ₺${fmt.format(s.debtPortion)}',
                                      color: POSColors.orange,
                                    ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                DateFormat('HH:mm').format(s.createdAt),
                                style: const TextStyle(fontSize: 11, color: POSColors.textDisabled),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Kasa Sayımı Paneli ───────────────────────────────────────
class _CashCountPanel extends ConsumerStatefulWidget {
  const _CashCountPanel({
    required this.report,
    required this.fmt,
    required this.controller,
    required this.date,
  });

  final EndOfDayReport report;
  final NumberFormat fmt;
  final TextEditingController controller;
  final DateTime date;

  @override
  ConsumerState<_CashCountPanel> createState() => _CashCountPanelState();
}

class _CashCountPanelState extends ConsumerState<_CashCountPanel> {
  double _counted = 0;
  late double _openingBalance;
  bool _showExpenses = false;
  bool _isSavingCount = false;

  @override
  void initState() {
    super.initState();
    _openingBalance = widget.report.cashFlow.openingBalance;
    if (widget.report.cashFlow.savedCountedCash != null &&
        widget.controller.text.isEmpty) {
      _counted = widget.report.cashFlow.savedCountedCash!;
      widget.controller.text = widget.fmt.format(_counted);
    } else if (widget.controller.text.isNotEmpty) {
      _counted =
          double.tryParse(widget.controller.text.replaceAll(',', '.')) ?? 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant _CashCountPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report != widget.report) {
      _openingBalance = widget.report.cashFlow.openingBalance;
      if (widget.report.cashFlow.savedCountedCash != null &&
          widget.controller.text.isEmpty) {
        _counted = widget.report.cashFlow.savedCountedCash!;
        widget.controller.text = widget.fmt.format(_counted);
      }
    }
  }

  double get _expected =>
      (_openingBalance +
              widget.report.cashFlow.totalCashInflow -
              widget.report.cashFlow.totalCashOutflow)
          .clamp(0.0, double.infinity);

  double get _diff => _counted - _expected;
  bool get _hasCounted => _counted > 0 || widget.controller.text.isNotEmpty;

  void _editOpeningBalance() async {
    final textCtrl = TextEditingController(
      text: _openingBalance > 0 ? widget.fmt.format(_openingBalance) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: POSColors.green),
            SizedBox(width: 8),
            Text('Sabah Kasa Devri (Avans)', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Güne başlarken kasada bırakılan bozuk para veya devir avansı tutarını girin:',
              style: TextStyle(fontSize: 13, color: POSColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
              ],
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Açılış Avansı (TL)',
                suffixText: 'TL',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              final val =
                  double.tryParse(textCtrl.text.replaceAll(',', '.')) ?? 0.0;
              Navigator.pop(ctx, val);
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() => _openingBalance = result);
    }
  }

  void _openDenominationSheet() async {
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DenominationSheet(fmt: widget.fmt),
    );

    if (result != null && mounted) {
      setState(() {
        _counted = result;
        widget.controller.text = widget.fmt.format(result);
      });
    }
  }

  void _openAddExpenseDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => _AddExpenseDialog(
        date: widget.date,
        onAdded: () {},
      ),
    );
  }

  void _saveCashCount() async {
    setState(() => _isSavingCount = true);
    try {
      await ref.read(endOfDayActionsProvider).saveCount(
            date: widget.date,
            openingBalance: _openingBalance,
            countedCash: _counted,
            expectedCash: _expected,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Gün sonu kasa sayımı başarıyla kaydedildi.'),
              ],
            ),
            backgroundColor: POSColors.greenDark,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sayım kaydedilirken hata oluştu: $e'),
            backgroundColor: POSColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingCount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final cashFlow = widget.report.cashFlow;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 0. Sabah Kasa Devri (Açılış Avansı)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 16, color: POSColors.green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sabah Kasa Devri (Açılış Avansı)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: POSColors.text,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _editOpeningBalance,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '${fmt.format(_openingBalance)} TL',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: POSColors.green,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_outlined,
                            size: 14, color: POSColors.green),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 12),

          // 1. Kasa akışı tablosu
          _CashRow(
            label: 'Nakit Satışlar (Tezgah)',
            value: cashFlow.saleCash,
            fmt: fmt,
            icon: Icons.add,
            color: POSColors.green,
          ),
          if (cashFlow.orderDepositCash > 0)
            _CashRow(
              label: 'Sipariş Kaporaları (Bugün Alınan Nakit)',
              value: cashFlow.orderDepositCash,
              fmt: fmt,
              icon: Icons.add,
              color: POSColors.green,
            ),
          if (cashFlow.orderDeliveryCash > 0)
            _CashRow(
              label: 'Sipariş Teslimat Tahsilatları (Bugün)',
              value: cashFlow.orderDeliveryCash,
              fmt: fmt,
              icon: Icons.add,
              color: POSColors.green,
            ),
          _CashRow(
            label: 'Cari Borç Nakit Tahsilatı',
            value: cashFlow.collectionCash,
            fmt: fmt,
            icon: Icons.add,
            color: POSColors.green,
          ),
          _CashRow(
            label: 'Nakit İadeler (Kasadan Çıkan)',
            value: cashFlow.refundCash,
            fmt: fmt,
            icon: Icons.remove,
            color: POSColors.red,
            isDeduction: true,
          ),

          // Kasadan Yapılan Harcamalar / Masraflar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.remove, size: 16, color: POSColors.red),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Kasadan Harcamalar / Masraflar',
                    style: TextStyle(
                      fontSize: 13,
                      color: POSColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '-${fmt.format(cashFlow.expenseCash)} TL',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: POSColors.red,
                  ),
                ),
              ],
            ),
          ),

          // Masraf Ekle ve Listele Aksiyonları
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: _openAddExpenseDialog,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: POSColors.redLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: POSColors.red.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 14, color: POSColors.red),
                        SizedBox(width: 6),
                        Text(
                          'Kasa Çıkışı / Masraf Ekle',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: POSColors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (cashFlow.expensesList.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () =>
                        setState(() => _showExpenses = !_showExpenses),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            _showExpenses
                                ? 'Harcamaları Gizle'
                                : 'Harcamaları İncele (${cashFlow.expensesList.length})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: POSColors.green,
                            ),
                          ),
                          Icon(
                            _showExpenses
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 16,
                            color: POSColors.green,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Masraf Detay Listesi (Accordion)
          if (_showExpenses && cashFlow.expensesList.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: POSColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: POSColors.border),
              ),
              child: Column(
                children: cashFlow.expensesList.map((exp) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: POSColors.surface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            exp.category,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: POSColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            exp.description.isEmpty
                                ? 'Masraf / Kasa Çıkışı'
                                : exp.description,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '-${fmt.format(exp.amount)} TL',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: POSColors.red,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: POSColors.textDisabled),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () async {
                            await ref
                                .read(endOfDayActionsProvider)
                                .deleteExpense(
                                  date: widget.date,
                                  expenseId: exp.id,
                                );
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const Divider(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'KASADA BULUNMASI GEREKEN NAKİT',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
              Text(
                '${fmt.format(_expected)} TL',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: POSColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Banka POS Tahsilatı (Kart - Bilgi Amaçlı)',
                  style: TextStyle(fontSize: 12, color: POSColors.textSecondary),
                ),
              ),
              Text(
                '${fmt.format(cashFlow.totalPosCard)} TL',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: POSColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Fiziksel sayım girişi başlığı ve banknot sayıcı butonu
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fiili Kasa Sayımı (Eldeki Nakit)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: POSColors.textSecondary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openDenominationSheet,
                icon: const Icon(Icons.calculate_outlined, size: 16),
                label: const Text('Banknot Sayıcı',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: POSColors.green,
                  side: const BorderSide(color: POSColors.green),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
            ],
            decoration: InputDecoration(
              hintText: '0,00',
              suffixText: 'TL',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: POSColors.green, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (v) {
              final parsed = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
              setState(() => _counted = parsed);
            },
          ),
          if (_hasCounted) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _diff == 0
                    ? POSColors.greenLight
                    : _diff > 0
                        ? POSColors.blueLight
                        : POSColors.redLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _diff == 0
                        ? Icons.check_circle_rounded
                        : _diff > 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                    color: _diff == 0
                        ? POSColors.greenDark
                        : _diff > 0
                            ? POSColors.blue
                            : POSColors.red,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _diff == 0
                          ? 'Kasa tam — fark yok'
                          : _diff > 0
                              ? 'Kasa fazlası var'
                              : 'Kasa açığı var',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _diff == 0
                            ? POSColors.greenDark
                            : _diff > 0
                                ? POSColors.blue
                                : POSColors.red,
                      ),
                    ),
                  ),
                  Text(
                    '${_diff >= 0 ? '+' : ''}${fmt.format(_diff)} TL',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: _diff == 0
                          ? POSColors.greenDark
                          : _diff > 0
                              ? POSColors.blue
                              : POSColors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSavingCount ? null : _saveCashCount,
                icon: _isSavingCount
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lock_clock_outlined, size: 18),
                label: Text(
                  widget.report.cashFlow.savedCountedCash != null
                      ? 'Sayımı Güncelle & Kilitle'
                      : 'Gün Sonu Kasa Sayımını Kilitle & Kaydet',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: POSColors.greenDark,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Banknot ve Madeni Para Sayma Sihirbazı (BottomSheet) ───────
class _DenominationSheet extends StatefulWidget {
  const _DenominationSheet({required this.fmt});
  final NumberFormat fmt;

  @override
  State<_DenominationSheet> createState() => _DenominationSheetState();
}

class _DenominationSheetState extends State<_DenominationSheet> {
  final Map<int, int> _counts = {
    200: 0,
    100: 0,
    50: 0,
    20: 0,
    10: 0,
    5: 0,
    1: 0,
  };
  double _extraCoins = 0.0;
  final TextEditingController _extraCoinsCtrl = TextEditingController();

  double get _total {
    double sum = 0.0;
    _counts.forEach((denom, count) {
      sum += denom * count;
    });
    sum += _extraCoins;
    return sum;
  }

  void _increment(int denom) {
    setState(() => _counts[denom] = (_counts[denom] ?? 0) + 1);
  }

  void _decrement(int denom) {
    setState(() {
      final current = _counts[denom] ?? 0;
      if (current > 0) _counts[denom] = current - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final denoms = [200, 100, 50, 20, 10, 5, 1];

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: POSColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.calculate_outlined, color: POSColors.green),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Banknot & Para Sayma Sihirbazı',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Denominations List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...denoms.map((d) {
                  final isCoin = d == 1;
                  final count = _counts[d] ?? 0;
                  final sub = d * count;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: POSColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: POSColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 65,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isCoin
                                ? Colors.amber.withValues(alpha: 0.15)
                                : POSColors.blueLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$d TL',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: isCoin
                                  ? Colors.amber.shade900
                                  : POSColors.blue,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: () => _decrement(d),
                          color: POSColors.textSecondary,
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '$count',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          onPressed: () => _increment(d),
                          color: POSColors.green,
                        ),
                        const Spacer(),
                        Text(
                          '${fmt.format(sub)} TL',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: POSColors.text,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // Bozuk paralar (50 kr, 25 kr vs.)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: POSColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: POSColors.border),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Diğer Kuruş / Bozukluklar (TL)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _extraCoinsCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[\d,.]')),
                          ],
                          textAlign: TextAlign.end,
                          decoration: const InputDecoration(
                            hintText: '0,00',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final p = double.tryParse(v.replaceAll(',', '.')) ??
                                0.0;
                            setState(() => _extraCoins = p);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Footer & Total
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: POSColors.card,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Toplam Sayılan Tutar:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: POSColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${fmt.format(_total)} TL',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: POSColors.greenDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _total),
                      icon: const Icon(Icons.check),
                      label: const Text(
                        'Sayımı Kasa Ekranına Aktar',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: POSColors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Masraf Ekle Dialogu ──────────────────────────────────────
class _AddExpenseDialog extends ConsumerStatefulWidget {
  const _AddExpenseDialog({required this.date, required this.onAdded});
  final DateTime date;
  final VoidCallback onAdded;

  @override
  ConsumerState<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends ConsumerState<_AddExpenseDialog> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _selectedCategory = 'Kargo';
  bool _loading = false;

  final _categories = [
    'Kargo',
    'Yemek & Çay',
    'Temizlik & Sarf',
    'Personel Avansı',
    'Kırtasiye',
    'Genel Gider',
  ];

  void _submit() async {
    final amt = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen geçerli bir tutar girin')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(endOfDayActionsProvider).addExpense(
            date: widget.date,
            amount: amt,
            category: _selectedCategory,
            description: _descCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        widget.onAdded();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.receipt_long_outlined, color: POSColors.red),
          SizedBox(width: 8),
          Text('Kasadan Masraf / Gider Çıkışı', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kasadan elden ödenen dükkan harcamasını kaydedin (kasadan düşecektir):',
              style: TextStyle(fontSize: 12, color: POSColors.textSecondary),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Gider Kategorisi',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _categories.map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedCategory = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Tutar (TL)',
                suffixText: 'TL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Açıklama / Fiş No (Örn: Aras Kargo)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: POSColors.red),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Kasadan Düş'),
        ),
      ],
    );
  }
}

class _CashRow extends StatelessWidget {
  const _CashRow({
    required this.label,
    required this.value,
    required this.fmt,
    required this.icon,
    required this.color,
    this.isDeduction = false,
  });

  final String label;
  final double value;
  final NumberFormat fmt;
  final IconData icon;
  final Color color;
  final bool isDeduction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: POSColors.textSecondary),
            ),
          ),
          Text(
            '${isDeduction ? '-' : ''}${fmt.format(value)} TL',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sipariş Paneli ───────────────────────────────────────────
class _OrderPanel extends StatefulWidget {
  const _OrderPanel({
    required this.orders,
    required this.fmt,
    required this.compact,
  });

  final OrderBreakdown orders;
  final NumberFormat fmt;
  final bool compact;

  @override
  State<_OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends State<_OrderPanel> {
  bool _showDeliveredOrders = false;

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    final fmt = widget.fmt;

    return _Card(
      child: Column(
        children: [
          // Teslim edilen özet satırı
          _OrderHeaderRow(
            label: 'Teslim Edilen Siparişler',
            count: orders.deliveredCount,
            total: orders.deliveredTotal,
            fmt: fmt,
            color: POSColors.green,
            icon: Icons.check_circle_outline_rounded,
          ),
          const SizedBox(height: 12),

          // Ödeme ve kapora alt kırılımı
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: POSColors.surface,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              children: [
                if (orders.deliveredPrepaidTotal > 0) ...[
                  _SubOrderRow(
                    label: '└ Önceden Alınmış Kapora (Avans)',
                    count: 0,
                    total: orders.deliveredPrepaidTotal,
                    fmt: fmt,
                    color: POSColors.textSecondary,
                    hideCount: true,
                  ),
                  const SizedBox(height: 6),
                ],
                _SubOrderRow(
                  label: '└ Bugün Teslimatta Alınan Nakit',
                  count: 0,
                  total: orders.deliveredCashToday,
                  fmt: fmt,
                  color: POSColors.green,
                  hideCount: true,
                ),
                const SizedBox(height: 6),
                _SubOrderRow(
                  label: '└ Bugün Teslimatta Alınan Kredi Kartı',
                  count: 0,
                  total: orders.deliveredCardToday,
                  fmt: fmt,
                  color: POSColors.blue,
                  hideCount: true,
                ),
                const SizedBox(height: 6),
                _SubOrderRow(
                  label: '└ Kalan Vadeli (Veresiye) Borç',
                  count: 0,
                  total: orders.deliveredDebtTotal,
                  fmt: fmt,
                  color: POSColors.orange,
                  hideCount: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Bekleyen ve iptal çipler
          Row(
            children: [
              Expanded(
                child: _StatusChip(
                  label: 'Bekleyen (${fmt.format(orders.pendingTotal)} TL)',
                  count: orders.pendingCount,
                  color: POSColors.amber,
                  icon: Icons.access_time_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusChip(
                  label: 'İptal Edilen',
                  count: orders.cancelledCount,
                  color: POSColors.red,
                  icon: Icons.cancel_outlined,
                ),
              ),
            ],
          ),

          // Teslim edilen siparişlerin tek tek listesi
          if (orders.deliveredOrders.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            InkWell(
              onTap: () => setState(() => _showDeliveredOrders = !_showDeliveredOrders),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showDeliveredOrders ? Icons.expand_less : Icons.local_shipping_outlined,
                      size: 18,
                      color: POSColors.greenDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _showDeliveredOrders
                            ? 'Sipariş Listesini Gizle'
                            : 'Teslim Edilen Siparişleri İncele (${orders.deliveredOrders.length} sipariş)',
                        style: const TextStyle(
                          color: POSColors.greenDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      _showDeliveredOrders ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 20,
                      color: POSColors.greenDark,
                    ),
                  ],
                ),
              ),
            ),
            if (_showDeliveredOrders) ...[
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orders.deliveredOrders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final o = orders.deliveredOrders[idx];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: POSColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: POSColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              o.orderNumber.isNotEmpty ? o.orderNumber : '#${o.id.substring(0, 8)}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                o.customerName,
                                style: const TextStyle(color: POSColors.textSecondary, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${fmt.format(o.totalAmount)} TL',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Wrap(
                              spacing: 6,
                              children: [
                                if (o.previouslyPaid > 0)
                                  _PaymentBadge(
                                    label: 'Önceki Kapora: ₺${fmt.format(o.previouslyPaid)}',
                                    color: Colors.grey.shade700,
                                  ),
                                if (o.cashPaidToday > 0)
                                  _PaymentBadge(
                                    label: 'Bugün Nakit: ₺${fmt.format(o.cashPaidToday)}',
                                    color: POSColors.green,
                                  ),
                                if (o.cardPaidToday > 0)
                                  _PaymentBadge(
                                    label: 'Bugün Kart: ₺${fmt.format(o.cardPaidToday)}',
                                    color: POSColors.blue,
                                  ),
                                if (o.debtRemaining > 0.01)
                                  _PaymentBadge(
                                    label: 'Kalan Vadeli: ₺${fmt.format(o.debtRemaining)}',
                                    color: POSColors.orange,
                                  ),
                              ],
                            ),
                            const Spacer(),
                            if (o.deliveredAt != null)
                              Text(
                                DateFormat('HH:mm').format(o.deliveredAt!),
                                style: const TextStyle(fontSize: 11, color: POSColors.textDisabled),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _OrderHeaderRow extends StatelessWidget {
  const _OrderHeaderRow({
    required this.label,
    required this.count,
    required this.total,
    required this.fmt,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final double total;
  final NumberFormat fmt;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        Text(
          '$count adet',
          style: const TextStyle(color: POSColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 16),
        Text(
          '${fmt.format(total)} TL',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color),
        ),
      ],
    );
  }
}

class _SubOrderRow extends StatelessWidget {
  const _SubOrderRow({
    required this.label,
    required this.count,
    required this.total,
    required this.fmt,
    required this.color,
    this.hideCount = false,
  });

  final String label;
  final int count;
  final double total;
  final NumberFormat fmt;
  final Color color;
  final bool hideCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: POSColors.textSecondary, fontSize: 12),
        ),
        const Spacer(),
        if (!hideCount && count > 0) ...[
          Text(
            '$count adet',
            style: const TextStyle(color: POSColors.textDisabled, fontSize: 12),
          ),
          const SizedBox(width: 16),
        ],
        Text(
          '${fmt.format(total)} TL',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(color: color, fontSize: 12)),
          ),
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ── Alacak Paneli ─────────────────────────────────────────────
class _ReceivablesPanel extends StatefulWidget {
  const _ReceivablesPanel({
    required this.recv,
    required this.fmt,
    this.collectionsList = const [],
  });

  final ReceivablesSummary recv;
  final NumberFormat fmt;
  final List<CollectionDetailLine> collectionsList;

  @override
  State<_ReceivablesPanel> createState() => _ReceivablesPanelState();
}

class _ReceivablesPanelState extends State<_ReceivablesPanel> {
  bool _showCollections = false;

  @override
  Widget build(BuildContext context) {
    final recv = widget.recv;
    final fmt = widget.fmt;
    final collections = widget.collectionsList;

    return _Card(
      child: Column(
        children: [
          _RecvRow(
            label: 'Bugün oluşan yeni vadeli alacak',
            value: recv.newDebtToday,
            fmt: fmt,
            color: POSColors.orange,
            icon: Icons.arrow_upward_rounded,
          ),
          const SizedBox(height: 8),
          _RecvRow(
            label: 'Bugün tahsil edilen cari borç',
            value: recv.collectedToday,
            fmt: fmt,
            color: POSColors.green,
            icon: Icons.arrow_downward_rounded,
          ),
          const Divider(height: 20),
          _RecvRow(
            label: 'Toplam Piyasa Alacağı (Tüm Müşteriler)',
            value: recv.totalReceivables,
            fmt: fmt,
            color: recv.totalReceivables > 0 ? POSColors.orange : POSColors.green,
            icon: Icons.account_balance_wallet_outlined,
            large: true,
          ),

          // Cari tahsilat makbuzları listesi
          if (collections.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            InkWell(
              onTap: () => setState(() => _showCollections = !_showCollections),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showCollections ? Icons.expand_less : Icons.receipt_long_rounded,
                      size: 18,
                      color: POSColors.greenDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _showCollections
                            ? 'Tahsilat Makbuzlarını Gizle'
                            : 'Bugünkü Cari Tahsilat Makbuzları (${collections.length} işlem)',
                        style: const TextStyle(
                          color: POSColors.greenDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      _showCollections ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 20,
                      color: POSColors.greenDark,
                    ),
                  ],
                ),
              ),
            ),
            if (_showCollections) ...[
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: collections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final c = collections[idx];
                  final isCard = c.method == 'card' || c.method.contains('pos');
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: POSColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: POSColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.customerName,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              if (c.description != null && c.description!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  c.description!,
                                  style: const TextStyle(fontSize: 11, color: POSColors.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        ),
                        _PaymentBadge(
                          label: isCard ? 'Kart' : 'Nakit',
                          color: isCard ? POSColors.blue : POSColors.green,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${fmt.format(c.amount)} TL',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('HH:mm').format(c.createdAt),
                          style: const TextStyle(fontSize: 11, color: POSColors.textDisabled),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RecvRow extends StatelessWidget {
  const _RecvRow({
    required this.label,
    required this.value,
    required this.fmt,
    required this.color,
    required this.icon,
    this.large = false,
  });

  final String label;
  final double value;
  final NumberFormat fmt;
  final Color color;
  final IconData icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: large ? FontWeight.w700 : FontWeight.w500,
              color: large ? POSColors.text : POSColors.textSecondary,
            ),
          ),
        ),
        Text(
          '${fmt.format(value)} TL',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: large ? 17 : 14,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Yardımcı Rozet (Badge) ──────────────────────────────────
class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
