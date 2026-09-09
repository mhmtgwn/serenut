part of '../reports_page.dart';

class _ReceivablesTab extends ConsumerWidget {
  const _ReceivablesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(agingSummaryProvider);
    final rows = ref.watch(debtAgingProvider);
    return ReportScrollView(
      onRefresh: () async {
        ref.invalidate(agingSummaryProvider);
        ref.invalidate(debtAgingProvider);
      },
      children: [
        const ReportSectionHeader(
          eyebrow: 'Risk görünümü',
          title: 'Alacak yaşlandırma',
          subtitle: 'Açık bakiyelerin gecikme süresine göre dağılımı',
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 14),
        summary.when(
          data: (data) => _AgingOverview(summary: data),
          loading: () => const ReportLoadingCard(height: 170),
          error: (error, _) => ReportErrorCard(
            message: 'Alacak özeti yüklenemedi.',
            onRetry: () => ref.invalidate(agingSummaryProvider),
          ),
        ),
        const SizedBox(height: 24),
        const ReportSectionHeader(
          eyebrow: 'Müşteriler',
          title: 'Açık hesaplar',
          subtitle: 'Gecikmiş bakiyesi bulunan müşteriler önce gösterilir',
          icon: Icons.people_outline_rounded,
        ),
        const SizedBox(height: 14),
        rows.when(
          data: (items) => items.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'Açık alacak yok',
                  message: 'Tüm müşteri bakiyeleri kapalı görünüyor.',
                )
              : _ReceivablesList(rows: items),
          loading: () => const ReportLoadingCard(height: 320),
          error: (error, _) => ReportErrorCard(
            message: 'Müşteri bakiyeleri yüklenemedi.',
            onRetry: () => ref.invalidate(debtAgingProvider),
          ),
        ),
      ],
    );
  }
}

class _AgingOverview extends StatelessWidget {
  const _AgingOverview({required this.summary});

  final AgingSummary summary;

  @override
  Widget build(BuildContext context) {
    final buckets = [
      ('0–30 gün', summary.total0to30, POSColors.green),
      ('31–60 gün', summary.total31to60, POSColors.amberDark),
      ('61–90 gün', summary.total61to90, POSColors.orange),
      ('90+ gün', summary.totalOver90, POSColors.red),
    ];
    return ReportPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 600 ? 2 : 4;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Toplam açık alacak',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 3),
                        Text(
                          '${formatReportCurrency(summary.grandTotal)} TL',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  ReportPill(
                    label: '${summary.affectedCustomers} müşteri',
                    icon: Icons.people_outline,
                    color: summary.totalOver90 > 0
                        ? POSColors.red
                        : POSColors.green,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: buckets
                    .map((bucket) => SizedBox(
                          width: width,
                          child: _AgingTile(
                            label: bucket.$1,
                            amount: bucket.$2,
                            color: bucket.$3,
                          ),
                        ))
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AgingTile extends StatelessWidget {
  const _AgingTile({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            '${formatReportCurrency(amount)} TL',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ReceivablesList extends StatelessWidget {
  const _ReceivablesList({required this.rows});

  final List<DebtAgingRow> rows;

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a, b) {
        final overdue = b.over90.compareTo(a.over90);
        return overdue != 0 ? overdue : b.total.compareTo(a.total);
      });
    return ReportPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: sorted.asMap().entries.map((entry) {
          final row = entry.value;
          final riskColor = row.over90 > 0
              ? POSColors.red
              : row.hasOverdue
                  ? POSColors.orange
                  : POSColors.green;
          return Column(
            children: [
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: riskColor.withValues(alpha: .10),
                  child: Icon(Icons.person_outline, size: 18, color: riskColor),
                ),
                title: Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  row.hasOverdue ? 'Gecikmiş bakiye var' : 'Vadesi geçmemiş',
                  style: TextStyle(color: riskColor, fontSize: 11),
                ),
                trailing: Text(
                  '${formatReportCurrency(row.total)} TL',
                  style:
                      TextStyle(color: riskColor, fontWeight: FontWeight.w800),
                ),
                children: [
                  _DebtBreakdown(row: row),
                ],
              ),
              if (entry.key != sorted.length - 1)
                const Divider(height: 1, indent: 68),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _DebtBreakdown extends StatelessWidget {
  const _DebtBreakdown({required this.row});

  final DebtAgingRow row;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('0–30 gün', row.current, POSColors.green),
      ('31–60 gün', row.days31to60, POSColors.amberDark),
      ('61–90 gün', row.days61to90, POSColors.orange),
      ('90+ gün', row.over90, POSColors.red),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: values
            .map((value) => SizedBox(
                  width: (constraints.maxWidth - 8) / 2,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: POSColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(value.$1,
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          '${formatReportCurrency(value.$2)} TL',
                          style: TextStyle(
                            color: value.$3,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

