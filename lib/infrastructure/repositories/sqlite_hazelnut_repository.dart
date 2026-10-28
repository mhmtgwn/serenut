// lib/infrastructure/repositories/sqlite_hazelnut_repository.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/domain/services/hazelnut_calculator.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

abstract class IHazelnutRepository {
  Future<List<WarehouseEntity>> getWarehouses();
  Future<WarehouseEntity?> getWarehouseById(String id);
  Future<void> saveWarehouse(WarehouseEntity warehouse);
  Future<List<WarehouseHazelnutMovementEntity>> getWarehouseMovements(String warehouseId);
  Future<List<CustomerHazelnutEscrowEntity>> getCustomerEscrows(String customerId);
  Future<CustomerHazelnutEscrowEntity?> getEscrowById(String id);
  Future<List<CustomerHazelnutEscrowEntity>> getAllActiveEscrows();
  Future<CustomerHazelnutEscrowEntity> addEscrowBatch({
    required String customerId,
    required String warehouseId,
    String? receiptNo,
    required double grossKg,
    int sackCount = 0,
    double tarePerSack = 1.0,
    double manualTareKg = 0.0,
    required double rendiment,
    String? notes,
    String? createdBy,
  });
  Future<HazelnutPriceCutEntity> cutEscrowPrice({
    required String escrowId,
    required double cutKg,
    required double basePrice50,
    required String settlementType, // 'CASH_PAID', 'OFFSET_DEBT', 'ACCOUNT_CREDIT'
    String? customerName,
    String? notes,
    String? createdBy,
  });
  Future<WarehouseHazelnutMovementEntity> dispatchFromWarehouse({
    required String warehouseId,
    required String movementType,
    required double quantityKg,
    String? description,
    String? referenceId,
    String? createdBy,
  });
}

class SqliteHazelnutRepository implements IHazelnutRepository {
  final DbGateway _gateway;
  static const _uuid = Uuid();

  SqliteHazelnutRepository(this._gateway);

