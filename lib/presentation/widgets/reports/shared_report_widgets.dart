import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';

class ReportScrollView extends StatelessWidget {
  const ReportScrollView({
    super.key,
    required this.children,
    required this.onRefresh,
  });

  final List<Widget> children;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth < 720 ? 12 : 24,
            18,
            constraints.maxWidth < 720 ? 12 : 24,
            32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class ReportPanel extends StatelessWidget {
  const ReportPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = POSColors.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
        boxShadow: const [
          BoxShadow(
            color: POSColors.shadowColor,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ReportSectionHeader extends StatelessWidget {
  const ReportSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: POSColors.greenDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    eyebrow!.toUpperCase(),
                    style: const TextStyle(
                      color: POSColors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (trailing == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            trailing!,
          ],
        );
      },
    );
  }
}

class ReportMetricCard extends StatelessWidget {
  const ReportMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: POSColors.text,
                      ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReportPill extends StatelessWidget {
  const ReportPill({
    super.key,
    required this.label,
    required this.icon,
    this.color = POSColors.green,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class ReportLegend extends StatelessWidget {
  const ReportLegend({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class ReportLoadingCard extends StatelessWidget {
  const ReportLoadingCard({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ReportPanel(
      child: SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class ReportEmptyState extends StatelessWidget {
  const ReportEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ReportPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(icon, size: 38, color: POSColors.textDisabled),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class ReportErrorCard extends StatelessWidget {
  const ReportErrorCard({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: POSColors.redLight,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.red.withValues(alpha: .20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: POSColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: POSColors.red),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}

// Eski rapor bileşenlerini kullanan dış kodlar için küçük uyumluluk yardımcıları.
Widget buildEmptyReportState(String message) => ReportEmptyState(
      icon: Icons.inbox_outlined,
      title: 'Veri bulunamadı',
      message: message,
    );

Widget buildErrorReportCard(String message) =>
    ReportErrorCard(message: message);

String formatReportCurrency(double value) {
  final formatter = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '',
    decimalDigits: value == value.roundToDouble() ? 0 : 2,
  );
  return formatter.format(value).trim();
}
