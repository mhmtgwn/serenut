part of '../home_page.dart';

class _CriticalStockBanner extends StatelessWidget {
  const _CriticalStockBanner({
    required this.lowStockCount,
    required this.onTap,
  });

  final int lowStockCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: POSColors.redLight,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: POSColors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: POSColors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$lowStockCount ürün kritik stok seviyesinde!',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF991B1B),
                          ),
                    ),
                    Text(
                      'Tükenmek üzere olan ürünleri inceleyin.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFB91C1C),
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: Color(0xFF991B1B)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 5. Yardımcı Operasyonel Araçlar Kartı (Quick Utilities) ───────────────────
class _QuickUtilitiesCard extends StatelessWidget {
  const _QuickUtilitiesCard();

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
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: POSColors.green,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Operasyonel Yardımcı Araçlar',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: POSColors.text,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _UtilityTile(
                  title: 'Hızlı Tahsilat',
                  subtitle: 'Borç Kapatma',
                  icon: Icons.payments_outlined,
                  color: POSColors.greenDark,
                  onTap: () => FastCollectionBottomSheet.show(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _UtilityTile(
                  title: 'Aygıtlar & Yazıcı',
                  subtitle: 'Donanım & Bağlantı',
                  icon: Icons.print_outlined,
                  color: const Color(0xFFD97706),
                  onTap: () => context.push(AppRoutes.hardware),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _UtilityTile(
                  title: 'Kasa & Raporlar',
                  subtitle: 'Gün Sonu Dökümü',
                  icon: Icons.assessment_outlined,
                  color: const Color(0xFF2563EB),
                  onTap: () => requirePermissionAccess(
                    context,
                    permission: Permission.reportsView,
                    title: 'Raporlar Yetkisi',
                    onGranted: (_, __) => context.push(AppRoutes.reports),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _UtilityTile(
                  title: 'Müşteri & Cariler',
                  subtitle: 'Borç & Bakiye Takibi',
                  icon: Icons.people_outline_rounded,
                  color: const Color(0xFF7C3AED),
                  onTap: () => context.go(AppRoutes.customers),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UtilityTile extends StatelessWidget {
  const _UtilityTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: POSColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: POSColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: POSColors.text,
                          ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: POSColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 6. Canlı İşlem Akışı Paneli ───────────────────────────────────────────────
