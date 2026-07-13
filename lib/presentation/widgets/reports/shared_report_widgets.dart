import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';

// ════════════════════════════════════════════════════════════
// Shared Widgets for Reports
// ════════════════════════════════════════════════════════════

class ReportSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const ReportSectionHeader({super.key, required this.title, this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: POSColors.greenDark),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ],
    );
  }
}

class ReportMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bg;
  final String? subtitle;

  const ReportMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bg,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  )),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }
}

class AgingBucketCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const AgingBucketCard({
    super.key,
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            formatReportCurrency(amount),
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 9, color: color),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════

Widget buildEmptyReportState(String message) {
  return Container(
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    ),
  );
}

Widget buildErrorReportCard(String message) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red[50],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red[200]!),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline, color: Colors.red[700]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: TextStyle(color: Colors.red[700], fontSize: 13)),
        ),
      ],
    ),
  );
}

String formatReportCurrency(double val) {
  if (val >= 1000000) {
    return '${NumberFormat('#,###.##', 'tr_TR').format(val / 1000000)}M';
  }
  if (val >= 1000) {
    return NumberFormat('#,###', 'tr_TR').format(val);
  }
  return NumberFormat('#,###.##', 'tr_TR').format(val);
}
