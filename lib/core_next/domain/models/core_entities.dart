// core_next/client_core/lib/domain/models/core_entities.dart
import 'money_cents.dart';

DateTime _parseDate(dynamic val) {
  if (val == null) return DateTime.now();
  if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
  if (val is String) {
    final asInt = int.tryParse(val);
    if (asInt != null && asInt > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(asInt);
    }
    return DateTime.tryParse(val) ?? DateTime.now();
  }
  return DateTime.now();
}

enum ProductUnit { piece, kg, gram, packet, liter }

class ProductEntity {
  final String id;
  final String barcode;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final MoneyCents price;
  final MoneyCents? costPrice;
  final int vatRate;
  final ProductUnit unit;
  final int stockQuantity;
  final int criticalStockThreshold;
  final String? imageUrl;
  final bool isActive;
  final bool isDeleted;
  final DateTime updatedAt;

  const ProductEntity({
    required this.id,
    required this.barcode,
    required this.name,
    this.categoryId,
    this.categoryName,
    required this.price,
    this.costPrice,
    this.vatRate = 20,
    this.unit = ProductUnit.piece,
    this.stockQuantity = 0,
    this.criticalStockThreshold = 5,
    this.imageUrl,
    this.isActive = true,
    this.isDeleted = false,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'barcode': barcode,
        'name': name,
        'category_id': categoryId,
        'price_cents': price.value,
        'cost_price_cents': costPrice?.value,
        'vat_rate': vatRate,
        'unit': unit.name,
        'stock_quantity': stockQuantity,
        'critical_threshold': criticalStockThreshold,
        'image_url': imageUrl,
        'is_active': isActive ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ProductEntity.fromMap(Map<String, dynamic> map) => ProductEntity(
        id: map['id'] as String,
        barcode: map['barcode'] as String,
        name: map['name'] as String,
        categoryId: map['category_id'] as String?,
        categoryName: map['category_name'] as String?,
        price: MoneyCents((map['price_cents'] as num).toInt()),
        costPrice: map['cost_price_cents'] != null
            ? MoneyCents((map['cost_price_cents'] as num).toInt())
            : null,
        vatRate: (map['vat_rate'] as num?)?.toInt() ?? 20,
        unit: ProductUnit.values.byName(map['unit'] as String? ?? 'piece'),
        stockQuantity: (map['stock_quantity'] as num?)?.toInt() ?? 0,
        criticalStockThreshold: (map['critical_threshold'] as num?)?.toInt() ?? 5,
        imageUrl: map['image_url'] as String?,
        isActive: (map['is_active'] as int? ?? 1) == 1,
        isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
        updatedAt: _parseDate(map['updated_at']),
      );
}

class CustomerEntity {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? taxNumber;
  final String? taxOffice;
  final MoneyCents balance;
  final MoneyCents creditLimit;
  final String? notes;
  final bool isActive;
  final bool isDeleted;
  final DateTime updatedAt;

  const CustomerEntity({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.taxNumber,
    this.taxOffice,
    required this.balance,
    this.creditLimit = MoneyCents.zero,
    this.notes,
    this.isActive = true,
    this.isDeleted = false,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'tax_number': taxNumber,
        'tax_office': taxOffice,
        'balance_cents': balance.value,
        'credit_limit_cents': creditLimit.value,
        'notes': notes,
        'is_active': isActive ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory CustomerEntity.fromMap(Map<String, dynamic> map) => CustomerEntity(
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        taxNumber: map['tax_number'] as String?,
        taxOffice: map['tax_office'] as String?,
        balance: MoneyCents((map['balance_cents'] as num).toInt()),
        creditLimit: MoneyCents((map['credit_limit_cents'] as num?)?.toInt() ?? 0),
        notes: map['notes'] as String?,
        isActive: (map['is_active'] as int? ?? 1) == 1,
        isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
        updatedAt: _parseDate(map['updated_at']),
      );
}

enum LedgerEntryType {
  debitSale,         // Müşterinin vadeli alışveriş borcu (- bakiye)
  creditCollection,  // Müşteriden nakit/kart tahsilat (+ bakiye)
  creditRefund,      // İade sonucu müşteriye alacak kaydı (+ bakiye)
  debitAdjustment,   // Borç düzeltme
  creditAdjustment,  // Alacak düzeltme
}

class LedgerEntryEntity {
  final String id;
  final String customerId;
  final String? referenceSaleId;
  final LedgerEntryType entryType;
  final MoneyCents amount;
  final MoneyCents balanceAfter;
  final String description;
  final DateTime createdAt;

  const LedgerEntryEntity({
    required this.id,
    required this.customerId,
    this.referenceSaleId,
    required this.entryType,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'reference_sale_id': referenceSaleId,
        'entry_type': entryType.name,
        'amount_cents': amount.value,
        'balance_after_cents': balanceAfter.value,
        'description': description,
        'created_at': createdAt.toIso8601String(),
      };

  factory LedgerEntryEntity.fromMap(Map<String, dynamic> map) =>
      LedgerEntryEntity(
        id: map['id'] as String,
        customerId: map['customer_id'] as String,
        referenceSaleId: map['reference_sale_id'] as String?,
        entryType: LedgerEntryType.values.byName(map['entry_type'] as String),
        amount: MoneyCents((map['amount_cents'] as num).toInt()),
        balanceAfter: MoneyCents((map['balance_after_cents'] as num).toInt()),
        description: map['description'] as String,
        createdAt: _parseDate(map['created_at']),
      );
}

enum PaymentType { cash, creditCard, onAccount, bankTransfer, mixed }

class PaymentSplitEntity {
  final PaymentType type;
  final MoneyCents amount;
  final String? referenceNote;

  const PaymentSplitEntity({
    required this.type,
    required this.amount,
    this.referenceNote,
  });

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'amount_cents': amount.value,
        'reference_note': referenceNote,
      };

  factory PaymentSplitEntity.fromMap(Map<String, dynamic> map) =>
      PaymentSplitEntity(
        type: PaymentType.values.byName(map['type'] as String),
        amount: MoneyCents(map['amount_cents'] as int),
        referenceNote: map['reference_note'] as String?,
      );
}

class SaleOrderItemEntity {
  final String id;
  final String saleId;
  final String productId;
  final String barcode;
  final String productName;
  final MoneyCents unitPrice;
  final int quantity;
  final MoneyCents discount;
  final int vatRate;
  final MoneyCents total;

  const SaleOrderItemEntity({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.discount = MoneyCents.zero,
    required this.vatRate,
    required this.total,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'barcode': barcode,
        'product_name': productName,
        'unit_price_cents': unitPrice.value,
        'quantity': quantity,
        'discount_cents': discount.value,
        'vat_rate': vatRate,
        'total_cents': total.value,
      };

  factory SaleOrderItemEntity.fromMap(Map<String, dynamic> map) =>
      SaleOrderItemEntity(
        id: map['id'] as String,
        saleId: map['sale_id'] as String? ?? '',
        productId: map['product_id'] as String,
        barcode: map['barcode'] as String,
        productName: map['product_name'] as String,
        unitPrice: MoneyCents((map['unit_price_cents'] as num).toInt()),
        quantity: (map['quantity'] as num).toInt(),
        discount: MoneyCents((map['discount_cents'] as num?)?.toInt() ?? 0),
        vatRate: (map['vat_rate'] as num?)?.toInt() ?? 20,
        total: MoneyCents((map['total_cents'] as num).toInt()),
      );
}

class SaleOrderEntity {
  final String id;
  final String receiptNo;
  final String? customerId;
  final MoneyCents subtotal;
  final MoneyCents discount;
  final MoneyCents vatTotal;
  final MoneyCents total;
  final MoneyCents paid;
  final MoneyCents debt;
  final List<SaleOrderItemEntity> items;
  final List<PaymentSplitEntity> payments;
  final bool isCancelled;
  final String? cancellationReason;
  final DateTime createdAt;

  const SaleOrderEntity({
    required this.id,
    required this.receiptNo,
    this.customerId,
    required this.subtotal,
    this.discount = MoneyCents.zero,
    this.vatTotal = MoneyCents.zero,
    required this.total,
    required this.paid,
    required this.debt,
    required this.items,
    required this.payments,
    this.isCancelled = false,
    this.cancellationReason,
    required this.createdAt,
  });
}
