part of '../checkout_section.dart';

class _PayButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final bool disabled;
  final double height;
  final VoidCallback onTap;

  const _PayButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.disabled,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = disabled ? _kSurface : color;
    final fg = disabled ? _kTextSecondary : Colors.white;

    return SizedBox(
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: disabled ? Border.all(color: _kBorder) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    color:
                        disabled ? _kTextSecondary : fg.withValues(alpha: 0.8),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── KARMA Geçiş Butonu (küçük) ────────────────────────────────────────────────

class _KarmaToggleButton extends StatelessWidget {
  final bool disabled;
  final VoidCallback onTap;

  const _KarmaToggleButton({required this.disabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: 44,
      child: Material(
        color: disabled
            ? _kSurface
            : const Color(0xFF7C3AED).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: disabled
                    ? _kBorder
                    : const Color(0xFF7C3AED).withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.call_split_rounded,
                  size: 16,
                  color: disabled ? _kTextSecondary : const Color(0xFF7C3AED),
                ),
                const SizedBox(height: 2),
                Text(
                  'MIX',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: disabled ? _kTextSecondary : const Color(0xFF7C3AED),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── KARMA İptal Butonu ────────────────────────────────────────────────────────

class _CancelKarmaButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelKarmaButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: 44,
      child: Material(
        color: _kRedLight,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 18, color: _kRed),
              SizedBox(height: 2),
              Text(
                'İptal',
                style: TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w800, color: _kRed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── MÜŞTERİ SEÇİM BOTTOM SHEET ────────────────────────────────────────────────
