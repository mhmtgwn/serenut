part of '../home_page.dart';

class _OrderPipelineCard extends StatelessWidget {
  const _OrderPipelineCard({required this.orderSummary});

  final DashboardOrderSummary orderSummary;

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
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: POSColors.amber,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sipariş Operasyon Aşamaları',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: POSColors.text,
                        ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.orders),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  children: [
                    Text(
                      'Tümünü Gör',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: POSColors.greenDark,
                          ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: POSColors.greenDark),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PipelineBadge(
                  label: 'Yeni',
                  count: orderSummary.createdCount,
                  color: const Color(0xFFF59E0B),
                  onTap: () => context.go('/orders?status=created'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PipelineBadge(
                  label: 'Hazırlanıyor',
                  count: orderSummary.preparingCount,
                  color: const Color(0xFF3B82F6),
                  onTap: () => context.go('/orders?status=preparing'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PipelineBadge(
                  label: 'Yolda',
                  count: orderSummary.shippedCount,
                  color: const Color(0xFF8B5CF6),
                  onTap: () => context.go('/orders?status=shipped'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PipelineBadge(
                  label: 'Teslim',
                  count: orderSummary.deliveredCount,
                  color: POSColors.green,
                  onTap: () => context.go('/orders?status=delivered'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineBadge extends StatelessWidget {
  const _PipelineBadge({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: POSColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 4. Kritik Stok Uyarısı Banner ─────────────────────────────────────────────
