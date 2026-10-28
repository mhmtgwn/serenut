// core_next/client_core/lib/domain/usecases/refund_use_case.dart

import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';

import '../../infrastructure/database/app_database.dart';
import '../models/core_entities.dart';
import '../models/money_cents.dart';
import '../models/rbac_models.dart';
import '../services/ledger_service.dart';
import '../../infrastructure/repositories/sqlite_ledger_repository.dart';

/// İade edilecek kalem detayı
class RefundItemRequest {
  final String productId;
  final int quantity; // İade adedi veya gramajı
  final String? saleItemId; // Belirli bir satış satırı hedefleniyorsa

  const RefundItemRequest({
    required this.productId,
    required this.quantity,
    this.saleItemId,
  });
}

/// İade ödeme dağılımı (Karma ödemeli satışlarda)
class RefundPaymentSplit {
  final PaymentType type;
  final MoneyCents amount;

  const RefundPaymentSplit({
    required this.type,
    required this.amount,
  });
}

/// İade İstek Modeli
class RefundRequest {
  final String originalSaleId;
  final List<RefundItemRequest> items; // Boş ise tam iade (tüm kalemler)
  final String reason;
  final ActorContext actor;
  final String? idempotencyKey;
  final List<RefundPaymentSplit>? paymentDistributions; // Karma ödemelerde zorunlu
  final bool allowManualRefundToCashOrBalance; // Yetkili onayıyla kartlı satışın elden nakit/cari iadesine izin verir

  const RefundRequest({
    required this.originalSaleId,
    this.items = const [],
    this.reason = 'Müşteri İadesi',
    required this.actor,
    this.idempotencyKey,
    this.paymentDistributions,
    this.allowManualRefundToCashOrBalance = false,
  });
}

/// İade Sonuç Varlığı
class RefundResultEntity {
  final String refundId;
  final String originalSaleId;
  final String receiptNo;
  final MoneyCents refundTotal;
  final List<SaleOrderItemEntity> refundedItems;
  final DateTime createdAt;

  const RefundResultEntity({
    required this.refundId,
    required this.originalSaleId,
    required this.receiptNo,
    required this.refundTotal,
    required this.refundedItems,
    required this.createdAt,
  });
}

/// Satış İade ve İptal Use-Case'i
/// 
/// KRİTİK GÜVENLİK VE ADLİ KURALLAR:
/// 1. Orijinal satış kaydı asla sessizce silinmez veya ezilmez; denetlenebilir ters kayıt oluşturulur.
/// 2. RBAC: Yalnızca `AppPermission.refund` iznine sahip aktörler iade yapabilir.
/// 3. Stok geri alımı (reinstatement): İade edilen ürünler stoğa tam adet/gram olarak geri eklenir.
/// 4. Finansal Ayrım: Nakit ödenmiş tutarlar müşteriye haksız alacak yazılmaz; yalnızca vadeli borç kısmı silinir.
/// 5. İdempotency Güvencesi: Aynı anahtar ve aynı istekle tekrarlandığında çökmez, mevcut sonucu döner.
/// 6. Eşzamanlı İade Yarışı: Tüm okuma, doğrulama ve yazma işlemleri tek ACID transaction içinde kilitlenir.
class CoreRefundUseCase {
  final CoreAppDatabase _db;
  final LedgerService? _ledgerService;
  final Uuid _uuid = const Uuid();

  CoreRefundUseCase({
    required CoreAppDatabase db,
    LedgerService? ledgerService,
  })  : _db = db,
        _ledgerService = ledgerService;

  LedgerService? get ledgerService => _ledgerService;

