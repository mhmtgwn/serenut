part of '../../orders_page.dart';

// ── Durum Meta ────────────────────────────────────────────────────────────────
class _StatusMeta {
  final Color color;
  final Color bg;
  final Color cardBg;
  final Color borderColor;
  final Color amountBg;
  final Color amountColor;
  final IconData icon;
  final String label;

  const _StatusMeta({
    required this.color,
    required this.bg,
    required this.cardBg,
    required this.borderColor,
    required this.amountBg,
    required this.amountColor,
    required this.icon,
    required this.label,
  });
}

_StatusMeta _statusMeta(String status) {
  switch (status.toLowerCase()) {
    case 'created':
    case 'pending':
    case 'new':
      return const _StatusMeta(
        color: Color(0xFF0284C7), // Sky 600
        bg: Color(0xFFE0F2FE), // Sky 100
        cardBg: Color(0xFFF0F9FF), // Sky 50
        borderColor: Color(0xFF38BDF8), // Sky 400
        amountBg: Color(0xFFE0F2FE), // Sky 100
        amountColor: Color(0xFF0369A1), // Sky 700
        icon: Icons.fiber_new_rounded,
        label: 'Yeni',
      );
    case 'preparing':
    case 'processing':
    case 'in_progress':
      return const _StatusMeta(
        color: Color(0xFFD97706), // Amber 600
        bg: Color(0xFFFEF3C7), // Amber 100
        cardBg: Color(0xFFFFFBEB), // Amber 50
        borderColor: Color(0xFFF59E0B), // Amber 500
        amountBg: Color(0xFFFEF3C7), // Amber 100
        amountColor: Color(0xFFB45309), // Amber 700
        icon: Icons.hourglass_top_rounded,
        label: 'Hazırlanıyor',
      );
    case 'ready':
      return const _StatusMeta(
        color: Color(0xFF16A34A), // Emerald 600
        bg: Color(0xFFDCFCE7), // Emerald 100
        cardBg: Color(0xFFF0FDF4), // Emerald 50
        borderColor: Color(0xFF22C55E), // Emerald 500
        amountBg: Color(0xFFDCFCE7), // Emerald 100
        amountColor: Color(0xFF15803D), // Emerald 700
        icon: Icons.check_circle_rounded,
        label: 'Hazır',
      );
    case 'on_way':
    case 'shipped':
    case 'out_for_delivery':
    case 'kuryede':
    case 'dagitimda':
      return const _StatusMeta(
        color: Color(0xFF7C3AED), // Violet 600
        bg: Color(0xFFEDE9FE), // Violet 100
        cardBg: Color(0xFFF5F3FF), // Violet 50
        borderColor: Color(0xFF8B5CF6), // Violet 500
        amountBg: Color(0xFFEDE9FE), // Violet 100
        amountColor: Color(0xFF6D28D9), // Violet 700
        icon: Icons.delivery_dining_rounded,
        label: 'Kuryede / Yolda',
      );
    case 'delivered':
    case 'completed':
      return const _StatusMeta(
        color: Color(0xFF475569), // Slate 600
        bg: Color(0xFFE2E8F0), // Slate 200
        cardBg: Color(0xFFF8FAFC), // Slate 50
        borderColor: Color(0xFF94A3B8), // Slate 400
        amountBg: Color(0xFFE2E8F0), // Slate 200
        amountColor: Color(0xFF334155), // Slate 700
        icon: Icons.task_alt_rounded,
        label: 'Teslim Edildi',
      );
    case 'paid':
      return const _StatusMeta(
        color: Color(0xFF0D9488), // Teal 600
        bg: Color(0xFFCCFBF1), // Teal 100
        cardBg: Color(0xFFF0FDFA), // Teal 50
        borderColor: Color(0xFF14B8A6), // Teal 500
        amountBg: Color(0xFFCCFBF1), // Teal 100
        amountColor: Color(0xFF0F766E), // Teal 700
        icon: Icons.paid_outlined,
        label: 'Ödendi',
      );
    case 'cancelled':
    case 'canceled':
      return const _StatusMeta(
        color: Color(0xFFDC2626), // Red 600
        bg: Color(0xFFFEE2E2), // Red 100
        cardBg: Color(0xFFFEF2F2), // Red 50
        borderColor: Color(0xFFEF4444), // Red 500
        amountBg: Color(0xFFFEE2E2), // Red 100
        amountColor: Color(0xFFB91C1C), // Red 700
        icon: Icons.cancel_outlined,
        label: 'İptal',
      );
    case 'refunded':
    case 'returned':
      return const _StatusMeta(
        color: Color(0xFFDB2777), // Pink 600
        bg: Color(0xFFFCE7F3), // Pink 100
        cardBg: Color(0xFFFDF2F8), // Pink 50
        borderColor: Color(0xFFEC4899), // Pink 500
        amountBg: Color(0xFFFCE7F3), // Pink 100
        amountColor: Color(0xFF9D174D), // Pink 700
        icon: Icons.assignment_return_outlined,
        label: 'İade Edildi',
      );
    case 'unpaid':
    case 'failed':
      return const _StatusMeta(
        color: Color(0xFFEA580C), // Orange 600
        bg: Color(0xFFFFEDD5), // Orange 100
        cardBg: Color(0xFFFFF7ED), // Orange 50
        borderColor: Color(0xFFF97316), // Orange 500
        amountBg: Color(0xFFFFEDD5), // Orange 100
        amountColor: Color(0xFFC2410C), // Orange 700
        icon: Icons.error_outline_rounded,
        label: 'Ödenmedi',
      );
    default:
      return const _StatusMeta(
        color: Color(0xFF64748B),
        bg: Color(0xFFF1F5F9),
        cardBg: Color(0xFFF8FAFC),
        borderColor: Color(0xFFCBD5E1),
        amountBg: Color(0xFFF1F5F9),
        amountColor: Color(0xFF475569),
        icon: Icons.help_outline_rounded,
        label: 'Diğer',
      );
  }
}

Color _statusCardBg(String status, bool isSelected) {
  if (isSelected) return const Color(0xFFDCFCE7);
  return _statusMeta(status).cardBg;
}

Color _statusCardBorder(String status, bool isSelected) {
  if (isSelected) return _kGreen;
  return _statusMeta(status).borderColor;
}
