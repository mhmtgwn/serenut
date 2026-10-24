// core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart
import '../../domain/models/core_entities.dart';
import '../../domain/models/money_cents.dart';

/// Sepetteki her bir satır kalemi (Kuruş bazlı değişmez model)
class CoreCartItem {
  final ProductEntity product;
  final int quantity; // Adet veya gramaj
  final MoneyCents unitPrice;
  final MoneyCents discount;
  final bool isWeighed; // Tartılı ürün mü? (Gram bazında hesaplanır)

  const CoreCartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.discount = MoneyCents.zero,
    this.isWeighed = false,
  });

  /// Satır tutarı (Kuruş)
  MoneyCents get lineTotal {
    if (isWeighed) {
      // 1 kg = 1000 gram. Örn: 100 TL/kg (10000 kuruş), 450 gram = 4500 kuruş
      // Ticari yarım-yukarı (commercial half-up) yuvarlama:
      // Tamsayı aritmetiğiyle 0.5 kuruş ve üzeri yukarı tamamlanır.
      final int rawCents;
      if (quantity >= 0) {
        rawCents = (unitPrice.value * quantity + 500) ~/ 1000;
      } else {
        rawCents = (unitPrice.value * quantity - 500) ~/ 1000;
      }
      final discounted = rawCents - discount.value;
      return MoneyCents(discounted > 0 ? discounted : 0);
    } else {
      final discounted = (unitPrice.value * quantity) - discount.value;
      return MoneyCents(discounted > 0 ? discounted : 0);
    }
  }


  CoreCartItem copyWith({
    int? quantity,
    MoneyCents? discount,
  }) {
    return CoreCartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice,
      discount: discount ?? this.discount,
      isWeighed: isWeighed,
    );
  }
}

/// Kasa Satış Akışı Durumu (Immutable State)
class CoreSalesFlowState {
  final List<CoreCartItem> items;
  final CustomerEntity? selectedCustomer;
  final MoneyCents generalDiscount;
  final List<PaymentSplitEntity> paymentSplits;
  final bool isSubmitting;
  final SaleOrderEntity? lastCompletedSale;
  final String? errorMessage;

  const CoreSalesFlowState({
    this.items = const [],
    this.selectedCustomer,
    this.generalDiscount = MoneyCents.zero,
    this.paymentSplits = const [],
    this.isSubmitting = false,
    this.lastCompletedSale,
    this.errorMessage,
  });

  /// Sepetteki ürünlerin indirimsiz ara toplamı
  MoneyCents get subtotal {
    var sum = 0;
    for (final item in items) {
      sum += item.lineTotal.value;
    }
    return MoneyCents(sum);
  }

  /// Genel toplam (Ara Toplam - Genel İskonto)
  MoneyCents get total {
    final t = subtotal.value - generalDiscount.value;
    return MoneyCents(t > 0 ? t : 0);
  }

  /// Ödenen / Tahsil edilen toplam tutar
  MoneyCents get paidTotal {
    var sum = 0;
    for (final split in paymentSplits) {
      if (split.type != PaymentType.onAccount) {
        sum += split.amount.value;
      }
    }
    return MoneyCents(sum);
  }

  /// Veresiye / Kalan borç tutarı
  MoneyCents get debtTotal {
    final debt = total.value - paidTotal.value;
    return MoneyCents(debt > 0 ? debt : 0);
  }

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, item) => sum + (item.isWeighed ? 1 : item.quantity));

  CoreSalesFlowState copyWith({
    List<CoreCartItem>? items,
    CustomerEntity? Function()? selectedCustomer,
    MoneyCents? generalDiscount,
    List<PaymentSplitEntity>? paymentSplits,
    bool? isSubmitting,
    SaleOrderEntity? Function()? lastCompletedSale,
    String? Function()? errorMessage,
  }) {
    return CoreSalesFlowState(
      items: items ?? this.items,
      selectedCustomer: selectedCustomer != null ? selectedCustomer() : this.selectedCustomer,
      generalDiscount: generalDiscount ?? this.generalDiscount,
      paymentSplits: paymentSplits ?? this.paymentSplits,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      lastCompletedSale: lastCompletedSale != null ? lastCompletedSale() : this.lastCompletedSale,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}
