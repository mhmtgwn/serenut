// core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart
import 'core_sales_flow_notifier.dart';
import '../../domain/models/core_entities.dart';
import '../../domain/models/money_cents.dart';
import '../../domain/models/rbac_models.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';

enum SalesEngineType { legacy, coreNext }

/// Kasa Satış Motoru Sonuç Modeli (Doğrulanmış Entegrasyon Sözleşmesi)
class SalesEngineCheckoutResult {
  final bool isSuccess;
  final String? saleId;
  final String? receiptNo;
  final String? customerId;
  final MoneyCents? subtotal;
  final MoneyCents? discount;
  final MoneyCents? vatTotal;
  final MoneyCents? total;
  final MoneyCents? paid;
  final MoneyCents? debt;
  final List<SaleOrderItemEntity> items;
  final List<PaymentSplitEntity> payments;
  final int stockMovementsCount;
  final bool hasLedgerDebit;
  final bool isOutboxEnqueued;
  final DateTime? createdAt;
  final String? idempotencyKey;
  final SaleOrderEntity? coreSaleOrder;
  final dynamic legacySale;
  final String? errorMessage;
  final SalesEngineType executedEngine;

  const SalesEngineCheckoutResult({
    required this.isSuccess,
    this.saleId,
    this.receiptNo,
    this.customerId,
    this.subtotal,
    this.discount,
    this.vatTotal,
    this.total,
    this.paid,
    this.debt,
    this.items = const [],
    this.payments = const [],
    this.stockMovementsCount = 0,
    this.hasLedgerDebit = false,
    this.isOutboxEnqueued = false,
    this.createdAt,
    this.idempotencyKey,
    this.coreSaleOrder,
    this.legacySale,
    this.errorMessage,
    required this.executedEngine,
  });

  /// Başarısız işlem sonucu üreteci
  factory SalesEngineCheckoutResult.failure({
    String? receiptNo,
    String? idempotencyKey,
    required String errorMessage,
    required SalesEngineType executedEngine,
  }) {
    return SalesEngineCheckoutResult(
      isSuccess: false,
      receiptNo: receiptNo,
      idempotencyKey: idempotencyKey,
      errorMessage: errorMessage,
      executedEngine: executedEngine,
    );
  }

  /// UI ve legacy SaleEntity modelleriyle uyumlu Map çıktısı döner
  Map<String, dynamic> toSaleEntityMap({String? paymentMethod, String? createdBy}) {
    return {
      'id': saleId ?? '',
      'customer_id': customerId ?? '',
      'total_amount': total?.toLira() ?? 0.0,
      'paid_amount': paid?.toLira() ?? 0.0,
      'discount_amount': discount?.toLira() ?? 0.0,
      'payment_method': paymentMethod ?? (debt?.isPositive == true ? 'debt' : 'cash'),
      'status': 'completed',
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'items': items.map((i) => {
        'product_id': i.productId,
        'product_name': i.productName,
        'quantity': i.quantity,
        'unit_price': i.unitPrice.toLira(),
        'total': i.total.toLira(),
      }).toList(),
      'idempotency_key': idempotencyKey,
      'is_synced': 0,
      'created_by': createdBy ?? 'Kasiyer',
    };
  }
}

/// Satış Motoru Güvenli Adaptörü (Feature Flag & Controlled Routing)
/// 
/// KRİTİK GÜVENLİK İLKELERİ:
/// 1. Varsayılan motor her zaman 'legacy'dir (useCoreNext = false).
/// 2. Satış işlemi (transaction) devam ederken motor dinamik olarak DEĞİŞTİRİLEMEZ.
/// 3. Yeni motorda hata oluşursa körü körüne eski motora otomatik geçiş YAPILMAZ!
///    (Çünkü veritabanına kısmi kayıt gitmiş veya fiş kesilmiş olabilir; 
///    önce idempotency anahtarıyla durum teyit edilmelidir).
/// 4. Para hesaplarında kayan noktalı sayı kullanılmaz, kuruş bazlı MoneyCents esastır.
class SalesEngineAdapter {
  final CoreSalesFlowNotifier? _coreNotifier;
  final ActorContext? _defaultActor;
  CutoffMaintenanceLock? _cutoffLock;
  bool _useCoreNext;
  bool _isOperationInProgress = false;

  SalesEngineAdapter({
    CoreSalesFlowNotifier? coreNotifier,
    bool initialUseCoreNext = false, // Varsayılan kesinlikle false
    ActorContext? defaultActor,
    CutoffMaintenanceLock? cutoffLock,
  })  : _coreNotifier = coreNotifier,
        _defaultActor = defaultActor,
        _cutoffLock = cutoffLock,
        _useCoreNext = initialUseCoreNext;

  bool get isCoreNextActive => _useCoreNext;
  bool get isOperationInProgress => _isOperationInProgress;
  CutoffMaintenanceLock? get cutoffLock => _cutoffLock;

  /// Bakım kilidini dinamik olarak bağlar veya günceller
  void setCutoffLock(CutoffMaintenanceLock? lock) {
    _cutoffLock = lock;
  }

