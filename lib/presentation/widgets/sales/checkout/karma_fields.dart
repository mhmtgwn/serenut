part of '../checkout_section.dart';

class _KarmaSplitField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color color;
  final double remainder;
  final VoidCallback? onSuffixTap;
  final ValueChanged<String>? onChanged;

  const _KarmaSplitField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.color,
    required this.remainder,
    this.onSuffixTap,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showSuffix = remainder > 0.01;

    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
        prefixIcon: Icon(icon, color: color, size: 18),
        prefixText: '₺',
        prefixStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 0,
          minHeight: 0,
        ),
        suffixIcon: showSuffix
            ? Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: color.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onSuffixTap,
                  child: Text(
                    '+₺${remainder.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        filled: true,
        fillColor: color.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

// ── Ödeme Butonu ─────────────────────────────────────────────────────────────

