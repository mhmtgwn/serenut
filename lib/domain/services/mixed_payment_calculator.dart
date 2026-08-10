import 'package:serenutos/domain/services/math_engine.dart';

class MixedPaymentResult {
  const MixedPaymentResult({
    required this.total,
    required this.cashTendered,
    required this.cashApplied,
    required this.card,
    required this.debt,
    required this.change,
    required this.remaining,
    required this.isValid,
  });

  final double total;
  final double cashTendered;
  final double cashApplied;
  final double card;
  final double debt;
  final double change;
  final double remaining;
  final bool isValid;

  double get paidAmount => MathEngine.roundTL(cashApplied + card);
  double get allocatedTotal => MathEngine.roundTL(cashApplied + card + debt);
}

class MixedPaymentCalculator {
  const MixedPaymentCalculator._();

  static MixedPaymentResult calculate({
    required double total,
    required double cashTendered,
    required double card,
    required double debt,
  }) {
    final values = [total, cashTendered, card, debt];
    final valuesValid = values.every((value) => value.isFinite && value >= 0);
    if (!valuesValid || total <= 0) {
      return MixedPaymentResult(
        total: total,
        cashTendered: cashTendered,
        cashApplied: 0,
        card: card,
        debt: debt,
        change: 0,
        remaining: total > 0 ? total : 0,
        isValid: false,
      );
    }

    final roundedTotal = MathEngine.roundTL(total);
    final roundedCard = MathEngine.roundTL(card);
    final roundedDebt = MathEngine.roundTL(debt);
    final roundedTendered = MathEngine.roundTL(cashTendered);
    final nonCash = MathEngine.roundTL(roundedCard + roundedDebt);
    final nonCashValid = nonCash <= roundedTotal + 0.009;
    final cashDue = MathEngine.roundTL(
      (roundedTotal - nonCash).clamp(0.0, double.infinity),
    );
    final cashApplied = MathEngine.roundTL(
      roundedTendered.clamp(0.0, cashDue),
    );
    final remaining = MathEngine.roundTL(
      (roundedTotal - nonCash - cashApplied).clamp(0.0, double.infinity),
    );
    final change = MathEngine.roundTL(
      (roundedTendered - cashDue).clamp(0.0, double.infinity),
    );

    return MixedPaymentResult(
      total: roundedTotal,
      cashTendered: roundedTendered,
      cashApplied: cashApplied,
      card: roundedCard,
      debt: roundedDebt,
      change: change,
      remaining: remaining,
      isValid: nonCashValid && remaining < 0.01,
    );
  }
}