  @override
  Future<List<WarehouseEntity>> getWarehouses() async {
    final rows = await _gateway.query(
      'warehouses',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
    return rows.map((r) => WarehouseEntity.fromMap(r)).toList();
  }

  @override
  Future<WarehouseEntity?> getWarehouseById(String id) async {
    final rows = await _gateway.query(
      'warehouses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WarehouseEntity.fromMap(rows.first);
  }

  @override
  Future<void> saveWarehouse(WarehouseEntity warehouse) async {
    await _gateway.insert(
      'warehouses',
      warehouse.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await SyncOutboxV4.enqueue(
        _gateway,
        entityType: 'warehouse',
        entityId: warehouse.id,
        operation: 'UPSERT',
        payload: warehouse.toMap(),
      );
    } catch (e) {
      debugPrint('[HazelnutRepo] Outbox enqueue skipped: $e');
    }
  }

  @override
  Future<List<WarehouseHazelnutMovementEntity>> getWarehouseMovements(String warehouseId) async {
    final rows = await _gateway.query(
      'warehouse_hazelnut_movements',
      where: 'warehouse_id = ?',
      whereArgs: [warehouseId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => WarehouseHazelnutMovementEntity.fromMap(r)).toList();
  }

  @override
  Future<List<CustomerHazelnutEscrowEntity>> getCustomerEscrows(String customerId) async {
    final rows = await _gateway.rawQuery('''
      SELECT e.*, w.name AS warehouse_name
      FROM customer_hazelnut_escrow e
      LEFT JOIN warehouses w ON e.warehouse_id = w.id
      WHERE e.customer_id = ?
      ORDER BY e.created_at DESC
    ''', [customerId]);
    return rows.map((r) => CustomerHazelnutEscrowEntity.fromMap(r)).toList();
  }

  @override
  Future<CustomerHazelnutEscrowEntity?> getEscrowById(String id) async {
    final rows = await _gateway.rawQuery('''
      SELECT e.*, w.name AS warehouse_name
      FROM customer_hazelnut_escrow e
      LEFT JOIN warehouses w ON e.warehouse_id = w.id
      WHERE e.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return CustomerHazelnutEscrowEntity.fromMap(rows.first);
  }

  @override
  Future<List<CustomerHazelnutEscrowEntity>> getAllActiveEscrows() async {
    final rows = await _gateway.rawQuery('''
      SELECT e.*, w.name AS warehouse_name
      FROM customer_hazelnut_escrow e
      LEFT JOIN warehouses w ON e.warehouse_id = w.id
      WHERE e.remaining_kg > 0
      ORDER BY e.created_at DESC
    ''');
    return rows.map((r) => CustomerHazelnutEscrowEntity.fromMap(r)).toList();
  }

  @override
  Future<CustomerHazelnutEscrowEntity> addEscrowBatch({
    required String customerId,
    required String warehouseId,
    String? receiptNo,
    required double grossKg,
    int sackCount = 0,
    double tarePerSack = 1.0,
    double manualTareKg = 0.0,
    required double rendiment,
    String? notes,
    String? createdBy,
  }) async {
    return await _gateway.transaction(() async {
      final effectiveTare = manualTareKg > 0 ? manualTareKg : (sackCount * tarePerSack);
      final netKg = HazelnutCalculator.calculateNetKg(
        grossKg: grossKg,
        sackCount: sackCount,
        tarePerSack: tarePerSack,
        manualTareKg: manualTareKg,
      );

      if (netKg <= 0) {
        throw ArgumentError('Net kilo sıfırdan büyük olmalıdır (Brüt: $grossKg, Dara: $effectiveTare).');
      }

      final wh = await getWarehouseById(warehouseId);
      if (wh == null) {
        throw StateError('Belirtilen depo bulunamadı (ID: $warehouseId).');
      }

      final newAvgRendiment = HazelnutCalculator.calculateWeightedAverageRendiment(
        currentStockKg: wh.currentStockKg,
        currentAverageRendiment: wh.averageRendiment,
        incomingKg: netKg,
        incomingRendiment: rendiment,
      );
      final newWarehouseStock = wh.currentStockKg + netKg;
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // 1. Depo stok ve randımanını güncelle
      await _gateway.update(
        'warehouses',
        {
          'current_stock_kg': newWarehouseStock,
          'average_rendiment': newAvgRendiment,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [warehouseId],
      );

      final escrowId = _uuid.v4();
      final generatedReceiptNo = receiptNo != null && receiptNo.trim().isNotEmpty
          ? receiptNo.trim()
          : 'EM-${now.millisecondsSinceEpoch.toString().substring(5)}';

      final escrow = CustomerHazelnutEscrowEntity(
        id: escrowId,
        customerId: customerId,
        warehouseId: warehouseId,
        warehouseName: wh.name,
        receiptNo: generatedReceiptNo,
        grossKg: grossKg,
        sackCount: sackCount,
        tareKg: effectiveTare,
        netKg: netKg,
        rendiment: rendiment,
        remainingKg: netKg,
        status: 'active',
        notes: notes,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
      );

      // 2. Müşteri emanet tablosuna ekle
      await _gateway.insert('customer_hazelnut_escrow', escrow.toMap());

      // 3. Depo hareket kaydı (ESCROW_IN)
      final movementId = _uuid.v4();
      final movement = WarehouseHazelnutMovementEntity(
        id: movementId,
        warehouseId: warehouseId,
        movementType: 'ESCROW_IN',
        quantityKg: netKg,
        rendiment: rendiment,
        balanceKgAfter: newWarehouseStock,
        averageRendimentAfter: newAvgRendiment,
        referenceId: escrowId,
        description: 'Müşteri Emanet Girişi ($generatedReceiptNo) - $sackCount Çuval',
        createdBy: createdBy,
        createdAt: now,
      );
      await _gateway.insert('warehouse_hazelnut_movements', movement.toMap());

      try {
        await SyncOutboxV4.enqueue(
          _gateway,
          entityType: 'warehouse',
          entityId: warehouseId,
          operation: 'UPSERT',
          payload: {
            'id': warehouseId,
            'name': wh.name,
            'location': wh.location,
            'capacity_kg': wh.capacityKg,
            'current_stock_kg': newWarehouseStock,
            'average_rendiment': newAvgRendiment,
            'is_active': wh.isActive ? 1 : 0,
            'updated_at': nowIso,
          },
        );
        await SyncOutboxV4.enqueue(
          _gateway,
          entityType: 'customer_hazelnut_escrow',
          entityId: escrowId,
          operation: 'UPSERT',
          payload: escrow.toMap(),
        );
        await SyncOutboxV4.enqueue(
          _gateway,
          entityType: 'warehouse_hazelnut_movement',
          entityId: movementId,
          operation: 'UPSERT',
          payload: movement.toMap(),
        );
      } catch (e) {
        debugPrint('[HazelnutRepo] Outbox enqueue skipped: $e');
      }

      return escrow;
    });
  }

  @override
  Future<HazelnutPriceCutEntity> cutEscrowPrice({
    required String escrowId,
    required double cutKg,
    required double basePrice50,
    required String settlementType,
    String? customerName,
    String? notes,
    String? createdBy,
  }) async {
    return await _gateway.transaction(() async {
      final escrow = await getEscrowById(escrowId);
      if (escrow == null) {
        throw StateError('Emanet partisi bulunamadı (ID: $escrowId).');
      }

      if (cutKg <= 0) {
        throw ArgumentError('Fiyat kesilecek miktar sıfırdan büyük olmalıdır.');
      }

      if (cutKg > escrow.remainingKg + 0.001) {
        throw ArgumentError('Kesilmek istenen miktar (${cutKg.toStringAsFixed(1)} kg) kalan emanetten (${escrow.remainingKg.toStringAsFixed(1)} kg) fazla olamaz.');
      }

      final effectiveUnitPrice = HazelnutCalculator.calculateEffectiveUnitPrice(
        basePrice50: basePrice50,
        rendiment: escrow.rendiment,
      );
      final totalAmount = HazelnutCalculator.calculateTotalAmount(
        cutKg: cutKg,
        effectiveUnitPrice: effectiveUnitPrice,
      );

      final newRemaining = escrow.remainingKg - cutKg;
      final newStatus = newRemaining <= 0.01 ? 'closed' : 'partially_cut';
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // 1. Emanet partisini güncelle
      await _gateway.update(
        'customer_hazelnut_escrow',
        {
          'remaining_kg': newRemaining > 0.01 ? newRemaining : 0.0,
          'status': newStatus,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [escrowId],
      );

      final cutId = _uuid.v4();
      String? finTxId;

      // 2. Finansal entegrasyon
      if (settlementType == 'OFFSET_DEBT' || settlementType == 'ACCOUNT_CREDIT') {
        finTxId = _uuid.v4();
        final clockResult = await _gateway.rawQuery(
          'SELECT MAX(logical_clock) as max_clock FROM financial_transactions',
        );
        final maxClock = Sqflite.firstIntValue(clockResult) ?? 0;
        final nextClock = maxClock + 1;
        final amountMinor = (totalAmount * 100).round();

        final label = settlementType == 'OFFSET_DEBT' ? 'Borca Mahsup' : 'Cariye Alacak';
        final txPayload = <String, dynamic>{
          'id': finTxId,
          'customer_id': escrow.customerId,
          'type': 'payment', // 'payment' increases balance in ledger trigger
          'amount': totalAmount,
          'amount_minor': amountMinor,
          'paid_amount': totalAmount,
          'paid_amount_minor': amountMinor,
          'debt_amount': 0.0,
          'debt_amount_minor': 0,
          'payment_method': 'other',
          'reference_id': cutId,
          'description': 'Fındık Fiyat Kesimi ($label) - ${cutKg.toStringAsFixed(1)} kg (${escrow.rendiment} Randıman)',
          'metadata': jsonEncode({
            'source': 'hazelnut_price_cut',
            'escrow_id': escrowId,
            'cut_kg': cutKg,
            'rendiment': escrow.rendiment,
            'base_price_50': basePrice50,
            'effective_price': effectiveUnitPrice,
            'settlement_type': settlementType,
          }),
          'created_at': nowIso,
          'logical_clock': nextClock,
          'device_id': 'local-device',
          'is_synced': 0,
        };
        await _gateway.insert('financial_transactions', txPayload);
        try {
          await SyncOutboxV4.enqueue(
            _gateway,
            entityType: 'financial_transaction',
            entityId: finTxId,
            operation: 'UPSERT',
            payload: txPayload,
          );
        } catch (_) {
          // SyncOutboxV4 table not present in mock/isolated test environment
        }
      } else if (settlementType == 'CASH_PAID') {
        // Kasadan Nakit Ödeme: Gider / Kasa çıkışı olarak kaydet
        final expenseId = _uuid.v4();
        final expensePayload = {
          'id': expenseId,
          'amount': totalAmount,
          'category': 'Fındık Alımı',
          'description': 'Fındık Fiyat Kesimi Nakit Ödeme - ${customerName ?? 'Müşteri'} (${cutKg.toStringAsFixed(1)} kg, ${escrow.rendiment} R)',
          'created_at': nowIso,
          'is_deleted': 0,
        };
        await _gateway.insert('cash_expenses', expensePayload);
        try {
          await SyncOutboxV4.enqueue(
            _gateway,
            entityType: 'cash_expense',
            entityId: expenseId,
            operation: 'UPSERT',
            payload: expensePayload,
          );
        } catch (_) {
          // SyncOutboxV4 table not present in mock/isolated test environment
        }
      }

      // 3. Fiyat kesim bordrosu kaydı
      final priceCut = HazelnutPriceCutEntity(
        id: cutId,
        escrowId: escrowId,
        customerId: escrow.customerId,
        customerName: customerName,
        cutKg: cutKg,
        rendiment: escrow.rendiment,
        basePrice50: basePrice50,
        effectivePrice: effectiveUnitPrice,
        totalAmount: totalAmount,
        settlementType: settlementType,
        financialTransactionId: finTxId,
        notes: notes,
        createdBy: createdBy,
        createdAt: now,
      );
      await _gateway.insert('hazelnut_price_cuts', priceCut.toMap());

      try {
        await SyncOutboxV4.enqueue(
          _gateway,
          entityType: 'customer_hazelnut_escrow',
          entityId: escrowId,
          operation: 'UPSERT',
          payload: {
            'id': escrowId,
            'customer_id': escrow.customerId,
            'warehouse_id': escrow.warehouseId,
            'remaining_kg': newRemaining > 0.01 ? newRemaining : 0.0,
            'status': newStatus,
            'updated_at': nowIso,
          },
        );
        await SyncOutboxV4.enqueue(
          _gateway,
          entityType: 'hazelnut_price_cut',
          entityId: cutId,
          operation: 'UPSERT',
          payload: priceCut.toMap(),
        );
      } catch (e) {
        debugPrint('[HazelnutRepo] Outbox enqueue skipped: $e');
      }

      return priceCut;
    });
  }

  @override
  Future<WarehouseHazelnutMovementEntity> dispatchFromWarehouse({
    required String warehouseId,
    required String movementType,
    required double quantityKg,
    String? description,
    String? referenceId,
    String? createdBy,
  }) async {
    return await _gateway.transaction(() async {
      final wh = await getWarehouseById(warehouseId);
      if (wh == null) {
        throw StateError('Depo bulunamadı (ID: $warehouseId).');
      }

      if (quantityKg <= 0) {
        throw ArgumentError('Çıkış miktarı sıfırdan büyük olmalıdır.');
      }

      if (quantityKg > wh.currentStockKg) {
        throw ArgumentError('Çıkış miktarı (${quantityKg.toStringAsFixed(1)} kg) depodaki mevcut stoktan (${wh.currentStockKg.toStringAsFixed(1)} kg) fazla olamaz.');
      }

      final newStock = wh.currentStockKg - quantityKg;
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // Depo stoğunu düş (çıkışta ortalama randıman değişmez)
      await _gateway.update(
        'warehouses',
        {
          'current_stock_kg': newStock,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [warehouseId],
      );

      final movementId = _uuid.v4();
      final movement = WarehouseHazelnutMovementEntity(
        id: movementId,
        warehouseId: warehouseId,
        movementType: movementType,
        quantityKg: quantityKg,
        rendiment: wh.averageRendiment,
        balanceKgAfter: newStock,
        averageRendimentAfter: wh.averageRendiment,
        referenceId: referenceId,
        description: description,
        createdBy: createdBy,
        createdAt: now,
      );
      await _gateway.insert('warehouse_hazelnut_movements', movement.toMap());

      try {
        await SyncOutboxV4.enqueue(
          _gateway,
          entityType: 'warehouse',
          entityId: warehouseId,
          operation: 'UPSERT',
          payload: {
            'id': warehouseId,
            'current_stock_kg': newStock,
            'updated_at': nowIso,
          },
        );
        await SyncOutboxV4.enqueue(
          _gateway,
          entityType: 'warehouse_hazelnut_movement',
          entityId: movementId,
          operation: 'UPSERT',
          payload: movement.toMap(),
        );
      } catch (e) {
        debugPrint('[HazelnutRepo] Outbox enqueue skipped: $e');
      }

      return movement;
    });
  }
}

