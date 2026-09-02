import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';

/// Karma (split) ödeme alanlarında Toplam, Ödenen ve Kalan tutarlarını
/// gerçek zamanlı gösteren özet bandı.
///
/// Hem Satış (POS) hem de Sipariş (Order Creation & Details) modüllerinde
/// ortaklaşa kullanılır.
class KarmaPaymentSummaryBar extends StatelessWidget {
  final double total;
  final double paid;
  final double remaining;
  final double debt;
  final double change;
  final bool isValid;

  const KarmaPaymentSummaryBar({
    super.key,
    required this.total,
    required this.paid,
    required this.remaining,
    this.debt = 0.0,
    this.change = 0.0,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: POSColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValid
              ? POSColors.green.withValues(alpha: 0.35)
              : POSColors.border,
          width: isValid ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 1. TOPLAM
              Expanded(
                child: _buildItem(
                  title: 'TOPLAM',
                  value: '₺${total.toStringAsFixed(2)}',
                  valueColor: POSColors.text,
                  backgroundColor: Colors.white,
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              const SizedBox(width: 6),
              // 2. ÖDENEN
              Expanded(
                child: _buildItem(
                  title: 'ÖDENEN',
                  value: '₺${paid.toStringAsFixed(2)}',
                  valueColor: POSColors.greenDark,
                  backgroundColor: POSColors.greenLight.withValues(alpha: 0.45),
                  icon: Icons.payments_rounded,
                  subtitle: debt > 0.009
                      ? '+₺${debt.toStringAsFixed(2)} Vadeli'
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              // 3. KALAN
              Expanded(
                child: _buildItem(
                  title: 'KALAN',
                  value: isValid
                      ? '₺0.00'
                      : '₺${remaining.toStringAsFixed(2)}',
                  valueColor: isValid
                      ? POSColors.greenDark
                      : (remaining > 0.009 ? POSColors.red : POSColors.text),
                  backgroundColor: isValid
                      ? POSColors.greenLight
                      : (remaining > 0.009
                          ? POSColors.redLight.withValues(alpha: 0.4)
                          : Colors.white),
                  icon: isValid
                      ? Icons.check_circle_rounded
                      : Icons.pending_rounded,
                  statusBadge: isValid
                      ? 'Tamam'
                      : (remaining > 0.009 ? 'Eksik' : null),
                ),
              ),
            ],
          ),
          if (change > 0.009) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: POSColors.greenLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: POSColors.greenDark.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.change_circle_rounded,
                      size: 14, color: POSColors.greenDark),
                  const SizedBox(width: 4),
                  Text(
                    'Para Üstü: ₺${change.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: POSColors.greenDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItem({
    required String title,
    required String value,
    required Color valueColor,
    required Color backgroundColor,
    required IconData icon,
    String? subtitle,
    String? statusBadge,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: POSColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: POSColors.textSecondary),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: POSColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (statusBadge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: statusBadge == 'Tamam'
                        ? POSColors.greenDark
                        : POSColors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusBadge,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: valueColor,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: POSColors.amberDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
