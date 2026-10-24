// core_next/client_core/lib/domain/usecases/checkout_use_case.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/hardware/hardware_commands.dart';
import '../../infrastructure/hardware/hardware_worker.dart';
import '../models/core_entities.dart';
import '../models/money_cents.dart';
import '../models/rbac_models.dart';
import '../services/ledger_service.dart';
import '../../infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../infrastructure/sync/sync_v4_payload_adapter.dart';
import '../../presentation/sales/core_sales_flow_state.dart';

typedef CheckoutFaultHook = Future<void> Function(String stepName);

class CheckoutRequest {
  final CoreSalesFlowState flowState;
  final String receiptNo;
  final String storeTitle;
  final String? storeAddress;
  final String? storePhone;
  final bool autoPrintReceipt;
  final bool openCashDrawer;
  final String? idempotencyKey;
  final ActorContext? actor;

  const CheckoutRequest({
    required this.flowState,
    required this.receiptNo,
    required this.storeTitle,
    this.storeAddress,
    this.storePhone,
    this.autoPrintReceipt = true,
    this.openCashDrawer = false,
    this.idempotencyKey,
    this.actor,
  });
}

/// Kasa Satış ve Ödeme Use-Case (Tek Atomik İşlem)
class CoreCheckoutUseCase {
  final CoreAppDatabase _db;
  final HardwareWorker _hardwareWorker;
  final CheckoutFaultHook? _faultHook;
  final ActorContext? _defaultActor;
  final Uuid _uuid = const Uuid();

  CoreCheckoutUseCase({
    required CoreAppDatabase db,
    required HardwareWorker hardwareWorker,
    LedgerService? ledgerService,
    CheckoutFaultHook? faultHook,
    ActorContext? defaultActor,
  })  : _db = db,
        _hardwareWorker = hardwareWorker,
        _faultHook = faultHook,
        _defaultActor = defaultActor;

