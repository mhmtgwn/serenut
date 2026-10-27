import 'package:uuid/uuid.dart';
import '../../domain/models/core_entities.dart';
import '../../domain/models/money_cents.dart';
import '../../domain/models/sync_mutation.dart';

/// Sunucu Sync V4 / Protocol 6 için ağ katmanından bağımsız DTO ve Payload Dönüştürücüsü.
/// 
/// Kuruş bazlı yerel varlıkları; sunucunun beklediği ondalık Lira formatına,
/// zorunlu kalem listesine (`items`), onaylı ödeme yöntemlerine (`payment_method`)
/// ve nedensel bağımlılık sıralamasına dönüştürür.
class SyncV4PayloadAdapter {
  static const _uuid = Uuid();

  /// Kuruş değerini kesinlikle 2 basamaklı ondalık Lira sayısına dönüştürür.
  /// (IEEE 754 kayan nokta sapmalarını engellemek için `toStringAsFixed(2)` kullanılır).
  static double toLira(MoneyCents cents) {
    return double.parse((cents.value / 100.0).toStringAsFixed(2));
  }

  /// Doğrudan kuruş tamsayısından Lira'ya dönüştürür.
  static double centsIntToLira(int centsValue) {
    return double.parse((centsValue / 100.0).toStringAsFixed(2));
  }

