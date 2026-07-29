// lib/presentation/widgets/pos_filter_bar.dart
// Modern, horizontal scrollable filter pills for Serenut OS

import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';

class PosFilterChipData {
  final String id;
  final String label;
  final int? count;
  final Color? color;
  final IconData? icon;

  const PosFilterChipData({
    required this.id,
    required this.label,
    this.count,
    this.color,
    this.icon,
  });
}

class PosFilterBar extends StatelessWidget {
  final List<PosFilterChipData> items;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry padding;

  const PosFilterBar({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: items.map((item) {
          final isSelected = item.id == selectedId;
          final chipColor = item.color ?? POSColors.green;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(item.id),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? chipColor : POSColors.card,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(
                      color: isSelected ? chipColor : POSColors.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.icon != null) ...[
                        Icon(
                          item.icon,
                          size: 15,
                          color: isSelected
                              ? Colors.white
                              : POSColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? Colors.white : POSColors.text,
                        ),
                      ),
                      if (item.count != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : POSColors.greenLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.count}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : POSColors.greenDark,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