  Future<SaleOrderEntity> execute(CheckoutRequest request) async {
    final state = request.flowState;
    if (state.isEmpty) {
      throw StateError('Sepet boş; satış yapılamaz.');
    }

    // RBAC Güvenlik Denetimi: İşlem yetkisi domain seviyesinde denetlenir (Fail-Secure)
    final actor = request.actor ?? _defaultActor;
    if (actor == null) {
      throw const AuthenticationRequiredException('İşlem yapan kullanıcı/aktör kimliği zorunludur.');
    }
    if (actor.isSystem) {
      throw const AuthorizationException(
        'Sistem arka plan kimliği (system actor) ile doğrudan satış yapılamaz. Satış işlemi yetkili bir kullanıcı tarafından yürütülmelidir.',
        requiredPermission: AppPermission.createSale,
        userRole: AppRole.sysadmin,
      );
    }
    actor.requirePermission(AppPermission.createSale, 'Satış oluşturma');
    if (state.generalDiscount.value > 0) {
      actor.requirePermission(AppPermission.applyDiscount, 'İskonto uygulama');
    }
    if (state.debtTotal.value > 0) {
      actor.requirePermission(AppPermission.creditSale, 'Veresiye satış yapma');
    }

    final now = DateTime.now();
    final saleId = _uuid.v4();
    final customer = state.selectedCustomer;
    final totalCents = state.total;
    final paidCents = state.paidTotal;
    final debtCents = state.debtTotal;
    final idempotencyKey = request.idempotencyKey ?? request.receiptNo;

    // Negatif ve sıfır tutar koruması
    if (totalCents.value <= 0) {
      throw StateError('Satış toplamı sıfırdan büyük olmalıdır (${totalCents.formatTL()}).');
    }
    if (paidCents.value < 0 || debtCents.value < 0) {
      throw StateError('Ödeme veya borç tutarı negatif olamaz.');
    }
    if (paidCents.value > totalCents.value) {
      throw StateError(
        'Tahsil edilen tutar (${paidCents.formatTL()}) satış toplamını (${totalCents.formatTL()}) aşamaz.',
      );
    }

    // Eğer veresiye borç kalıyorsa müşteri seçilmiş olmak zorunda
    if (debtCents.value > 0 && customer == null) {
      throw StateError(
        'Kalan ${debtCents.formatTL()} tutarındaki veresiye borç için müşteri seçilmelidir.',
      );
    }

    // İdempotency Ön Kontrolü: Bu fiş/işlem daha önce işlenmiş mi?
    final existingSales = await _db.query(
      'sales',
      where: 'idempotency_key = ? OR receipt_no = ?',
      whereArgs: [idempotencyKey, request.receiptNo],
      limit: 1,
    );
    if (existingSales.isNotEmpty) {
      return await _evaluateExistingSale(
        existing: existingSales.first,
        request: request,
        state: state,
        idempotencyKey: idempotencyKey,
      );
    }

    // Ödeme Parçalarını (Splits) Hazırla ve Doğrula
    final effectiveSplits = <PaymentSplitEntity>[];
    if (state.paymentSplits.isEmpty) {
      if (paidCents.value > 0) {
        effectiveSplits.add(
          PaymentSplitEntity(type: PaymentType.cash, amount: paidCents),
        );
      }
    } else {
      for (final split in state.paymentSplits) {
        if (split.amount.value <= 0) {
          throw StateError('Ödeme parçası tutarı pozitif olmalıdır.');
        }
        effectiveSplits.add(split);
      }
    }

    // Invariant Kontrolü: Nakit/Kart tahsilat toplamı ile paidCents kuruşu kuruşuna uyuşmalı
    final computedPaidCents = effectiveSplits
        .where((s) => s.type != PaymentType.onAccount)
        .fold<int>(0, (sum, s) => sum + s.amount.value);
    if (computedPaidCents != paidCents.value) {
      throw StateError(
        'Ödeme parçaları toplamı ($computedPaidCents kuruş) tahsil edilen tutara (${paidCents.value} kuruş) eşit olmalıdır.',
      );
    }

    // Eğer veresiye borç varsa ve splitlerde açık onAccount yoksa, denge için ekle
    if (debtCents.value > 0 &&
        !effectiveSplits.any((s) => s.type == PaymentType.onAccount)) {
      effectiveSplits.add(
        PaymentSplitEntity(
          type: PaymentType.onAccount,
          amount: debtCents,
          referenceNote: customer?.name,
        ),
      );
    }

    // ── TEK BİR ATOMİK SQLITE TRANSACTION'I ─────────────────────────────────
    final orderItems = <SaleOrderItemEntity>[];
    final receiptItems = <ReceiptLineItem>[];

    try {
      await _db.transaction((txn) async {
        var vatTotalSum = 0;

        // 1. Önce Kalemleri Hazırla, Stok Kontrolü Yap ve KDV'yi Hesapla
        for (final cartItem in state.items) {
          final itemId = _uuid.v4();
          final p = cartItem.product;

          if (!cartItem.isWeighed) {
            final prodRows = await txn.query('products',
                columns: ['stock_quantity'], where: 'id = ?', whereArgs: [p.id]);
            if (prodRows.isNotEmpty) {
              final currentStock =
                  (prodRows.first['stock_quantity'] as num?)?.toInt() ?? 0;
              if (currentStock < cartItem.quantity) {
                throw StateError(
                    'Yetersiz stok: "${p.name}" ürününden stokta $currentStock adet var, ${cartItem.quantity} adet satılamaz.');
              }
            }
          }

          final lineTotal = cartItem.lineTotal;
          final vatCents = lineTotal.percentage(p.vatRate).value;
          vatTotalSum += vatCents;

          final itemEntity = SaleOrderItemEntity(
            id: itemId,
            saleId: saleId,
            productId: p.id,
            barcode: p.barcode,
            productName: p.name,
            unitPrice: cartItem.unitPrice,
            quantity: cartItem.quantity,
            discount: cartItem.discount,
            vatRate: p.vatRate,
            total: lineTotal,
          );
          orderItems.add(itemEntity);

          receiptItems.add(ReceiptLineItem(
            name: p.name,
            quantity: cartItem.quantity,
            unitPriceCents: cartItem.unitPrice.value,
            totalCents: lineTotal.value,
          ));
        }

        // 2. Ana Satış Başlığını Kaydet (Parent)
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': request.receiptNo,
          'customer_id': customer?.id,
          'subtotal_cents': state.subtotal.value,
          'discount_cents': state.generalDiscount.value,
          'vat_total_cents': vatTotalSum,
          'total_cents': totalCents.value,
          'paid_cents': paidCents.value,
          'debt_cents': debtCents.value,
          'status': 'COMPLETED',
          'idempotency_key': idempotencyKey,
          'created_at': now.millisecondsSinceEpoch,
        });

        if (_faultHook != null) await _faultHook!('after_sales_insert');

        // 3. Kalemleri ve Stok Düşümlerini Kaydet (Children)
        for (final itemEntity in orderItems) {
          await txn.insert('sale_items', itemEntity.toMap());
          await txn.rawUpdate(
            'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
            [itemEntity.quantity, now.millisecondsSinceEpoch, itemEntity.productId],
          );
        }

        if (_faultHook != null) await _faultHook!('after_items_insert');

        // 4. Parçalı / Karma Ödemeleri Kalıcı Olarak Kaydet (sale_payments)
        for (final split in effectiveSplits) {
          final paymentId = _uuid.v4();
          await txn.insert('sale_payments', {
            'id': paymentId,
            'sale_id': saleId,
            'payment_type': split.type.name,
            'amount_cents': split.amount.value,
            'reference_note': split.referenceNote,
            'created_at': now.millisecondsSinceEpoch,
          });

          // Nakit tahsilat ise kasa nakit hareketlerine atomik giriş ekle
          if (split.type == PaymentType.cash && split.amount.value > 0) {
            await txn.insert('cash_transactions', {
              'id': _uuid.v4(),
              'type': 'INFLOW',
              'amount_cents': split.amount.value,
              'category': 'SALE',
              'description': 'Fiş No: ${request.receiptNo}',
              'created_at': now.millisecondsSinceEpoch,
            });
          }
        }

        if (_faultHook != null) await _faultHook!('after_payments_insert');

        // 5. Veresiye Varsa Deftere Borç İşle
        if (debtCents.value > 0 && customer != null) {
          final txnLedgerRepo = SqliteLedgerRepository(txn);
          final txnLedgerService = LedgerService(txnLedgerRepo);
          await txnLedgerService.postDebitSale(
            entryId: _uuid.v4(),
            customerId: customer.id,
            saleId: saleId,
            debtAmount: debtCents,
            receiptNo: request.receiptNo,
            timestamp: now,
          );
        }

        if (_faultHook != null) await _faultHook!('after_ledger_insert');

        // 6. Çevrimdışı Senkronizasyon Kuyruğuna Ekle (Sync V4 / Protocol 6 Outbox)
        final saleMutation = SyncV4PayloadAdapter.buildSaleMutation(
          saleId: saleId,
          receiptNo: request.receiptNo,
          customerId: customer?.id,
          orderItems: orderItems,
          subtotal: state.subtotal,
          generalDiscount: state.generalDiscount,
          total: totalCents,
          paid: paidCents,
          debt: debtCents,
          splits: effectiveSplits,
          createdAt: now,
          idempotencyKey: idempotencyKey,
        );
        await txn.insert('sync_events', saleMutation.toDbRow());

        // Eğer müşteri cari borcu varsa, finansal hareket mutasyonunu (financial_transaction) aynı transaction içinde atomik ekle
        if (customer != null && debtCents.value > 0) {
          final finTxMutation = SyncV4PayloadAdapter.buildFinancialTransactionMutation(
            saleId: saleId,
            customerId: customer.id,
            total: totalCents,
            paid: paidCents,
            debt: debtCents,
            paymentMethod: saleMutation.payload['payment_method'] as String? ?? 'veresiye',
            createdAt: now,
          );
          await txn.insert('sync_events', finTxMutation.toDbRow());
        }

        if (_faultHook != null) await _faultHook!('after_sync_events_insert');
      });
    } catch (e) {
      // Eşzamanlı yarış durumunu (UNIQUE constraint ihlali) adli olarak yakala ve doğrula:
      final isUniqueViolation = (e is DatabaseException &&
              (e.isUniqueConstraintError() ||
                  e.toString().contains('UNIQUE constraint failed'))) ||
          e.toString().contains('UNIQUE constraint failed');

      if (isUniqueViolation) {
        // Eşzamanlı yarışan diğer checkout transaction'ı tamamlanmış olabilir.
        // Sales tablosunu derhal yeniden oku ve doğrula:
        final racedSales = await _db.query(
          'sales',
          where: 'idempotency_key = ? OR receipt_no = ?',
          whereArgs: [idempotencyKey, request.receiptNo],
          limit: 1,
        );
        if (racedSales.isNotEmpty) {
          return await _evaluateExistingSale(
            existing: racedSales.first,
            request: request,
            state: state,
            idempotencyKey: idempotencyKey,
          );
        }
      }
      // UNIQUE çakışması dışındaki veya doğrulanamayan genel hataları asla yutma:
      rethrow;
    }

    // ── SATIŞ TRANSACTION'I BİTTİ (BAŞARILI) ─────────────────────────────────
    final saleOrder = SaleOrderEntity(
      id: saleId,
      receiptNo: request.receiptNo,
      customerId: customer?.id,
      subtotal: state.subtotal,
      discount: state.generalDiscount,
      total: totalCents,
      paid: paidCents,
      debt: debtCents,
      items: orderItems,
      payments: effectiveSplits,
      createdAt: now,
    );

    // 4. Fiş Yazdırma Komutunu Arka Plan Isolate'ine Fırlat (NON-BLOCKING)
    if (request.autoPrintReceipt && _hardwareWorker.isInitialized) {
      final paymentTypeDesc = effectiveSplits.isNotEmpty
          ? effectiveSplits.map((s) => s.type.name.toUpperCase()).join('+')
          : 'NAKİT';

      _hardwareWorker.printReceipt(
        PrintReceiptCommand(
          correlationId: saleId,
          receiptNo: request.receiptNo,
          title: request.storeTitle,
          address: request.storeAddress,
          phone: request.storePhone,
          items: receiptItems,
          subtotalCents: state.subtotal.value,
          discountCents: state.generalDiscount.value,
          totalCents: totalCents.value,
          paidCents: paidCents.value,
          debtCents: debtCents.value,
          paymentType: paymentTypeDesc,
          customerName: customer?.name,
          timestamp: now,
          openCashDrawer: request.openCashDrawer,
          cutPaper: true,
        ),
      );
    }

    return saleOrder;
  }

  /// İdempotency kaydını değerlendirir: Birebir aynı sepet ise replay, farklı ise açık çakışma hatası.
  Future<SaleOrderEntity> _evaluateExistingSale({
    required Map<String, Object?> existing,
    required CheckoutRequest request,
    required CoreSalesFlowState state,
    required String idempotencyKey,
  }) async {
    final existingReceipt = existing['receipt_no'] as String;
    final existingTotal = existing['total_cents'] as int;
    final existingPaid = existing['paid_cents'] as int;
    final existingDebt = existing['debt_cents'] as int;
    final totalCents = state.total;
    final paidCents = state.paidTotal;
    final debtCents = state.debtTotal;

    // Birebir aynı satış isteği mi tekrarlandı? (IDEMPOTENT REPLAY)
    final isExactReplay = existingReceipt == request.receiptNo &&
        existingTotal == totalCents.value &&
        existingPaid == paidCents.value &&
        existingDebt == debtCents.value;

    if (isExactReplay) {
      // İkinci kez tahsilat ve stok düşümü yapmadan mevcut satışı getir ve güvenle döndür
      return await _reconstructSaleOrder(existing['id'] as String);
    } else {
      // Çakışma: Aynı idempotency key veya fiş no ile farklı tutarlı bir sepet!
      throw StateError(
        'İdempotency çakışması: "$idempotencyKey" anahtarı daha önce farklı tutar (${existingTotal} kuruş) ile kaydedilmiştir. İkinci işlem reddedildi.',
      );
    }
  }

  /// Veritabanından mevcut satışı ve ilişkili kayıtlarını tekilleştirip yeniden oluşturur.
  Future<SaleOrderEntity> _reconstructSaleOrder(String saleId) async {
    final saleRows = await _db.query('sales', where: 'id = ?', whereArgs: [saleId]);
    if (saleRows.isEmpty) throw StateError('Satış bulunamadı: $saleId');
    final row = saleRows.first;

    final itemRows = await _db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
    final items = itemRows.map((m) => SaleOrderItemEntity.fromMap(m)).toList();

    final paymentRows = await _db.query('sale_payments', where: 'sale_id = ?', whereArgs: [saleId]);
    final payments = paymentRows.map((m) => PaymentSplitEntity(
      type: PaymentType.values.byName(m['payment_type'] as String),
      amount: MoneyCents(m['amount_cents'] as int),
      referenceNote: m['reference_note'] as String?,
    )).toList();

    return SaleOrderEntity(
      id: row['id'] as String,
      receiptNo: row['receipt_no'] as String,
      customerId: row['customer_id'] as String?,
      subtotal: MoneyCents(row['subtotal_cents'] as int),
      discount: MoneyCents(row['discount_cents'] as int? ?? 0),
      vatTotal: MoneyCents(row['vat_total_cents'] as int? ?? 0),
      total: MoneyCents(row['total_cents'] as int),
      paid: MoneyCents(row['paid_cents'] as int),
      debt: MoneyCents(row['debt_cents'] as int? ?? 0),
      items: items,
      payments: payments,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }
}