  /// Satış kaydını sunucunun Sync V4 `sale` mutasyonuna dönüştürür.
  static SyncMutation buildSaleMutation({
    required String saleId,
    required String receiptNo,
    required String? customerId,
    required List<SaleOrderItemEntity> orderItems,
    required MoneyCents subtotal,
    required MoneyCents generalDiscount,
    required MoneyCents total,
    required MoneyCents paid,
    required MoneyCents debt,
    required List<PaymentSplitEntity> splits,
    required DateTime createdAt,
    required String idempotencyKey,
    int baseRevision = 0,
    String? deterministicEventId,
  }) {
    // 1. Temel Doğrulamalar: Boş veya bozuk satış kabul edilmez
    if (orderItems.isEmpty) {
      throw ArgumentError('Satış en az bir ürün kalemi içermelidir (invalid_sale).');
    }

    double computedItemsTotal = 0.0;
    final normalizedItems = <Map<String, dynamic>>[];

    for (int i = 0; i < orderItems.length; i++) {
      final item = orderItems[i];
      if (item.quantity <= 0) {
        throw ArgumentError('Satış kalemi miktarı pozitif olmalıdır (invalid_sale_item).');
      }
      if (item.unitPrice.value < 0) {
        throw ArgumentError('Satış kalemi birim fiyatı negatif olamaz (invalid_sale_item).');
      }

      final unitPriceLira = toLira(item.unitPrice);
      final subtotalLira = toLira(item.total);
      computedItemsTotal += subtotalLira;

      // Tartılı ürünlerde miktar gram cinsinden tutulduğu için kilogram standardına normalize et
      final isWeighed = item.isWeighed ||
          (item.quantity > 0 &&
              item.unitPrice.value > 0 &&
              ((item.unitPrice.value * item.quantity) - item.total.value).abs() > 5 &&
              (((item.unitPrice.value * item.quantity) / 1000.0) - item.total.value).abs() <= 5);
      final effectiveQuantity = isWeighed
          ? double.parse((item.quantity / 1000.0).toStringAsFixed(3))
          : item.quantity.toDouble();

      normalizedItems.add({
        'id': item.id,
        'product_id': item.productId,
        'product_name': item.productName,
        'quantity': effectiveQuantity,
        'is_weighed': isWeighed,
        'unit_price': unitPriceLira,
        'subtotal': subtotalLira,
        'created_at': createdAt.toUtc().toIso8601String(),
      });
    }

    final totalLira = toLira(total);
    final paidLira = toLira(paid);
    final discountLira = toLira(generalDiscount);

    // 2. Matematiksel Doğrulama (Sunucu: Math.abs(clientTotal - expectedTotal) <= 0.05)
    final expectedTotalLira = double.parse(
      ((computedItemsTotal - discountLira) > 0 ? (computedItemsTotal - discountLira) : 0.0)
          .toStringAsFixed(2),
    );
    if ((totalLira - expectedTotalLira).abs() > 0.05) {
      throw StateError(
        'Satış genel toplamı ile kalemler toplamı uyuşmuyor (sale_total_mismatch): Toplam=$totalLira, Beklenen=$expectedTotalLira',
      );
    }

    // 3. Ödeme Yöntemi ve Ödenen Tutarın Çözümlenmesi
    final String paymentMethod;
    if (debt.value > 0 && paid.value == 0) {
      paymentMethod = 'veresiye';
    } else if (debt.value == 0) {
      final cashSplits = splits.where((s) => s.type == PaymentType.cash).toList();
      final cardSplits = splits.where((s) => s.type == PaymentType.creditCard).toList();

      if (cashSplits.isNotEmpty && cardSplits.isEmpty && splits.length == cashSplits.length) {
        paymentMethod = 'cash';
      } else if (cardSplits.isNotEmpty && cashSplits.isEmpty && splits.length == cardSplits.length) {
        paymentMethod = 'card';
      } else {
        paymentMethod = 'mixed';
      }
    } else {
      // debt > 0 && paid > 0 (kısmi peşinat, kısmi veresiye)
      paymentMethod = 'mixed';
    }

    // 4. Sunucu Kural Doğrulamaları
    if ((paymentMethod == 'veresiye' || paymentMethod == 'credit' || paymentMethod == 'debt') &&
        paidLira != 0) {
      throw StateError('Veresiye satışta peşin ödenen tutar 0 olmalıdır (invalid_credit_payment).');
    }
    if (paymentMethod == 'card' && (paidLira - expectedTotalLira).abs() > 0.05) {
      throw StateError('Kart ile ödemede tam tahsilat zorunludur (invalid_full_payment).');
    }
    if (paymentMethod == 'cash' && paidLira < expectedTotalLira - 0.05) {
      throw StateError('Nakit ödemede ödenen tutar toplamı karşılamalıdır (invalid_full_payment).');
    }

    final payload = <String, dynamic>{
      'id': saleId,
      'customer_id': (customerId != null && customerId.trim().isNotEmpty) ? customerId.trim() : null,
      'total_amount': totalLira,
      'paid_amount': paidLira,
      'discount_amount': discountLira,
      'payment_method': paymentMethod,
      'idempotency_key': idempotencyKey,
      'items': normalizedItems,
      'created_at': createdAt.toUtc().toIso8601String(),
    };

    return SyncMutation(
      eventId: deterministicEventId ?? _uuid.v4(),
      entityType: 'sale', // KESİNLİKLE KÜÇÜK HARF
      entityId: saleId,
      operation: 'UPSERT',
      payload: payload,
      baseRevision: baseRevision,
      clientTimestamp: createdAt.millisecondsSinceEpoch,
      syncState: 'PENDING',
      attempts: 0,
      groupId: saleId,
      causalSequence: 1, // Satış grubu içinde 1. sıra
    );
  }

  /// Satışa bağlı müşteri cari borcunu sunucunun `financial_transaction` mutasyonuna dönüştürür.
  static SyncMutation buildFinancialTransactionMutation({
    required String saleId,
    required String customerId,
    required MoneyCents total,
    required MoneyCents paid,
    required MoneyCents debt,
    required String paymentMethod,
    required DateTime createdAt,
    int baseRevision = 0,
    String? deterministicEventId,
    String? deterministicEntityId,
  }) {
    return buildFinancialMutation(
      id: deterministicEntityId ?? _uuid.v4(),
      type: 'sale',
      customerId: customerId,
      total: total,
      paid: paid,
      debt: debt,
      referenceId: saleId,
      paymentMethod: paymentMethod,
      createdAt: createdAt,
      baseRevision: baseRevision,
      deterministicEventId: deterministicEventId,
      groupId: saleId,
      causalSequence: 2,
    );
  }