  /// Özellik bayrağını kontrollü şekilde değiştirir.
  void setFeatureFlag(bool enabled) {
    if (_isOperationInProgress) {
      throw StateError(
        'Devam eden bir satış işlemi varken motor değiştirilemez! '
        'Lütfen önce mevcut işlemi tamamlayın veya iptal edin.',
      );
    }
    _useCoreNext = enabled;
  }

  /// Mevcut sepet ve ödeme durumunu CoreSalesFlowNotifier'a deterministik aktarır
  void syncFromCart({
    required List<ProductEntity> products,
    required Map<String, int> quantities,
    CustomerEntity? customer,
    MoneyCents discount = MoneyCents.zero,
    required List<PaymentSplitEntity> paymentSplits,
  }) {
    if (_coreNotifier == null) return;
    _coreNotifier!.clearCart();
    for (final prod in products) {
      final qty = quantities[prod.id];
      if (qty != null && qty > 0) {
        if (prod.unit == ProductUnit.gram || prod.unit == ProductUnit.kg) {
          _coreNotifier!.addWeighedProduct(prod, qty);
        } else {
          _coreNotifier!.addProduct(prod, quantity: qty);
        }
      }
    }
    _coreNotifier!.selectCustomer(customer);
    _coreNotifier!.setGeneralDiscount(discount);
    _coreNotifier!.setPaymentSplits(paymentSplits);
  }

  /// Satışı seçili motor üzerinden yürütür.
  Future<SalesEngineCheckoutResult> executeCheckout({
    required String receiptNo,
    required String storeTitle,
    String? storeAddress,
    String? storePhone,
    String? idempotencyKey,
    ActorContext? actor,
    Future<dynamic> Function()? legacyExecute,
  }) async {
    if (_isOperationInProgress) {
      throw StateError('Şu anda başka bir satış işlemi devam ediyor.');
    }

    // Bakım kilidi kontrolü: Kilit aktifse veya draining aşamasındaysa yeni checkout başlatılamaz
    if (_cutoffLock != null) {
      _cutoffLock!.assertWritePermitted(operation: 'SalesEngineAdapter:executeCheckout');
    }

    Future<SalesEngineCheckoutResult> action() async {
      _isOperationInProgress = true;
      try {
        if (_useCoreNext) {
          if (_coreNotifier == null) {
            throw StateError('CoreNext motoru seçildi ancak notifier başlatılmamış.');
          }

          final saleOrder = await _coreNotifier!.completeCheckout(
            receiptNo: receiptNo,
            storeTitle: storeTitle,
            storeAddress: storeAddress,
            storePhone: storePhone,
            idempotencyKey: idempotencyKey,
            actor: actor ?? _defaultActor,
          );

          return SalesEngineCheckoutResult(
            isSuccess: true,
            saleId: saleOrder.id,
            receiptNo: saleOrder.receiptNo,
            customerId: saleOrder.customerId,
            subtotal: saleOrder.subtotal,
            discount: saleOrder.discount,
            vatTotal: saleOrder.vatTotal,
            total: saleOrder.total,
            paid: saleOrder.paid,
            debt: saleOrder.debt,
            items: saleOrder.items,
            payments: saleOrder.payments,
            stockMovementsCount: saleOrder.items.length,
            hasLedgerDebit: saleOrder.debt.value > 0,
            isOutboxEnqueued: true,
            createdAt: saleOrder.createdAt,
            idempotencyKey: idempotencyKey ?? receiptNo,
            coreSaleOrder: saleOrder,
            executedEngine: SalesEngineType.coreNext,
          );
        } else {
          // Legacy motor yolu:
          // Eğer dışarıdan gerçek legacy yürütücü verilmişse onu çağırır.
          dynamic legacyResult;
          if (legacyExecute != null) {
            legacyResult = await legacyExecute();
          }

          return SalesEngineCheckoutResult(
            isSuccess: true,
            receiptNo: receiptNo,
            idempotencyKey: idempotencyKey,
            legacySale: legacyResult,
            executedEngine: SalesEngineType.legacy,
          );
        }
      } catch (e) {
        // Kesim kilidi istisnası doğrudan fırlatılmalıdır
        if (e is CutoffMaintenanceActiveException) {
          rethrow;
        }
        // KRİTİK GÜVENLİK KURALI:
        // Yeni motorda hata olursa otomatik olarak legacy motora geçilmez!
        // Doğrudan hata döndürülür.
        return SalesEngineCheckoutResult.failure(
          receiptNo: receiptNo,
          idempotencyKey: idempotencyKey,
          errorMessage: e.toString(),
          executedEngine: _useCoreNext ? SalesEngineType.coreNext : SalesEngineType.legacy,
        );
      } finally {
        _isOperationInProgress = false;
      }
    }

    if (_cutoffLock != null) {
      return await _cutoffLock!.drainer.runTrackedWrite(
        operationType: 'executeCheckout',
        caller: 'SalesEngineAdapter',
        action: action,
        isWritePermitted: () => _cutoffLock!.state.isWritePermitted,
        currentPhase: () => _cutoffLock!.state.phase,
      );
    } else {
      return await action();
    }
  }
}
