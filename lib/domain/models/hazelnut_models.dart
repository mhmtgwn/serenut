// lib/domain/models/hazelnut_models.dart

class WarehouseEntity {
  final String id;
  final String? companyId;
  final String name;
  final String? location;
  final double capacityKg;
  final double currentStockKg;
  final double averageRendiment;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  WarehouseEntity({
    required this.id,
    this.companyId,
    required this.name,
    this.location,
    this.capacityKg = 0.0,
    this.currentStockKg = 0.0,
    this.averageRendiment = 50.0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  WarehouseEntity copyWith({
    String? id,
    String? companyId,
    String? name,
    String? location,
    double? capacityKg,
    double? currentStockKg,
    double? averageRendiment,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WarehouseEntity(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      location: location ?? this.location,
      capacityKg: capacityKg ?? this.capacityKg,
      currentStockKg: currentStockKg ?? this.currentStockKg,
      averageRendiment: averageRendiment ?? this.averageRendiment,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'name': name,
      'location': location,
      'capacity_kg': capacityKg,
      'current_stock_kg': currentStockKg,
      'average_rendiment': averageRendiment,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory WarehouseEntity.fromMap(Map<String, dynamic> map) {
    return WarehouseEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String?,
      name: map['name'] as String? ?? 'Depo',
      location: map['location'] as String?,
      capacityKg: (map['capacity_kg'] as num?)?.toDouble() ?? 0.0,
      currentStockKg: (map['current_stock_kg'] as num?)?.toDouble() ?? 0.0,
      averageRendiment: (map['average_rendiment'] as num?)?.toDouble() ?? 50.0,
      isActive: (map['is_active'] as num?)?.toInt() != 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class CustomerHazelnutEscrowEntity {
  final String id;
  final String? companyId;
  final String customerId;
  final String warehouseId;
  final String? warehouseName;
  final String? receiptNo;
  final double grossKg;
  final int sackCount;
  final double tareKg;
  final double netKg;
  final double rendiment;
  final double remainingKg;
  final String status; // 'active', 'partially_cut', 'closed'
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerHazelnutEscrowEntity({
    required this.id,
    this.companyId,
    required this.customerId,
    required this.warehouseId,
    this.warehouseName,
    this.receiptNo,
    required this.grossKg,
    this.sackCount = 0,
    this.tareKg = 0.0,
    required this.netKg,
    this.rendiment = 50.0,
    required this.remainingKg,
    this.status = 'active',
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  CustomerHazelnutEscrowEntity copyWith({
    String? id,
    String? companyId,
    String? customerId,
    String? warehouseId,
    String? warehouseName,
    String? receiptNo,
    double? grossKg,
    int? sackCount,
    double? tareKg,
    double? netKg,
    double? rendiment,
    double? remainingKg,
    String? status,
    String? notes,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerHazelnutEscrowEntity(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      customerId: customerId ?? this.customerId,
      warehouseId: warehouseId ?? this.warehouseId,
      warehouseName: warehouseName ?? this.warehouseName,
      receiptNo: receiptNo ?? this.receiptNo,
      grossKg: grossKg ?? this.grossKg,
      sackCount: sackCount ?? this.sackCount,
      tareKg: tareKg ?? this.tareKg,
      netKg: netKg ?? this.netKg,
      rendiment: rendiment ?? this.rendiment,
      remainingKg: remainingKg ?? this.remainingKg,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'customer_id': customerId,
      'warehouse_id': warehouseId,
      'receipt_no': receiptNo,
      'gross_kg': grossKg,
      'sack_count': sackCount,
      'tare_kg': tareKg,
      'net_kg': netKg,
      'rendiment': rendiment,
      'remaining_kg': remainingKg,
      'status': status,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CustomerHazelnutEscrowEntity.fromMap(Map<String, dynamic> map) {
    return CustomerHazelnutEscrowEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String?,
      customerId: map['customer_id'] as String,
      warehouseId: map['warehouse_id'] as String,
      warehouseName: map['warehouse_name'] as String?,
      receiptNo: map['receipt_no'] as String?,
      grossKg: (map['gross_kg'] as num?)?.toDouble() ?? 0.0,
      sackCount: (map['sack_count'] as num?)?.toInt() ?? 0,
      tareKg: (map['tare_kg'] as num?)?.toDouble() ?? 0.0,
      netKg: (map['net_kg'] as num?)?.toDouble() ?? 0.0,
      rendiment: (map['rendiment'] as num?)?.toDouble() ?? 50.0,
      remainingKg: (map['remaining_kg'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'active',
      notes: map['notes'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class WarehouseHazelnutMovementEntity {
  final String id;
  final String? companyId;
  final String warehouseId;
  final String movementType; // 'ESCROW_IN', 'PURCHASE_IN', 'SALE_OUT', 'TRANSFER_IN', 'TRANSFER_OUT', 'RETURN_OUT'
  final double quantityKg;
  final double rendiment;
  final double balanceKgAfter;
  final double averageRendimentAfter;
  final String? referenceId;
  final String? description;
  final String? createdBy;
  final DateTime createdAt;

  WarehouseHazelnutMovementEntity({
    required this.id,
    this.companyId,
    required this.warehouseId,
    required this.movementType,
    required this.quantityKg,
    this.rendiment = 50.0,
    required this.balanceKgAfter,
    required this.averageRendimentAfter,
    this.referenceId,
    this.description,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'warehouse_id': warehouseId,
      'movement_type': movementType,
      'quantity_kg': quantityKg,
      'rendiment': rendiment,
      'balance_kg_after': balanceKgAfter,
      'average_rendiment_after': averageRendimentAfter,
      'reference_id': referenceId,
      'description': description,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory WarehouseHazelnutMovementEntity.fromMap(Map<String, dynamic> map) {
    return WarehouseHazelnutMovementEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String?,
      warehouseId: map['warehouse_id'] as String,
      movementType: map['movement_type'] as String? ?? 'ESCROW_IN',
      quantityKg: (map['quantity_kg'] as num?)?.toDouble() ?? 0.0,
      rendiment: (map['rendiment'] as num?)?.toDouble() ?? 50.0,
      balanceKgAfter: (map['balance_kg_after'] as num?)?.toDouble() ?? 0.0,
      averageRendimentAfter: (map['average_rendiment_after'] as num?)?.toDouble() ?? 50.0,
      referenceId: map['reference_id'] as String?,
      description: map['description'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class HazelnutPriceCutEntity {
  final String id;
  final String? companyId;
  final String escrowId;
  final String customerId;
  final String? customerName;
  final double cutKg;
  final double rendiment;
  final double basePrice50;
  final double effectivePrice;
  final double totalAmount;
  final String settlementType; // 'CASH_PAID', 'OFFSET_DEBT', 'ACCOUNT_CREDIT'
  final String? financialTransactionId;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;

  HazelnutPriceCutEntity({
    required this.id,
    this.companyId,
    required this.escrowId,
    required this.customerId,
    this.customerName,
    required this.cutKg,
    required this.rendiment,
    required this.basePrice50,
    required this.effectivePrice,
    required this.totalAmount,
    this.settlementType = 'ACCOUNT_CREDIT',
    this.financialTransactionId,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'escrow_id': escrowId,
      'customer_id': customerId,
      'cut_kg': cutKg,
      'rendiment': rendiment,
      'base_price_50': basePrice50,
      'effective_price': effectivePrice,
      'total_amount': totalAmount,
      'settlement_type': settlementType,
      'financial_transaction_id': financialTransactionId,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory HazelnutPriceCutEntity.fromMap(Map<String, dynamic> map) {
    return HazelnutPriceCutEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String?,
      escrowId: map['escrow_id'] as String,
      customerId: map['customer_id'] as String,
      customerName: map['customer_name'] as String?,
      cutKg: (map['cut_kg'] as num?)?.toDouble() ?? 0.0,
      rendiment: (map['rendiment'] as num?)?.toDouble() ?? 50.0,
      basePrice50: (map['base_price_50'] as num?)?.toDouble() ?? 0.0,
      effectivePrice: (map['effective_price'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      settlementType: map['settlement_type'] as String? ?? 'ACCOUNT_CREDIT',
      financialTransactionId: map['financial_transaction_id'] as String?,
      notes: map['notes'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