  /// Genel finansal işlem mutasyonu oluşturucu (Protocol 6 uyumlu).
  /// Desteklenen sunucu tipleri: 'sale', 'payment', 'collection', 'manual_debt', 'cancellation', 'refund'.
  static SyncMutation buildFinancialMutation({
    required String id,
    required String type, // 'sale', 'payment', 'collection', 'manual_debt', 'cancellation', 'refund'
    required String customerId,
    required MoneyCents total,
    required MoneyCents paid,
    required MoneyCents debt,
    String? referenceId,
    String? paymentMethod,
    String? description,
    required DateTime createdAt,
    int baseRevision = 0,
    String? deterministicEventId,
    String? groupId,
    int causalSequence = 0,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError('Finansal işlem kimliği (id) boş olamaz.');
    }
    if (customerId.trim().isEmpty) {
      throw ArgumentError('Finansal işlem için geçerli bir customer_id zorunludur.');
    }

    // 1. Negatif Değer Koruması (Fail-Closed)
    if (total.value < 0 || paid.value < 0 || debt.value < 0) {
      throw ArgumentError(
        'Negatif tutarlı finansal hareketler Sync V4 protokolünde desteklenmez: '
        'Toplam=${total.value}, Ödenen=${paid.value}, Borç=${debt.value}',
      );
    }

    final amountLira = toLira(total);
    final paidLira = toLira(paid);
    final debtLira = toLira(debt);

    // 2. Tür Eşleme ve Normalizasyon
    String resolvedType = type.trim().toLowerCase();
    if (resolvedType == 'debt') {
      // Yalnızca satış referansı olmayan doğrudan borç hareketleri manual_debt olur
      if (referenceId != null && referenceId.trim().isNotEmpty) {
        resolvedType = 'sale';
      } else {
        resolvedType = 'manual_debt';
      }
    }

    const validServerTypes = {
      'sale',
      'payment',
      'collection',
      'manual_debt',
      'cancellation',
      'refund',
    };
    if (!validServerTypes.contains(resolvedType)) {
      throw ArgumentError(
        'Desteklenmeyen finansal işlem türü: "$type" (İzin verilenler: ${validServerTypes.join(", ")})',
      );
    }

    // 3. Sunucu Matematiksel Sözleşme Doğrulamaları
    if (resolvedType == 'manual_debt') {
      if (amountLira <= 0 || paidLira != 0 || (amountLira - debtLira).abs() > 0.01) {
        throw StateError(
          'Geçersiz manual_debt hareketi: amount ($amountLira) pozitif olmalı, paid (0 olmalı, gelen $paidLira), debt ($debtLira) amount ile eşit olmalıdır.',
        );
      }
    } else if (resolvedType == 'collection') {
      if (amountLira <= 0 || (amountLira - paidLira).abs() > 0.01) {
        throw StateError(
          'Geçersiz collection hareketi: amount ($amountLira) pozitif ve paid_amount ($paidLira) ile eşit olmalıdır.',
        );
      }
    } else if (resolvedType == 'payment') {
      if (amountLira <= 0) {
        throw StateError('Geçersiz payment hareketi: amount ($amountLira) pozitif olmalıdır.');
      }
    } else if (resolvedType == 'sale') {
      if ((amountLira - paidLira - debtLira).abs() > 0.05) {
        throw StateError(
          'Satış finansal işlem tutar dengesi hatalı: Tutar=$amountLira, Ödenen=$paidLira, Borç=$debtLira',
        );
      }
    } else if (resolvedType == 'cancellation' || resolvedType == 'refund') {
      if (referenceId == null || referenceId.trim().isEmpty || amountLira <= 0 || paidLira > amountLira || debtLira > amountLira) {
        throw StateError('Geçersiz $resolvedType hareketi: referenceId zorunludur ve tutar sınırları aşılmamalıdır.');
      }
    }

    final payload = <String, dynamic>{
      'id': id.trim(),
      'type': resolvedType,
      'customer_id': customerId.trim(),
      'amount': amountLira,
      'paid_amount': paidLira,
      'debt_amount': debtLira,
      'reference_id': (referenceId != null && referenceId.trim().isNotEmpty) ? referenceId.trim() : null,
      'payment_method': paymentMethod ?? (resolvedType == 'manual_debt' ? 'veresiye' : 'cash'),
      'description': description ?? '',
      'date': createdAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      // İstemci yerel kuruş alanları
      'amount_cents': total.value,
      'paid_amount_cents': paid.value,
      'debt_amount_cents': debt.value,
    };

    return SyncMutation(
      eventId: deterministicEventId ?? _uuid.v4(),
      entityType: 'financial_transaction',
      entityId: id.trim(),
      operation: 'UPSERT',
      payload: payload,
      baseRevision: baseRevision,
      clientTimestamp: createdAt.millisecondsSinceEpoch,
      syncState: 'PENDING',
      attempts: 0,
      groupId: groupId,
      causalSequence: causalSequence,
    );
  }

