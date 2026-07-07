// lib/domain/services/order_math_engine.dart
import 'package:serenutos/domain/services/math_engine.dart';

class OrderMathEngine {
  /// Safely multiply price and quantity avoiding floating point drifts
  static double calculateItemSubtotal(double unitPrice, double quantity) {
    return MathEngine.roundTL(unitPrice * quantity);
  }

  /// Calculate total of list of items
  static double calculateTotal(List<Map<String, dynamic>> items) {
    double sum = 0.0;
    for (final item in items) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] ?? item['unitPrice'] as num?)?.toDouble() ?? 0.0;
      sum += calculateItemSubtotal(price, qty);
    }
    return MathEngine.roundTL(sum);
  }

  /// Safely parse user input string to double (accepting comma/dot)
  static double parseDouble(String text) {
    final cleaned = text.trim().replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
