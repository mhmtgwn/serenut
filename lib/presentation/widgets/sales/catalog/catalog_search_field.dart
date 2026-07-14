part of '../catalog_panel.dart';

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
        prefixIcon: Icon(prefixIcon, color: _kTextSecondary, size: 20),
        suffixIcon: onClear != null
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: _kTextSecondary,
                onPressed: onClear,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kGreen, width: 2),
        ),
        filled: true,
        fillColor: _kSurface,
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

// ── Barkod Alanı Bileşeni ─────────────────────────────────────────────────────



// ── Ürün Kartı ────────────────────────────────────────────────────────────────