  /// Ürün varlığını sunucunun Sync V4 / Protocol 6 `product` mutasyonuna dönüştürür.
  /// 
  /// Kuruş bazlı `price_cents` ve `cost_price_cents` değerlerini kesinlikle 2 basamaklı
  /// ondalık Lira (`price`, `purchase_price`) formatına dönüştürür.
  /// İstemci ve sunucu geriye dönük uyumluluğu için hem sunucu anahtarları (`price`,
  /// `purchase_price`, `quantity`), hem de yerel anahtarlar (`price_cents`,
  /// `cost_price_cents`, `stock_quantity`) birlikte yer alır.
  static SyncMutation buildProductMutation({
    required String productId,
    required String name,
    required int priceCents,
    int? costPriceCents,
    required num stockQuantity,
    num minStock = 5,
    String? category,
    String? unit,
    String saleType = 'piece',
    int minimumWeightGrams = 20,
    int? vatRate,
    String? imageUrl,
    bool isDeleted = false,
    required DateTime updatedAt,
    int baseRevision = 0,
    String? deterministicEventId,
    String operation = 'UPSERT',
  }) {
    final cleanId = productId.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('Ürün kimliği (id) boş olamaz.');
    }
    final cleanName = name.trim();
    if (operation == 'UPSERT' && cleanName.isEmpty) {
      throw ArgumentError('Ürün adı (name) boş olamaz (invalid_mutation).');
    }
    if (priceCents < 0) {
      throw ArgumentError('Ürün satış fiyatı negatif olamaz: $priceCents kuruş');
    }
    if (costPriceCents != null && costPriceCents < 0) {
      throw ArgumentError('Ürün maliyet fiyatı negatif olamaz: $costPriceCents kuruş');
    }

    final priceLira = centsIntToLira(priceCents);
    final costPriceLira = costPriceCents != null ? centsIntToLira(costPriceCents) : 0.0;
    final effectiveUnit = (unit != null && unit.trim().isNotEmpty) ? unit.trim() : 'adet';
    final effectiveCategory = (category != null && category.trim().isNotEmpty) ? category.trim() : 'Genel';
    final effectiveVat = vatRate ?? 20;

