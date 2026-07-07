// lib/presentation/pages/onboarding/widgets/step_indicator.dart
// Premium adım göstergesi: ●────○────○

import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';

class StepIndicator extends StatelessWidget {
  final int totalSteps;
  final int currentStep; // 0-indexed

  const StepIndicator({
    super.key,
    required this.totalSteps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps * 2 - 1, (i) {
        if (i.isOdd) {
          // Bağlantı çizgisi
          final stepIndex = i ~/ 2;
          final isCompleted = currentStep > stepIndex;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 2,
              decoration: BoxDecoration(
                color: isCompleted ? POSColors.green : POSColors.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        } else {
          // Adım noktası
          final stepIndex = i ~/ 2;
          final isCompleted = currentStep > stepIndex;
          final isCurrent   = currentStep == stepIndex;
          return _StepDot(
            index:       stepIndex + 1,
            isCompleted: isCompleted,
            isCurrent:   isCurrent,
          );
        }
      }),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final bool isCompleted;
  final bool isCurrent;

  const _StepDot({
    required this.index,
    required this.isCompleted,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isCompleted
        ? POSColors.green
        : isCurrent
            ? POSColors.green
            : Colors.white;

    final Color border = (isCompleted || isCurrent)
        ? POSColors.green
        : POSColors.border;

    final double size = isCurrent ? 32 : 26;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width:  size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
        boxShadow: isCurrent
            ? [BoxShadow(color: POSColors.green.withValues(alpha: 0.30), blurRadius: 8, spreadRadius: 1)]
            : null,
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check, color: Colors.white, size: 14)
            : Text(
                '$index',
                style: TextStyle(
                  fontSize: isCurrent ? 13 : 11,
                  fontWeight: FontWeight.w700,
                  color: isCurrent ? Colors.white : POSColors.textSecondary,
                ),
              ),
      ),
    );
  }
}
