part of '../../orders_page.dart';

// ── Durum Meta ────────────────────────────────────────────────────────────────
class _StatusMeta {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;
  const _StatusMeta(
      {required this.color,
      required this.bg,
      required this.icon,
      required this.label});
}

_StatusMeta _statusMeta(String status) {
  switch (status.toLowerCase()) {
    case 'created':
    case 'pending':
    case 'new':
      return const _StatusMeta(
          color: Color(0xFF0284C7),
          bg: Color(0xFFE0F2FE),
          icon: Icons.fiber_new_rounded,
          label: 'Yeni');
    case 'preparing':
    case 'processing':
    case 'in_progress':
      return const _StatusMeta(
          color: Color(0xFFD97706),
          bg: Color(0xFFFEF3C7),
          icon: Icons.hourglass_top_rounded,
          label: 'Hazırlanıyor');
    case 'ready':
      return const _StatusMeta(
          color: Color(0xFF16A34A),
          bg: Color(0xFFDCFCE7),
          icon: Icons.check_circle_rounded,
          label: 'Hazır');
    case 'on_way':
    case 'shipped':
    case 'out_for_delivery':
    case 'kuryede':
    case 'dagitimda':
      return const _StatusMeta(
          color: Color(0xFF7C3AED),
          bg: Color(0xFFEDE9FE),
          icon: Icons.delivery_dining_rounded,
          label: 'Kuryede / Yolda');
    case 'delivered':
    case 'completed':
      return const _StatusMeta(
          color: Color(0xFF475569),
          bg: Color(0xFFE2E8F0),
          icon: Icons.task_alt_rounded,
          label: 'Teslim Edildi');
    case 'paid':
      return const _StatusMeta(
          color: Color(0xFF16A34A),
          bg: Color(0xFFDCFCE7),
          icon: Icons.paid_outlined,
          label: 'Ödendi');
    case 'cancelled':
    case 'canceled':
      return const _StatusMeta(
          color: Color(0xFFDC2626),
          bg: Color(0xFFFEE2E2),
          icon: Icons.cancel_outlined,
          label: 'İptal');
    case 'refunded':
    case 'returned':
      return const _StatusMeta(
          color: Color(0xFFDB2777),
          bg: Color(0xFFFCE7F3),
          icon: Icons.assignment_return_outlined,
          label: 'İade Edildi');
    case 'unpaid':
    case 'failed':
      return const _StatusMeta(
          color: Color(0xFFEA580C),
          bg: Color(0xFFFFEDD5),
          icon: Icons.error_outline_rounded,
          label: 'Ödenmedi');
    default:
      return const _StatusMeta(
          color: Color(0xFF64748B),
          bg: Color(0xFFF1F5F9),
          icon: Icons.help_outline_rounded,
          label: 'Diğer');
  }
}

Color _statusCardBg(String status, bool isSelected) {
  if (isSelected) return const Color(0xFFDCFCE7);
  switch (status.toLowerCase()) {
    case 'created':
    case 'pending':
    case 'new':
      return const Color(0xFFF0F9FF); // Soft gök mavisi
    case 'preparing':
    case 'processing':
    case 'in_progress':
      return const Color(0xFFFFFDF5); // Dingin, soft amber / krem
    case 'ready':
      return const Color(0xFFF0FDF4); // Ferah açık zümrüt nane
    case 'on_way':
    case 'shipped':
    case 'out_for_delivery':
    case 'kuryede':
    case 'dagitimda':
      return const Color(0xFFF8F6FF); // Soft lavanta / lila
    case 'delivered':
    case 'completed':
      return const Color(0xFFF8FAFC); // Sakin nötr asil çelik gri (kapanmış)
    case 'paid':
      return const Color(0xFFF4FAF5); // Dingin taze nane
    case 'cancelled':
    case 'canceled':
      return const Color(0xFFFFF5F5); // Soft mercan / gül
    case 'refunded':
    case 'returned':
      return const Color(0xFFFFF5FA); // Soft fuşya / pembe
    case 'unpaid':
    case 'failed':
      return const Color(0xFFFFF8F2); // Soft turuncu
    default:
      return const Color(0xFFF8FAFC); // Açık slate gri
  }
}

Color _statusCardBorder(String status, bool isSelected) {
  if (isSelected) return _kGreen;
  switch (status.toLowerCase()) {
    case 'created':
    case 'pending':
    case 'new':
      return const Color(0xFF7DD3FC).withValues(alpha: 0.55);
    case 'preparing':
    case 'processing':
    case 'in_progress':
      return const Color(0xFFFCD34D).withValues(alpha: 0.55);
    case 'ready':
      return const Color(0xFF86EFAC).withValues(alpha: 0.65); // green-300
    case 'on_way':
    case 'shipped':
    case 'out_for_delivery':
    case 'kuryede':
    case 'dagitimda':
      return const Color(0xFFC4B5FD).withValues(alpha: 0.55);
    case 'delivered':
    case 'completed':
      return const Color(0xFFCBD5E1).withValues(alpha: 0.65); // slate-300
    case 'paid':
      return const Color(0xFF86EFAC).withValues(alpha: 0.55);
    case 'cancelled':
    case 'canceled':
      return const Color(0xFFFCA5A5).withValues(alpha: 0.55);
    case 'refunded':
    case 'returned':
      return const Color(0xFFF472B6).withValues(alpha: 0.55);
    case 'unpaid':
    case 'failed':
      return const Color(0xFFFDBA74).withValues(alpha: 0.55);
    default:
      return const Color(0xFFCBD5E1).withValues(alpha: 0.55);
  }
}
