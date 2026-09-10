part of '../home_page.dart';

class _CockpitDateBanner extends StatelessWidget {
  const _CockpitDateBanner({required this.totalTransactions});

  final int totalTransactions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy', 'tr_TR').format(now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: POSColors.green,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: POSColors.text,
                    ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: POSColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '$totalTransactions İşlem Tamamlandı',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: POSColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 2. 4'lü Kurumsal Serenut KPI Metrik Kartları ──────────────────────────────
class _HeroExecutiveMetrics extends StatelessWidget {
  const _HeroExecutiveMetrics({
    required this.summary,
    required this.orderSummary,
    required this.isWide,
  });

  final DashboardSummary summary;
  final DashboardOrderSummary orderSummary;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final totalTurnover = summary.todayRevenue + orderSummary.todayOrdersRevenue;
    final totalTxCount = summary.totalSalesToday + orderSummary.todayOrdersCount;

    final cards = [
      _SerenutMetricCard(
        title: 'BUGÜNKÜ CİRO',
        amount: currency.format(totalTurnover),
        subtitle: '$totalTxCount İşlem (Kasa + Sipariş)',
        icon: Icons.account_balance_wallet_rounded,
        accentColor: POSColors.green,
      ),
      _SerenutMetricCard(
        title: 'KASA SATIŞI',
        amount: currency.format(summary.todayRevenue),
        subtitle: '${summary.totalSalesToday} Fiş / Kasa Satışı',
        icon: Icons.point_of_sale_rounded,
        accentColor: POSColors.greenDark,
      ),
      _SerenutMetricCard(
        title: 'SİPARİŞLER',
        amount: currency.format(orderSummary.todayOrdersRevenue),
        subtitle: '${orderSummary.todayOrdersCount} Kargo & Paket',
        icon: Icons.local_shipping_rounded,
        accentColor: POSColors.amberDark,
      ),
      _SerenutMetricCard(
        title: 'TAHSİLAT & VADELİ',
        amount: currency.format(summary.todayCollected),
        subtitle:
            'Toplam Alacak: ₺${summary.totalReceivables.toStringAsFixed(2)}',
        icon: Icons.payments_rounded,
        accentColor: const Color(0xFF0284C7),
      ),
    ];

    if (isWide) {
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: c,
                  ),
                ))
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 520) {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.1,
            children: cards,
          );
        }
        return Column(
          children: cards
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: c,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _SerenutMetricCard extends StatelessWidget {
  const _SerenutMetricCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  final String title;
  final String amount;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 30,
                height: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: POSColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: POSColors.text,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: POSColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

// ── 3. Sipariş Operasyon Takip Kartı (Pipeline) ──────────────────────────────
