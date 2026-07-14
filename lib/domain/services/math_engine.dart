/// Math Engine = Hesaplama kuralları (sistem içinde tutarlılık)
/// UI hesap yapmaz — sistem hesaplar
/// Kurallar:
/// - total = sum(items)
/// - vat = category.vatRate * itemPrice
/// - debt = total - paid
/// - balance = sum(transactions)
library;

class ItemLine {
  final double price;
  final int quantity;
  final double? vatRate;

  ItemLine({required this.price, required this.quantity, this.vatRate = 0});

  double get subtotal => price * quantity;
}

class MathEngine {
  /// Toplam hesapla (items)
  static double calculateTotal(List<ItemLine> items) {
    return items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  ///VAT hesapla (item level)
  static double calculateItemVat(double itemPrice, double vatRate) {
    return itemPrice * (vatRate / 100);
  }

  /// Item toplam (price + vat)
  static double calculateItemTotal(double itemPrice, double vatRate) {
    return itemPrice + calculateItemVat(itemPrice, vatRate);
  }

  /// Mal defteri toplam VAT (all items)
  static double calculateTotalVat(List<ItemLine> items) {
    double totalVat = 0.0;
    for (final item in items) {
      if (item.vatRate != null) {
        totalVat += calculateItemVat(item.subtotal, item.vatRate!);
      }
    }
    return totalVat;
  }

  /// Toplam + VAT = Final amount
  static double calculateGrandTotal(List<ItemLine> items) {
    final subtotal = calculateTotal(items);
    final vat = calculateTotalVat(items);
    return subtotal + vat;
  }

  /// Borç hesapla (ödenmiş - toplam = debt)
  /// Eğer paid < total → debt var
  static double calculateDebt(double total, double paid) {
    final debt = total - paid;
    return debt > 0 ? debt : 0.0;
  }

  /// Para üstü (paid - total)
  static double calculateChange(double total, double paid) {
    final change = paid - total;
    return change > 0 ? change : 0.0;
  }

  /// Müşteri bakiyesi (SUM_TL) = sum(all transactions)
  /// Kuralı: müşteri satıştan sonra yapılan ödeme negatif (+), satış borcu pozitif (-)
  /// Örnek: 100 TL satış (borç) = +100, 50 TL ödeme = -50, net = +50 (müşteri 50 borcu var)
  static double calculateCustomerBalance(List<double> transactions) {
    return transactions.fold(0.0, (sum, txn) => sum + txn);
  }

  /// Discount yüzde uygula
  static double applyDiscountPercent(double amount, double discountPercent) {
    return amount * (1 - (discountPercent / 100));
  }

  /// Discount TL uygula
  static double applyDiscountTL(double amount, double discountTL) {
    final result = amount - discountTL;
    return result > 0 ? result : 0.0;
  }

  /// Markup hesapla (cost → selling price)
  static double calculateMarkup(double costPrice, double markupPercent) {
    return costPrice * (1 + (markupPercent / 100));
  }

  /// Profit margin hesapla
  static double calculateProfitMargin(double costPrice, double sellingPrice) {
    if (costPrice == 0) return 0.0;
    return ((sellingPrice - costPrice) / costPrice) * 100;
  }

  /// Ortalama fiyat (weighted avg)
  static double calculateWeightedAveragePrice(List<ItemLine> items) {
    final totalQuantity =
        items.fold<int>(0, (sum, item) => sum + item.quantity);
    if (totalQuantity == 0) return 0.0;

    final totalValue =
        items.fold<double>(0.0, (sum, item) => sum + item.subtotal);
    return totalValue / totalQuantity;
  }

  /// Floating point karşılaştırması (tolerance: 0.01 TL)
  static bool areEqual(double a, double b, {double tolerance = 0.01}) {
    return (a - b).abs() < tolerance;
  }

  /// Round to 2 decimal places (TL)
  static double roundTL(double value) {
    return (value * 100).round() / 100;
  }

  /// Validation: total > 0
  static bool isValidTotal(double total) => total > 0;

  /// Validation: paid >= 0 && paid <= total (for partial payments)
  static bool isValidPayment(double paid, double total) =>
      paid >= 0 && paid <= total;

  /// Validation: vat between 0-100
  static bool isValidVatRate(double vatRate) => vatRate >= 0 && vatRate <= 100;
}