  Future<RefundResultEntity> execute(RefundRequest request) async {
    // 1. RBAC Yetkilendirme Kontrolü
    if (request.actor.isSystem) {
      throw const AuthorizationException(
        'Sistem arka plan kimliği (system actor) ile doğrudan satış iadesi yapılamaz.',
        requiredPermission: AppPermission.refund,
        userRole: AppRole.sysadmin,
      );
    }
    request.actor.requirePermission(AppPermission.refund, 'Satış iadesi yapma');

    // 2. Tüm İade İşlemini Tek Atomik ACID Transaction İçinde Yürüt
    return await _db.transaction<RefundResultEntity>((txn) async {
      // A) Orijinal Satışı Oku
      final saleRows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [request.originalSaleId],
        limit: 1,
      );
      if (saleRows.isEmpty) {
        throw StateError('İade edilecek orijinal satış bulunamadı (ID: ${request.originalSaleId}).');
      }
      final originalSale = saleRows.first;

      final itemRows = await txn.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [request.originalSaleId],
      );
      if (itemRows.isEmpty) {
        throw StateError('Orijinal satışa ait kalem kaydı bulunamadı.');
      }

      final originalItems = itemRows.map((r) => SaleOrderItemEntity.fromMap(r)).toList();
      final origReceipt = originalSale['receipt_no'] as String;

      // Çoklu satır desteği: Aynı ürünün birden fazla satırdaki miktarlarını topla
      final originalItemsByLineId = <String, SaleOrderItemEntity>{};
      final originalTotalQtys = <String, int>{};
      final sampleItemByProduct = <String, SaleOrderItemEntity>{};
      for (final it in originalItems) {
        originalItemsByLineId[it.id] = it;
        originalTotalQtys[it.productId] = (originalTotalQtys[it.productId] ?? 0) + it.quantity;
        sampleItemByProduct[it.productId] = it;
      }

      // B) İdempotency Ön Kontrolü: Bu anahtar daha önce kullanılmış mı?
      if (request.idempotencyKey != null && request.idempotencyKey!.trim().isNotEmpty) {
        final existingRefundRows = await txn.query(
          'sales',
          where: 'idempotency_key = ?',
          whereArgs: [request.idempotencyKey],
          limit: 1,
        );
        if (existingRefundRows.isNotEmpty) {
          final existing = existingRefundRows.first;
          final existingRefundId = existing['id'] as String;

          // 1. Orijinal satış kimliğini doğrula (sync_events üzerinden)
          final refSyncRow = await txn.query(
            'sync_events',
            where: "group_id = ? AND entity_type = 'financial_transaction'",
            whereArgs: [existingRefundId],
            limit: 1,
          );
          String? existingOriginalSaleId;
          Map<String, dynamic>? existingPayload;
          if (refSyncRow.isNotEmpty) {
            try {
              existingPayload = jsonDecode(refSyncRow.first['payload_json'] as String) as Map<String, dynamic>;
              existingOriginalSaleId = existingPayload['reference_id'] as String?;
            } catch (_) {}
          }

          if (existingOriginalSaleId != null && existingOriginalSaleId != request.originalSaleId) {
            throw StateError(
              'İdempotency Çakışması: "${request.idempotencyKey}" anahtarı daha önce farklı bir satış (ID: $existingOriginalSaleId) için kullanılmıştır.',
            );
          }

          // 2. İade edilen kalemleri ve satırları oku
          final existingItems = await txn.query(
            'sale_items',
            where: 'sale_id = ?',
            whereArgs: [existingRefundId],
            orderBy: 'product_id ASC',
          );
          final existingQtyByProduct = <String, int>{};
          final existingAmountByProduct = <String, int>{};
          int existingTotalCents = 0;
          for (final it in existingItems) {
            final pId = it['product_id'] as String;
            final q = (it['quantity'] as num).toInt();
            final tot = (it['total_cents'] as num).toInt().abs();
            existingQtyByProduct[pId] = (existingQtyByProduct[pId] ?? 0) + q;
            existingAmountByProduct[pId] = (existingAmountByProduct[pId] ?? 0) + tot;
            existingTotalCents += tot;
          }

          // 3. Mevcut istekteki kalemleri ve satırları topla
          final requestedQtyByProduct = <String, int>{};
          final requestedAmountByProduct = <String, int>{};
          int reqTotalCents = 0;
          if (request.items.isEmpty) {
            for (final it in originalItems) {
              requestedQtyByProduct[it.productId] = (requestedQtyByProduct[it.productId] ?? 0) + it.quantity;
              requestedAmountByProduct[it.productId] = (requestedAmountByProduct[it.productId] ?? 0) + it.total.value;
              reqTotalCents += it.total.value;
            }
          } else {
            for (final reqItem in request.items) {
              final lineItem = reqItem.saleItemId != null
                  ? originalItemsByLineId[reqItem.saleItemId]
                  : sampleItemByProduct[reqItem.productId];
              if (lineItem != null) {
                requestedQtyByProduct[reqItem.productId] = (requestedQtyByProduct[reqItem.productId] ?? 0) + reqItem.quantity;
                final lineCents = lineItem.quantity > 0
                    ? ((lineItem.total.value * reqItem.quantity) / lineItem.quantity).round()
                    : lineItem.unitPrice.value * reqItem.quantity;
                requestedAmountByProduct[reqItem.productId] = (requestedAmountByProduct[reqItem.productId] ?? 0) + lineCents;
                reqTotalCents += lineCents;
              }
            }
          }

          // 4. Tam payload karşılaştırması (Total, ürünler, miktarlar ve tutarlar)
          bool isExactMatch = true;
          if (existingTotalCents != reqTotalCents) {
            isExactMatch = false;
          } else if (existingQtyByProduct.length != requestedQtyByProduct.length) {
            isExactMatch = false;
          } else {
            for (final entry in requestedQtyByProduct.entries) {
              if (existingQtyByProduct[entry.key] != entry.value ||
                  existingAmountByProduct[entry.key] != requestedAmountByProduct[entry.key]) {
                isExactMatch = false;
                break;
              }
            }
          }

          // 5. Ödeme dağılımı (Payment Distributions) karşılaştırması
          final existingPaidCents = -(existing['paid_cents'] as num).toInt();
          final existingDebtCents = -(existing['debt_cents'] as num).toInt();

          int reqCashRefund = 0;
          int reqDebtRefund = 0;
          if (request.paymentDistributions != null && request.paymentDistributions!.isNotEmpty) {
            for (final split in request.paymentDistributions!) {
              if (split.type == PaymentType.cash) {
                reqCashRefund += split.amount.value;
              } else if (split.type == PaymentType.onAccount) {
                reqDebtRefund += split.amount.value;
              }
            }
            if (reqCashRefund != existingPaidCents || reqDebtRefund != existingDebtCents) {
              isExactMatch = false;
            }
          } else {
            // Dağılım verilmemişse, mevcut iadenin tek kanal olup olmadığı kontrol edilir
            if (existingPaidCents != reqTotalCents && existingDebtCents != reqTotalCents) {
              isExactMatch = false;
            }
          }

          if (isExactMatch) {
            // Birebir aynı tam payload tekrarlandı -> Güvenli Replay
            return RefundResultEntity(
              refundId: existingRefundId,
              originalSaleId: request.originalSaleId,
              receiptNo: existing['receipt_no'] as String,
              refundTotal: MoneyCents(existingTotalCents),
              refundedItems: existingItems.map((r) => SaleOrderItemEntity.fromMap(r)).toList(),
              createdAt: DateTime.fromMillisecondsSinceEpoch(existing['created_at'] as int),
            );
          } else {
            // Farklı ürün, miktar, tutar veya ödeme dağılımı ile aynı key -> CONFLICT
            throw StateError(
              'İdempotency Çakışması: "${request.idempotencyKey}" anahtarı daha önce farklı kalem, miktar, tutar veya ödeme dağılımı içeren bir iade ile kullanılmıştır.',
            );
          }
        }
      }

      // C) Daha Önce Yapılmış İadeleri Oku (Transaction İçinde Kilitli)
      final priorRefundItems = await txn.query(
        'sale_items',
        where: "sale_id IN (SELECT id FROM sales WHERE status = 'REFUND' AND receipt_no LIKE ?)",
        whereArgs: ['REF-$origReceipt%'],
      );
      final previouslyRefundedQtys = <String, int>{};
      for (final pri in priorRefundItems) {
        final pId = pri['product_id'] as String;
        final q = (pri['quantity'] as num).toInt();
        previouslyRefundedQtys[pId] = (previouslyRefundedQtys[pId] ?? 0) + q;
      }

      // D) İade Edilecek Kalemleri ve Tutarları Doğrula
      final itemsToRefund = <SaleOrderItemEntity>[];
      int computedRefundCents = 0;

      if (request.items.isEmpty) {
        // Tam İade: Kalan tüm orijinal kalemler
        for (final entry in originalTotalQtys.entries) {
          final pId = entry.key;
          final totalSold = entry.value;
          final alreadyRefunded = previouslyRefundedQtys[pId] ?? 0;
          final availableQty = totalSold - alreadyRefunded;
          if (availableQty <= 0) {
            throw StateError('Ürün (${sampleItemByProduct[pId]?.productName}) daha önce tamamen iade edilmiş.');
          }

          final sample = sampleItemByProduct[pId]!;
          final lineRefundCents = sample.quantity > 0
              ? ((sample.total.value * availableQty) / sample.quantity).round()
              : sample.unitPrice.value * availableQty;
          itemsToRefund.add(
            SaleOrderItemEntity(
              id: _uuid.v4(),
              saleId: '',
              productId: pId,
              barcode: sample.barcode,
              productName: sample.productName,
              unitPrice: sample.unitPrice,
              quantity: availableQty,
              total: MoneyCents(lineRefundCents),
              vatRate: sample.vatRate,
              isWeighed: sample.isWeighed,
            ),
          );
          computedRefundCents += lineRefundCents;
        }
      } else {
        // Kısmi İade: Belirtilen kalemler
        for (final reqItem in request.items) {
          final totalSold = originalTotalQtys[reqItem.productId];
          if (totalSold == null) {
            throw ArgumentError('İade edilmek istenen ürün orijinal satışta yok (ID: ${reqItem.productId}).');
          }
          if (reqItem.quantity <= 0) {
            throw ArgumentError('İade miktarı pozitif olmalıdır.');
          }

          final alreadyRefunded = previouslyRefundedQtys[reqItem.productId] ?? 0;
          final remainingQty = totalSold - alreadyRefunded;
          if (reqItem.quantity > remainingQty) {
            throw StateError(
              'İade miktarı (${reqItem.quantity}), kalan iade edilebilir miktarı ($remainingQty) aşamaz.',
            );
          }

          final lineItem = reqItem.saleItemId != null
              ? (originalItemsByLineId[reqItem.saleItemId] ?? sampleItemByProduct[reqItem.productId]!)
              : sampleItemByProduct[reqItem.productId]!;
          final lineRefundCents = lineItem.quantity > 0
              ? ((lineItem.total.value * reqItem.quantity) / lineItem.quantity).round()
              : lineItem.unitPrice.value * reqItem.quantity;
          itemsToRefund.add(
            SaleOrderItemEntity(
              id: _uuid.v4(),
              saleId: '',
              productId: lineItem.productId,
              barcode: lineItem.barcode,
              productName: lineItem.productName,
              unitPrice: lineItem.unitPrice,
              quantity: reqItem.quantity,
              total: MoneyCents(lineRefundCents),
              vatRate: lineItem.vatRate,
              isWeighed: lineItem.isWeighed,
            ),
          );
          computedRefundCents += lineRefundCents;
        }
      }

      final refundTotal = MoneyCents(computedRefundCents);
      final refundId = _uuid.v4();
      final idempotencyKey = request.idempotencyKey ?? 'idemp-ref-$refundId';

      // E) Finansal Kaynak Ayrımı ve Özgün Ödemeyle Mutabakat
      final origPayments = await txn.query(
        'sale_payments',
        where: 'sale_id = ? AND amount_cents > 0',
        whereArgs: [request.originalSaleId],
      );

      int origCashCents = 0;
      int origDebtCents = 0;
      int origCardCents = 0;
      if (origPayments.isNotEmpty) {
        for (final p in origPayments) {
          final pType = p['payment_type'] as String;
          final amt = (p['amount_cents'] as num).toInt();
          if (pType == 'cash') {
            origCashCents += amt;
          } else if (pType == 'onAccount' || pType == 'on_account') {
            origDebtCents += amt;
          } else if (pType == 'creditCard') {
            origCardCents += amt;
          }
        }
      } else {
        origCashCents = (originalSale['paid_cents'] as num?)?.toInt() ?? 0;
        origDebtCents = (originalSale['debt_cents'] as num?)?.toInt() ?? 0;
      }

      // Varsa önceki iadelerdeki nakit ve vadeli düşümleri topla
      final priorRefundSales = await txn.query(
        'sales',
        where: "status = 'REFUND' AND receipt_no LIKE ?",
        whereArgs: ['REF-$origReceipt%'],
      );
      int priorCashRefunded = 0;
      int priorDebtRefunded = 0;
      int priorTotalRefunded = 0;
      for (final prs in priorRefundSales) {
        priorTotalRefunded += ((prs['total_cents'] as num?)?.toInt() ?? 0).abs();
        final prsId = prs['id'] as String;
        final prsPayments = await txn.query(
          'sale_payments',
          where: 'sale_id = ?',
          whereArgs: [prsId],
        );
        if (prsPayments.isNotEmpty) {
          for (final p in prsPayments) {
            final pType = p['payment_type'] as String;
            final amt = (p['amount_cents'] as num).toInt().abs();
            if (pType == 'cash') {
              priorCashRefunded += amt;
            } else if (pType == 'onAccount' || pType == 'on_account') {
              priorDebtRefunded += amt;
            }
          }
        } else {
          priorCashRefunded += ((prs['paid_cents'] as num?)?.toInt() ?? 0).abs();
          priorDebtRefunded += ((prs['debt_cents'] as num?)?.toInt() ?? 0).abs();
        }
      }

      final origTotalCents = (originalSale['total_cents'] as num).toInt().abs();
      if (priorTotalRefunded + refundTotal.value > origTotalCents) {
        throw StateError(
          'Toplam iade tutarı (${priorTotalRefunded + refundTotal.value} kuruş), orijinal satış tutarını ($origTotalCents kuruş) aşamaz.',
        );
      }

      final availableCashRefundCents = max(0, origCashCents - priorCashRefunded);
      final availableDebtRefundCents = max(0, origDebtCents - priorDebtRefunded);

      // Kart ödemesi kontrolü ve esnek iade kanalları
      final hasCardOnly = (origCardCents > 0 && origCashCents == 0 && origDebtCents == 0);
      int cashRefundCents = 0;
      int debtRefundCents = 0;
      int cardRefundCents = 0;

      final isMixedSale = (origCashCents > 0 && origDebtCents > 0) ||
          (origCardCents > 0 && (origCashCents > 0 || origDebtCents > 0));

      if (hasCardOnly) {
        final hasExplicitDistribution = request.paymentDistributions != null && request.paymentDistributions!.isNotEmpty;
        if (!request.allowManualRefundToCashOrBalance && !hasExplicitDistribution) {
          throw UnsupportedError(
            'Kredi kartı ile tahsil edilmiş satışlar için harici POS/kart terminali iade entegrasyonu bulunmamaktadır. Otomatik kart iadesi yapılamaz.',
          );
        }

        if (hasExplicitDistribution) {
          int splitSum = 0;
          for (final split in request.paymentDistributions!) {
            if (split.amount.value < 0) {
              throw ArgumentError('İade dağılım tutarı negatif olamaz.');
            }
            if (split.amount.value == 0) continue;
            if (split.type == PaymentType.cash) {
              cashRefundCents += split.amount.value;
            } else if (split.type == PaymentType.onAccount) {
              debtRefundCents += split.amount.value;
            } else if (split.type == PaymentType.creditCard) {
              cardRefundCents += split.amount.value;
            } else {
              throw UnsupportedError('Desteklenmeyen iade ödeme türü: ${split.type}');
            }
            splitSum += split.amount.value;
          }
          if (splitSum != refundTotal.value) {
            throw StateError('İade ödeme dağılımı toplamı ($splitSum kuruş) iade tutarına (${refundTotal.value} kuruş) eşit olmalıdır.');
          }
        } else {
          // allowManualRefundToCashOrBalance aktif ise varsayılan olarak nakit iade yapılır
          cashRefundCents = refundTotal.value;
        }
      } else if (isMixedSale) {
        // Karma ödemeli satışlarda dağılım kontrolü
        if (request.paymentDistributions == null || request.paymentDistributions!.isEmpty) {
          throw StateError(
            'Karma ödemeli satışlarda iade tutarının hangi ödeme kanalından yapılacağı (paymentDistributions) açıkça belirtilmelidir. Otomatik tahmin yapılamaz.',
          );
        }

        int splitSum = 0;
        for (final split in request.paymentDistributions!) {
          if (split.amount.value < 0) {
            throw ArgumentError('İade dağılım tutarı negatif olamaz.');
          }
          if (split.amount.value == 0) continue;
          if (split.type == PaymentType.creditCard) {
            cardRefundCents += split.amount.value;
          } else if (split.type == PaymentType.bankTransfer) {
            cardRefundCents += split.amount.value;
          } else if (split.type == PaymentType.cash) {
            cashRefundCents += split.amount.value;
          } else if (split.type == PaymentType.onAccount) {
            debtRefundCents += split.amount.value;
          } else {
            throw UnsupportedError('Desteklenmeyen iade ödeme türü: ${split.type}');
          }
          splitSum += split.amount.value;
        }

        if (splitSum != refundTotal.value) {
          throw StateError(
            'İade ödeme dağılımı toplamı ($splitSum kuruş) iade tutarına (${refundTotal.value} kuruş) eşit olmalıdır.',
          );
        }

        if (debtRefundCents > availableDebtRefundCents) {
          throw StateError(
            'İade edilecek vadeli borç tutarı ($debtRefundCents kuruş), orijinal satışta kalan iade edilebilir vadeli tutarı ($availableDebtRefundCents kuruş) aşamaz.',
          );
        }
      } else if (origCashCents > 0) {
        // %100 Nakit Satış
        if (request.paymentDistributions != null && request.paymentDistributions!.isNotEmpty) {
          int splitSum = 0;
          for (final split in request.paymentDistributions!) {
            if (split.type != PaymentType.cash) {
              throw StateError('Yalnızca nakit tahsil edilmiş bir satış için ${split.type.name} iadesi yapılamaz.');
            }
            splitSum += split.amount.value;
          }
          if (splitSum != refundTotal.value) {
            throw StateError('İade ödeme dağılımı toplamı ($splitSum kuruş) iade tutarına (${refundTotal.value} kuruş) eşit olmalıdır.');
          }
        }
        cashRefundCents = refundTotal.value;
        debtRefundCents = 0;
        if (cashRefundCents > availableCashRefundCents) {
          throw StateError(
            'İade edilecek nakit tutarı ($cashRefundCents kuruş), orijinal satışta kalan iade edilebilir nakit tutarını ($availableCashRefundCents kuruş) aşamaz.',
          );
        }
      } else if (origDebtCents > 0) {
        // %100 Vadeli Satış
        if (request.paymentDistributions != null && request.paymentDistributions!.isNotEmpty) {
          int splitSum = 0;
          for (final split in request.paymentDistributions!) {
            if (split.type != PaymentType.onAccount) {
              throw StateError('Yalnızca veresiye tahsil edilmiş bir satış için ${split.type.name} iadesi yapılamaz.');
            }
            splitSum += split.amount.value;
          }
          if (splitSum != refundTotal.value) {
            throw StateError('İade ödeme dağılımı toplamı ($splitSum kuruş) iade tutarına (${refundTotal.value} kuruş) eşit olmalıdır.');
          }
        }
        debtRefundCents = refundTotal.value;
        cashRefundCents = 0;
        if (debtRefundCents > availableDebtRefundCents) {
          throw StateError(
            'İade edilecek vadeli borç tutarı ($debtRefundCents kuruş), orijinal satışta kalan iade edilebilir vadeli tutarı ($availableDebtRefundCents kuruş) aşamaz.',
          );
        }
      } else {
        throw StateError('Orijinal satışta geçerli bir ödeme kaydı bulunamadı.');
      }

      final now = DateTime.now();
      final priorCount = priorRefundSales.length;
      final suffix = priorCount > 0 ? '-${priorCount + 1}' : '';
      final refundReceiptNo = 'REF-$origReceipt$suffix';

      // F) İade Satış Başlığını Kaydet
      await txn.insert('sales', {
        'id': refundId,
        'receipt_no': refundReceiptNo,
        'customer_id': originalSale['customer_id'],
        'branch_id': originalSale['branch_id'],
        'subtotal_cents': -refundTotal.value,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': -refundTotal.value,
        'paid_cents': -(cashRefundCents + cardRefundCents),
        'debt_cents': -debtRefundCents,
        'status': 'REFUND',
        'idempotency_key': idempotencyKey,
        'created_at': now.millisecondsSinceEpoch,
      });

      // G) İade Kalemlerini Kaydet ve Stokları Geri Al (Reinstatement)
      final finalizedItems = <SaleOrderItemEntity>[];
      for (final it in itemsToRefund) {
        final itemId = _uuid.v4();
        await txn.insert('sale_items', {
          'id': itemId,
          'sale_id': refundId,
          'product_id': it.productId,
          'barcode': it.barcode,
          'product_name': it.productName,
          'unit_price_cents': it.unitPrice.value,
          'quantity': it.quantity,
          'discount_cents': 0,
          'vat_rate': it.vatRate,
          'total_cents': it.total.value,
        });

        // Önceki stoku ve tartılı ürün bilgisini sorgula
        final prodRows = await txn.query(
          'products',
          columns: ['stock_quantity', 'sale_type', 'unit'],
          where: 'id = ?',
          whereArgs: [it.productId],
          limit: 1,
        );
        final isWeighed = prodRows.isNotEmpty &&
            ((prodRows.first['sale_type'] == 'weighed') ||
                (prodRows.first['unit'] == 'kg' || prodRows.first['unit'] == 'gram'));
        final prevStock = prodRows.isNotEmpty
            ? ((prodRows.first['stock_quantity'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        final stockDelta = isWeighed ? (it.quantity / 1000.0) : it.quantity.toDouble();
        final newStock = prevStock + stockDelta;

        // Stoğu geri artır
        await txn.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
          [stockDelta, now.millisecondsSinceEpoch, it.productId],
        );

        // Append-Only Değişmez Stok Defteri Kaydı (stock_movements)
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': it.productId,
          'branch_id': originalSale['branch_id'],
          'reference_id': refundId,
          'reference_type': 'REFUND',
          'quantity_delta': stockDelta,
          'previous_stock': prevStock,
          'new_stock': newStock,
          'reason': 'İade: ${request.reason}',
          'created_by': request.actor.username,
          'created_at': now.millisecondsSinceEpoch,
        });

        finalizedItems.add(
          SaleOrderItemEntity(
            id: itemId,
            saleId: refundId,
            productId: it.productId,
            barcode: it.barcode,
            productName: it.productName,
            unitPrice: it.unitPrice,
            quantity: it.quantity,
            total: it.total,
            vatRate: it.vatRate,
            isWeighed: isWeighed,
          ),
        );
      }

      // H) Cari Hesap Etkisi (Yalnızca vadeli borç kısmı silinir, nakit satışta alacak YAZILMAZ!)
      final customerId = originalSale['customer_id'] as String?;
      if (customerId != null && customerId.isNotEmpty && debtRefundCents > 0) {
        // Deadlock'ı önlemek için transaction'a bağlı repository kullanılır!
        final txnLedgerRepo = SqliteLedgerRepository(txn);
        final txnLedgerService = LedgerService(txnLedgerRepo);

        await txnLedgerService.postRefund(
          entryId: _uuid.v4(),
          customerId: customerId,
          saleId: refundId,
          refundAmount: MoneyCents(debtRefundCents),
          description: 'Satış İadesi ($refundReceiptNo): Borç Düşümü',
          timestamp: now,
        );
      }

      // I) Ödeme Hareketlerini Kaydet
      if (cashRefundCents > 0) {
        await txn.insert('sale_payments', {
          'id': _uuid.v4(),
          'sale_id': refundId,
          'payment_type': 'cash',
          'amount_cents': -cashRefundCents,
          'created_at': now.millisecondsSinceEpoch,
        });

        // Kasa nakit defterine de atomik OUTFLOW kaydı ekle (Kasa mutabakatı ve Z-raporu için)
        await txn.insert('cash_transactions', {
          'id': _uuid.v4(),
          'type': 'OUTFLOW',
          'amount_cents': cashRefundCents,
          'category': 'REFUND',
          'description': 'Satış İadesi ($refundReceiptNo)',
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      if (debtRefundCents > 0) {
        await txn.insert('sale_payments', {
          'id': _uuid.v4(),
          'sale_id': refundId,
          'payment_type': 'on_account',
          'amount_cents': -debtRefundCents,
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      if (cardRefundCents > 0) {
        await txn.insert('sale_payments', {
          'id': _uuid.v4(),
          'sale_id': refundId,
          'payment_type': 'credit_card',
          'amount_cents': -cardRefundCents,
          'created_at': now.millisecondsSinceEpoch,
        });
      }

      // J) Senkronizasyon Kuyruğuna Ekle (Sunucu Sync V4 Uyumlu)
      final finMutationId = 'mut-ref-fin-$refundId';
      final finPayload = {
        'id': 'tx-ref-$refundId',
        'type': 'refund',
        'customer_id': customerId,
        'amount': refundTotal.toLira(),
        'paid_amount': MoneyCents(cashRefundCents).toLira(),
        'debt_amount': MoneyCents(debtRefundCents).toLira(),
        'reference_id': request.originalSaleId,
        'payment_method': debtRefundCents > 0 ? (cashRefundCents > 0 ? 'mixed' : 'veresiye') : 'cash',
        'date': now.toUtc().toIso8601String(),
        'description': request.reason.isNotEmpty ? request.reason : 'İade: $refundReceiptNo',
        'reason': request.reason,
        'items': finalizedItems.map((it) => {
          'product_id': it.productId,
          'quantity': it.quantity,
          'unit_price_cents': it.unitPrice.value,
          'total_cents': it.total.value,
        }).toList(),
        'payment_distributions': request.paymentDistributions?.map((d) => {
          'type': d.type.name,
          'amount_cents': d.amount.value,
        }).toList(),
      };

      await txn.insert('sync_events', {
        'event_id': finMutationId,
        'entity_type': 'financial_transaction',
        'entity_id': 'tx-ref-$refundId',
        'operation': 'UPSERT',
        'payload_json': jsonEncode(finPayload),
        'base_revision': 0,
        'client_timestamp': now.millisecondsSinceEpoch,
        'sync_state': 'PENDING',
        'attempts': 0,
        'group_id': refundId,
        'causal_sequence': 1,
      });

      return RefundResultEntity(
        refundId: refundId,
        originalSaleId: request.originalSaleId,
        receiptNo: refundReceiptNo,
        refundTotal: refundTotal,
        refundedItems: finalizedItems,
        createdAt: now,
      );
    });
  }
}