    final payload = <String, dynamic>{
      'id': cleanId,
      'barcode': cleanId,
      'name': cleanName,
      'description': cleanName,
      // Sunucu Protocol 6 alanları (Ondalık TL ve birim adet/kg)
      'price': priceLira,
      'purchase_price': costPriceLira,
      'quantity': stockQuantity,
      'min_stock': minStock,
      'unit': effectiveUnit,
      'sale_type': saleType,
      'minimum_weight_grams': minimumWeightGrams,
      'category': effectiveCategory,
      'vat': effectiveVat,
      'sku': cleanId,
      'image_url': imageUrl,
      'status': isDeleted ? 'inactive' : 'active',
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': updatedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      // İstemci yerel/çevrimdışı kuruş alanları
      'price_cents': priceCents,
      'cost_price_cents': costPriceCents,
      'stock_quantity': stockQuantity,
      'critical_threshold': minStock,
      'vat_rate': effectiveVat,
      'category_id': effectiveCategory,
    };

    return SyncMutation(
      eventId: deterministicEventId ?? _uuid.v4(),
      entityType: 'product',
      entityId: cleanId,
      operation: operation,
      payload: payload,
      baseRevision: baseRevision,
      clientTimestamp: updatedAt.millisecondsSinceEpoch,
      syncState: 'PENDING',
      attempts: 0,
    );
  }

  /// Müşteri varlığını sunucunun Sync V4 / Protocol 6 `customer` mutasyonuna dönüştürür.
  static SyncMutation buildCustomerMutation({
    required String customerId,
    required String name,
    String? phone,
    String? email,
    String? address,
    int balanceCents = 0,
    int creditLimitCents = 0,
    bool isDeleted = false,
    required DateTime updatedAt,
    int baseRevision = 0,
    String? deterministicEventId,
    String operation = 'UPSERT',
  }) {
    final cleanId = customerId.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('Müşteri kimliği (id) boş olamaz.');
    }
    final cleanName = name.trim();
    if (operation == 'UPSERT' && cleanName.isEmpty) {
      throw ArgumentError('Müşteri adı (name) boş olamaz (invalid_mutation).');
    }

    final creditLimitLira = centsIntToLira(creditLimitCents);
    final cleanAddress = address?.trim();

    final payload = <String, dynamic>{
      'id': cleanId,
      'name': cleanName,
      'phone': (phone != null && phone.trim().isNotEmpty) ? phone.trim() : null,
      'email': (email != null && email.trim().isNotEmpty) ? email.trim() : null,
      'address': cleanAddress,
      'notes': cleanAddress, // İstemci geriye dönük uyumluluğu
      'credit_limit': creditLimitLira,
      'credit_limit_cents': creditLimitCents,
      'balance_cents': balanceCents,
      'status': isDeleted ? 'inactive' : 'active',
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': updatedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };

    return SyncMutation(
      eventId: deterministicEventId ?? _uuid.v4(),
      entityType: 'customer',
      entityId: cleanId,
      operation: operation,
      payload: payload,
      baseRevision: baseRevision,
      clientTimestamp: updatedAt.millisecondsSinceEpoch,
      syncState: 'PENDING',
      attempts: 0,
    );
  }

  /// Desteklenmeyen veya yasaklı operasyonları doğrular ve reddeder.
  static void validateOperation(String entityType, String operation) {
    final lowerEntity = entityType.toLowerCase();
    if (lowerEntity == 'sale' && operation.toUpperCase() == 'DELETE') {
      throw UnsupportedError('Satış kayıtları silinemez (immutable_sale).');
    }
    if (lowerEntity == 'refund') {
      throw UnsupportedError(
        'İade mutasyonu sunucu tarafında actor_id ve ek yetkilendirme gerektirir (refund_actor_required).',
      );
    }
    if (!const {'product', 'customer', 'order', 'sale', 'financial_transaction', 'refund'}.contains(lowerEntity)) {
      throw ArgumentError('Desteklenmeyen entity türü: $entityType');
    }
    if (operation.toUpperCase() != 'UPSERT' && operation.toUpperCase() != 'DELETE') {
      throw ArgumentError('Desteklenmeyen operasyon: $operation');
    }
  }
}
