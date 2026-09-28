// lib/infrastructure/repositories/end_of_day_repository.dart
// Kasa Sayımı, Nakit Akışı, Teslimat & Gün Sonu Raporu — Data Layer
// Created: 28 Sep 2026

import 'dart:convert';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

// ════════════════════════════════════════════════════════════
// DTOs
// ════════════════════════════════════════════════════════════

/// Satış ödeme yöntemi kırılım satırı (Tezgah Satışları)
class PaymentTypeLine {
  final String label;
  final int count;
  final double total;
  final String? subNote;

  const PaymentTypeLine({
    required this.label,
    required this.count,
    required this.total,
    this.subNote,
  });
}

/// Günlük tezgah satışı detay satırı
class SaleDetailLine {
  final String id;
  final String customerName;
  final double totalAmount;
  final double paidAmount;
  final String paymentMethod;
  final double cashPortion;
  final double cardPortion;
  final double debtPortion;
  final DateTime createdAt;

  const SaleDetailLine({
    required this.id,
    required this.customerName,
    required this.totalAmount,
    required this.paidAmount,
    required this.paymentMethod,
    required this.cashPortion,
    required this.cardPortion,
    required this.debtPortion,
    required this.createdAt,
  });
}

/// Bugün teslim edilen siparişin detay satırı
class DeliveredOrderLine {
  final String id;
  final String orderNumber;
  final String customerName;
  final double totalAmount;

  /// Geçmiş günlerde kapora olarak ödenmiş kısım
  final double previouslyPaid;

  /// Bugün teslimatta nakit ödenen kısım
  final double cashPaidToday;

  /// Bugün teslimatta karta çekilen kısım
  final double cardPaidToday;

  /// Kalan vadeli (veresiye) borç
  final double debtRemaining;

  final DateTime? deliveredAt;

  const DeliveredOrderLine({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.totalAmount,
    required this.previouslyPaid,
    required this.cashPaidToday,
    required this.cardPaidToday,
    required this.debtRemaining,
    this.deliveredAt,
  });
}

/// Cari tahsilat detay satırı
class CollectionDetailLine {
  final String id;
  final String customerName;
  final double amount;
  final String method;
  final String type;
  final String? description;
  final DateTime createdAt;

  const CollectionDetailLine({
    required this.id,
    required this.customerName,
    required this.amount,
    required this.method,
    required this.type,
    this.description,
    required this.createdAt,
  });
}

/// Teslimat ve Sipariş Özeti (Teslim edilen mal & ödeme dağılımı)
class OrderBreakdown {
  final int deliveredCount;
  final double deliveredTotal;

  /// Bu siparişlerin geçmişte ödenen kaporaları
  final double deliveredPrepaidTotal;

  /// Bu siparişlerden bugün teslimatta nakit alınan
  final double deliveredCashToday;

  /// Bu siparişlerden bugün teslimatta kartla alınan
  final double deliveredCardToday;

  /// Bu siparişlerden kalan vadeli borç
  final double deliveredDebtTotal;

  /// Bekleyen sipariş sayısı ve bekleyen siparişlerin toplam tutarı
  final int pendingCount;
  final double pendingTotal;

  /// İptal sipariş sayısı
  final int cancelledCount;

  /// Teslim edilen siparişlerin tek tek listesi
  final List<DeliveredOrderLine> deliveredOrders;

  const OrderBreakdown({
    required this.deliveredCount,
    required this.deliveredTotal,
    required this.deliveredPrepaidTotal,
    required this.deliveredCashToday,
    required this.deliveredCardToday,
    required this.deliveredDebtTotal,
    required this.pendingCount,
    required this.pendingTotal,
    required this.cancelledCount,
    this.deliveredOrders = const [],
  });
}

/// Kasadan nakit yapılan harcama/gider kalemi
class CashExpenseItem {
  final String id;
  final double amount;
  final String category;
  final String description;
  final String createdAt;

  const CashExpenseItem({
    required this.id,
    required this.amount,
    required this.category,
    required this.description,
    required this.createdAt,
  });
}

/// Kasa Sayım ve Kapanış Kaydı
class CashCountRecord {
  final String id;
  final String date;
  final double openingBalance;
  final double countedCash;
  final double expectedCash;
  final double difference;
  final String? notes;
  final DateTime createdAt;

  const CashCountRecord({
    required this.id,
    required this.date,
    required this.openingBalance,
    required this.countedCash,
    required this.expectedCash,
    required this.difference,
    this.notes,
    required this.createdAt,
  });
}

/// Kasa Nakit Akışı & Sayımı (Bugün kasaya ve bankaya fiilen giren paralar)
class CashFlowSummary {
  /// 0. Sabah Kasa Devri / Açılış Avansı
  final double openingBalance;

  /// 1. Tezgah satışlarından bugün kasaya giren nakit
  final double saleCash;

  /// 2. Yeni alınan siparişlerden bugün nakit alınan kaporalar (sipariş henüz teslim edilmemiş olsa bile kasada durur!)
  final double orderDepositCash;

  /// 3. Bugün teslim edilen siparişlerden elden alınan nakit
  final double orderDeliveryCash;

  /// 4. Müşterinin eski borcuna istinaden bugün elden getirdiği nakit (Cari tahsilat)
  final double collectionCash;

  /// 5. Bugün kasadan müşteriye geri ödenen nakit iadeler (eksi)
  final double refundCash;

  /// 6. Bugün kasadan yapılan nakit harcamalar / masraflar (eksi)
  final double expenseCash;

  /// Toplam Günlük Nakit Girişi (Açılış hariç)
  double get totalCashInflow =>
      saleCash + orderDepositCash + orderDeliveryCash + collectionCash;

  /// Toplam Günlük Nakit Çıkışı (İade + Masraflar)
  double get totalCashOutflow =>
      refundCash + expenseCash;

  /// FİZİKSEL KASADA BULUNMASI GEREKEN TOPLAM NAKİT
  /// = openingBalance + totalCashInflow - totalCashOutflow
  double get expectedCash =>
      (openingBalance + totalCashInflow - totalCashOutflow)
          .clamp(0.0, double.infinity);

  // ── Banka POS Girişleri (Bilgi Amaçlı) ──
  final double saleCard;
  final double orderDepositCard;
  final double orderDeliveryCard;
  final double collectionCard;
  final double refundCard;

  /// BANKAYA (POS) GİREN TOPLAM KART TUTARI
  double get totalPosCard =>
      (saleCard + orderDepositCard + orderDeliveryCard + collectionCard - refundCard)
          .clamp(0.0, double.infinity);

  /// Cari tahsilat makbuzları listesi
  final List<CollectionDetailLine> collectionsList;

  /// Kasadan yapılan harcamalar listesi
  final List<CashExpenseItem> expensesList;

  /// Daha önce kaydedilmiş fiili sayım (varsa)
  final double? savedCountedCash;
  final String? savedNotes;

  const CashFlowSummary({
    this.openingBalance = 0.0,
    required this.saleCash,
    required this.orderDepositCash,
    required this.orderDeliveryCash,
    required this.collectionCash,
    required this.refundCash,
    this.expenseCash = 0.0,
    required this.saleCard,
    required this.orderDepositCard,
    required this.orderDeliveryCard,
    required this.collectionCard,
    required this.refundCard,
    this.collectionsList = const [],
    this.expensesList = const [],
    this.savedCountedCash,
    this.savedNotes,
  });
}

/// Alacak & Piyasa Durumu
class ReceivablesSummary {
  /// Bugün oluşan yeni vadeli alacak (tezgah vadeli satışlar + vadeli teslim edilen siparişler)
  final double newDebtToday;

  /// Bugün tahsil edilen eski borçlar (cari tahsilat)
  final double collectedToday;

  /// Tüm müşterilerin toplam net piyasa borcu (alacağımız)
  final double totalReceivables;

  const ReceivablesSummary({
    required this.newDebtToday,
    required this.collectedToday,
    required this.totalReceivables,
  });
}

/// Gün Sonu Tam Rapor Nesnesi
class EndOfDayReport {
  final DateTime date;

  /// 1. Ciro & Hasılat Bilgileri
  final double directSalesRevenue;
  final double deliveredOrdersRevenue;
  final double totalRevenue;
  final double totalDiscount;
  final double totalRefunds;

  /// Net Ciro = (Tezgah Satışları + Teslim Edilen Siparişler) - İndirim - İade
  double get netRevenue => totalRevenue - totalDiscount - totalRefunds;

  /// 2. Satış Kırılımı (Tezgah)
  final List<PaymentTypeLine> salesBreakdown;
  final List<SaleDetailLine> salesList;
  int get totalSaleCount => salesList.length;

  /// 3. Sipariş & Teslimat Raporu
  final OrderBreakdown orders;

  /// 4. Kasa Nakit Akışı & Sayımı (Çekmece kontrolü)
  final CashFlowSummary cashFlow;

  /// 5. Alacak Durumu
  final ReceivablesSummary receivables;

  /// İptal satış sayısı
  final int cancelledSaleCount;

  const EndOfDayReport({
    required this.date,
    required this.directSalesRevenue,
    required this.deliveredOrdersRevenue,
    required this.totalRevenue,
    required this.totalDiscount,
    required this.totalRefunds,
    required this.salesBreakdown,
    required this.salesList,
    required this.orders,
    required this.cashFlow,
    required this.receivables,
    required this.cancelledSaleCount,
  });
}

// ════════════════════════════════════════════════════════════
// Repository
// ════════════════════════════════════════════════════════════

class EndOfDayRepository {
  final DbGateway _gateway;

  EndOfDayRepository(this._gateway);

  /// Seçili gün için kusursuz gün sonu ve kasa sayım raporunu derler.
  Future<EndOfDayReport> getReport(DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final results = await Future.wait([
      _fetchDirectSales(dayStr),
      _fetchOrderBreakdown(dayStr),
      _fetchDailyTransactions(dayStr),
      _fetchRefunds(dayStr),
      _fetchTotals(dayStr),
      _fetchDailyExpenses(dayStr),
      _fetchSavedCashCount(dayStr),
      _fetchPreviousDayClosingCash(dayStr),
    ]);

    final salesData = results[0] as _SalesDataResult;
    final orders = results[1] as OrderBreakdown;
    final txData = results[2] as _TransactionsDataResult;
    final refundData = results[3] as _RefundDataResult;
    final totals = results[4] as _TotalsRaw;
    final expensesResult = results[5] as _DailyExpensesResult;
    final savedCount = results[6] as _SavedCashCount?;
    final prevClosing = results[7] as double;

    // Sabah Kasa Devri / Avans:
    // Kayıtlı bir açılış avansı varsa onu al, yoksa bir önceki günün kapanış sayımını devir olarak öner
    final openingBalance = savedCount?.openingBalance ?? prevClosing;

    // Toplam piyasa alacağını çek
    final totalReceivables = await _fetchTotalReceivables();

    // ── KASA NAKİT AKIŞI MATEMATİĞİ ─────────────────────────
    // Kasaya bugün fiziksel olarak giren nakitler:
    // 1. Tezgah satışlarından nakit (direkt satışlar)
    final saleCash = salesData.totalCashCollected;
    final saleCard = salesData.totalCardCollected;

    // 2. Bugün oluşturulan siparişlerden alınan nakit kaporalar
    final orderDepositCash = txData.orderDepositCash;
    final orderDepositCard = txData.orderDepositCard;

    // 3. Bugün teslim edilen veya önceden sipariş edilmiş siparişlerden bugün alınan teslimat/ara nakit
    final orderDeliveryCash = txData.orderDeliveryCash;
    final orderDeliveryCard = txData.orderDeliveryCard;

    // 4. Müşteri cari borç tahsilatı (nakit)
    final collectionCash = txData.collectionCash;
    final collectionCard = txData.collectionCard;

    // 5. İadeler
    final refundCash = refundData.refundCash;
    final refundCard = refundData.refundCard;

    // 6. Kasadan Yapılan Harcamalar / Masraflar
    final expenseCash = expensesResult.total;

    final cashFlow = CashFlowSummary(
      openingBalance: openingBalance,
      saleCash: saleCash,
      orderDepositCash: orderDepositCash,
      orderDeliveryCash: orderDeliveryCash,
      collectionCash: collectionCash,
      refundCash: refundCash,
      expenseCash: expenseCash,
      saleCard: saleCard,
      orderDepositCard: orderDepositCard,
      orderDeliveryCard: orderDeliveryCard,
      collectionCard: collectionCard,
      refundCard: refundCard,
      collectionsList: txData.collectionDetails,
      expensesList: expensesResult.list,
      savedCountedCash: savedCount?.countedCash,
      savedNotes: savedCount?.notes,
    );

    // ── CİRO & HASILAT HESABI ──────────────────────────────
    // Ciro = Bugün yapılan tezgah satışları + Bugün teslim edilen siparişler
    final directSalesRevenue = totals.revenue;
    final deliveredOrdersRevenue = orders.deliveredTotal;
    final totalRevenue = directSalesRevenue + deliveredOrdersRevenue;

    // ── YENİ ALACAK HESABI ─────────────────────────────────
    // Bugün oluşan yeni vadeli borç:
    // Tezgah vadeli satışlar + Teslim edilen siparişlerden vadeli kalan
    final newDebtToday = salesData.totalDebtIncurred + orders.deliveredDebtTotal;

    final receivablesSummary = ReceivablesSummary(
      newDebtToday: newDebtToday,
      collectedToday: collectionCash + collectionCard,
      totalReceivables: totalReceivables,
    );

    // Tezgah Satış Kırılımı (Nakit, Kart, Vadeli, Karma)
    final salesLines = <PaymentTypeLine>[
      PaymentTypeLine(
        label: 'Nakit Satış',
        count: salesData.cashCount,
        total: salesData.totalCashCollected,
        subNote: salesData.karmaCount > 0 ? 'Karma nakit payı dahil' : null,
      ),
      PaymentTypeLine(
        label: 'Kredi Kartı',
        count: salesData.cardCount,
        total: salesData.totalCardCollected,
        subNote: salesData.karmaCount > 0 ? 'Karma kart payı dahil' : null,
      ),
      PaymentTypeLine(
        label: 'Vadeli (Veresiye)',
        count: salesData.debtCount,
        total: salesData.totalDebtIncurred,
        subNote: salesData.karmaCount > 0 ? 'Karma vadeli payı dahil' : null,
      ),
      if (salesData.karmaCount > 0)
        PaymentTypeLine(
          label: 'Karma Satışlar',
          count: salesData.karmaCount,
          total: salesData.karmaTotal,
          subNote:
              '₺${salesData.karmaCash.toStringAsFixed(2)} N + ₺${salesData.karmaCard.toStringAsFixed(2)} K + ₺${salesData.karmaDebt.toStringAsFixed(2)} V',
        ),
    ];

    return EndOfDayReport(
      date: dayStart,
      directSalesRevenue: directSalesRevenue,
      deliveredOrdersRevenue: deliveredOrdersRevenue,
      totalRevenue: totalRevenue,
      totalDiscount: totals.discount,
      totalRefunds: refundCash + refundCard,
      salesBreakdown: salesLines,
      salesList: salesData.salesList,
      orders: orders,
      cashFlow: cashFlow,
      receivables: receivablesSummary,
      cancelledSaleCount: totals.cancelledCount,
    );
  }

  // ── 1. Tezgah Satışları (sales tablosu) ──────────────────────
  Future<_SalesDataResult> _fetchDirectSales(String dayStr) async {
    final rows = await _gateway.rawQuery('''
      SELECT
        s.id,
        s.customer_id,
        COALESCE(c.name, 'Genel Müşteri') AS customer_name,
        s.total_amount,
        s.paid_amount,
        LOWER(COALESCE(s.payment_method, 'cash')) AS method,
        s.created_at,
        ft.metadata AS ft_metadata
      FROM sales s
      LEFT JOIN customers c ON s.customer_id = c.id
      LEFT JOIN financial_transactions ft ON ft.reference_id = s.id AND ft.type = 'sale'
      WHERE s.status NOT IN ('cancelled', 'iptal')
        AND (s.is_deleted = 0 OR s.is_deleted IS NULL)
        AND substr(s.created_at, 1, 10) = ?
      ORDER BY s.created_at DESC
    ''', [dayStr]);

    int cashCount = 0, cardCount = 0, debtCount = 0, karmaCount = 0;
    double pureCash = 0, pureCard = 0, pureDebt = 0;
    double karmaTotal = 0, karmaCash = 0, karmaCard = 0, karmaDebt = 0;

    final salesList = <SaleDetailLine>[];

    for (final r in rows) {
      final id = (r['id'] ?? '').toString();
      final customerName = (r['customer_name'] ?? 'Genel Müşteri').toString();
      final total = (r['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final method = (r['method'] as String? ?? 'cash').toLowerCase();
      final createdAt = DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now();

      double lineCash = 0;
      double lineCard = 0;
      double lineDebt = 0;

      if (_isCash(method)) {
        cashCount++;
        pureCash += total;
        lineCash = total;
      } else if (_isCard(method)) {
        cardCount++;
        pureCard += total;
        lineCard = total;
      } else if (method == 'karma') {
        karmaCount++;
        karmaTotal += total;

        final metaStr = r['ft_metadata'] as String?;
        double kCash = 0;
        double kCard = 0;
        double kDebt = 0;

        if (metaStr != null && metaStr.isNotEmpty) {
          try {
            final meta = jsonDecode(metaStr) as Map<String, dynamic>?;
            final breakdown = meta?['payment_breakdown'] as Map<String, dynamic>?;
            if (breakdown != null) {
              kCash = (breakdown['cash_applied'] ?? breakdown['cash_tendered'] as num?)?.toDouble() ?? 0.0;
              kCard = (breakdown['card'] as num?)?.toDouble() ?? 0.0;
              kDebt = (breakdown['debt'] as num?)?.toDouble() ?? 0.0;
            }
          } catch (_) {}
        }

        if (kCash == 0 && kCard == 0 && kDebt == 0) {
          kCash = paid;
          kDebt = (total - paid).clamp(0.0, double.infinity);
        }

        karmaCash += kCash;
        karmaCard += kCard;
        karmaDebt += kDebt;

        lineCash = kCash;
        lineCard = kCard;
        lineDebt = kDebt;
      } else {
        debtCount++;
        pureDebt += total;
        lineDebt = total;
      }

      salesList.add(SaleDetailLine(
        id: id,
        customerName: customerName,
        totalAmount: total,
        paidAmount: paid,
        paymentMethod: method,
        cashPortion: lineCash,
        cardPortion: lineCard,
        debtPortion: lineDebt,
        createdAt: createdAt,
      ));
    }

    return _SalesDataResult(
      cashCount: cashCount,
      cardCount: cardCount,
      debtCount: debtCount,
      karmaCount: karmaCount,
      totalCashCollected: pureCash + karmaCash,
      totalCardCollected: pureCard + karmaCard,
      totalDebtIncurred: pureDebt + karmaDebt,
      karmaTotal: karmaTotal,
      karmaCash: karmaCash,
      karmaCard: karmaCard,
      karmaDebt: karmaDebt,
      salesList: salesList,
    );
  }

  // ── 2. Sipariş & Teslimat Raporu (orders tablosu) ─────────────
  Future<OrderBreakdown> _fetchOrderBreakdown(String dayStr) async {
    try {
      // Bugün teslim edilen siparişler (actual_delivery_date = dayStr veya status=delivered & updated_at=dayStr)
      final deliveredRows = await _gateway.rawQuery('''
        SELECT
          o.id,
          o.order_number,
          o.customer_id,
          COALESCE(c.name, 'Genel Müşteri') AS customer_name,
          COALESCE(o.total_amount, 0) AS total_amount,
          o.actual_delivery_date,
          o.updated_at,
          o.created_at
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.id
        WHERE (o.is_deleted = 0 OR o.is_deleted IS NULL)
          AND LOWER(o.status) IN ('delivered', 'completed', 'teslim')
          AND substr(COALESCE(o.actual_delivery_date, o.updated_at, o.created_at), 1, 10) = ?
        ORDER BY COALESCE(o.actual_delivery_date, o.updated_at) DESC
      ''', [dayStr]);

      final deliveredOrders = <DeliveredOrderLine>[];
      double deliveredPrepaidTotal = 0;
      double deliveredCashToday = 0;
      double deliveredCardToday = 0;
      double deliveredDebtTotal = 0;

      for (final r in deliveredRows) {
        final orderId = (r['id'] ?? '').toString();
        final orderNumber = (r['order_number'] ?? '').toString();
        final customerName = (r['customer_name'] ?? 'Genel Müşteri').toString();
        final totalAmount = (r['total_amount'] as num?)?.toDouble() ?? 0.0;
        final deliveryDateStr = (r['actual_delivery_date'] ?? r['updated_at'] ?? r['created_at'])?.toString();
        final deliveryDate = deliveryDateStr != null ? DateTime.tryParse(deliveryDateStr) : null;

        // Siparişe ait tüm ödemeleri tarihleriyle çek
        final txRows = await _gateway.rawQuery('''
          SELECT
            type,
            amount,
            paid_amount,
            LOWER(COALESCE(payment_method, '')) AS method,
            metadata,
            created_at
          FROM financial_transactions
          WHERE reference_id = ?
            AND (is_deleted = 0 OR is_deleted IS NULL)
        ''', [orderId]);

        double prepaid = 0;
        double cashToday = 0;
        double cardToday = 0;

        for (final tx in txRows) {
          final txPaid = (tx['paid_amount'] as num?)?.toDouble() ??
              (tx['amount'] as num?)?.toDouble() ??
              0.0;
          final method = (tx['method'] ?? '').toString().toLowerCase();
          final txDateStr = (tx['created_at'] ?? '').toString();
          final isTodayTx = txDateStr.startsWith(dayStr);

          if (txPaid > 0) {
            if (isTodayTx) {
              if (_isCard(method)) {
                cardToday += txPaid;
              } else {
                cashToday += txPaid;
              }
            } else {
              // Geçmiş günlerde alınmış kapora/peşinat
              prepaid += txPaid;
            }
          }
        }

        final debtRemaining =
            (totalAmount - (prepaid + cashToday + cardToday)).clamp(0.0, double.infinity);

        deliveredPrepaidTotal += prepaid;
        deliveredCashToday += cashToday;
        deliveredCardToday += cardToday;
        deliveredDebtTotal += debtRemaining;

        deliveredOrders.add(DeliveredOrderLine(
          id: orderId,
          orderNumber: orderNumber,
          customerName: customerName,
          totalAmount: totalAmount,
          previouslyPaid: prepaid,
          cashPaidToday: cashToday,
          cardPaidToday: cardToday,
          debtRemaining: debtRemaining,
          deliveredAt: deliveryDate,
        ));
      }

      // Bekleyen ve iptal siparişler (oluşturulma veya güncelleme tarihine göre)
      final statusRows = await _gateway.rawQuery('''
        SELECT
          LOWER(COALESCE(status, '')) AS status,
          COUNT(*) AS cnt,
          COALESCE(SUM(total_amount), 0) AS total
        FROM orders
        WHERE (is_deleted = 0 OR is_deleted IS NULL)
          AND substr(created_at, 1, 10) = ?
        GROUP BY LOWER(COALESCE(status, ''))
      ''', [dayStr]);

      int pendingCount = 0, cancelledCount = 0;
      double pendingTotal = 0;

      for (final r in statusRows) {
        final status = (r['status'] as String? ?? '').toLowerCase();
        final cnt = (r['cnt'] as num?)?.toInt() ?? 0;
        final tot = (r['total'] as num?)?.toDouble() ?? 0.0;

        if (_isPending(status)) {
          pendingCount += cnt;
          pendingTotal += tot;
        } else if (_isCancelled(status)) {
          cancelledCount += cnt;
        }
      }

      final totalDelivered = deliveredOrders.length;
      final totalDeliveredAmount = deliveredOrders.fold(0.0, (s, o) => s + o.totalAmount);

      return OrderBreakdown(
        deliveredCount: totalDelivered,
        deliveredTotal: totalDeliveredAmount,
        deliveredPrepaidTotal: deliveredPrepaidTotal,
        deliveredCashToday: deliveredCashToday,
        deliveredCardToday: deliveredCardToday,
        deliveredDebtTotal: deliveredDebtTotal,
        pendingCount: pendingCount,
        pendingTotal: pendingTotal,
        cancelledCount: cancelledCount,
        deliveredOrders: deliveredOrders,
      );
    } catch (_) {
      return const OrderBreakdown(
        deliveredCount: 0,
        deliveredTotal: 0,
        deliveredPrepaidTotal: 0,
        deliveredCashToday: 0,
        deliveredCardToday: 0,
        deliveredDebtTotal: 0,
        pendingCount: 0,
        pendingTotal: 0,
        cancelledCount: 0,
        deliveredOrders: [],
      );
    }
  }

  // ── 3. Günlük Finansal Hareketler (financial_transactions) ────
  // Para ne zaman kasaya girdiyse O GÜNÜN hareketidir!
  Future<_TransactionsDataResult> _fetchDailyTransactions(String dayStr) async {
    double orderDepositCash = 0;
    double orderDepositCard = 0;
    double orderDeliveryCash = 0;
    double orderDeliveryCard = 0;
    double collectionCash = 0;
    double collectionCard = 0;

    final collectionDetails = <CollectionDetailLine>[];

    try {
      final rows = await _gateway.rawQuery('''
        SELECT
          ft.id,
          ft.customer_id,
          COALESCE(c.name, 'Cari Müşteri') AS customer_name,
          ft.type,
          ft.reference_id,
          ft.amount,
          ft.paid_amount,
          LOWER(COALESCE(ft.payment_method, 'cash')) AS method,
          ft.description,
          ft.metadata,
          ft.created_at,
          o.id AS is_order,
          s.id AS is_sale
        FROM financial_transactions ft
        LEFT JOIN customers c ON ft.customer_id = c.id
        LEFT JOIN orders o ON ft.reference_id = o.id
        LEFT JOIN sales s ON ft.reference_id = s.id
        WHERE (ft.is_deleted = 0 OR ft.is_deleted IS NULL)
          AND substr(ft.created_at, 1, 10) = ?
        ORDER BY ft.created_at DESC
      ''', [dayStr]);

      for (final r in rows) {
        final id = (r['id'] ?? '').toString();
        final customerName = (r['customer_name'] ?? 'Cari Müşteri').toString();
        final type = (r['type'] ?? '').toString().toLowerCase();
        final isOrder = r['is_order'] != null;
        final isSale = r['is_sale'] != null;
        final amount = (r['paid_amount'] as num?)?.toDouble() ??
            (r['amount'] as num?)?.toDouble() ??
            0.0;
        final method = (r['method'] as String? ?? 'cash').toLowerCase();
        final description = r['description'] as String?;
        final createdAt = DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now();

        if (amount <= 0) continue;

        // 1. Sipariş Kaporası (Bugün alınan yeni siparişten giren peşinat/kapora)
        if (isOrder && type == 'sale') {
          if (_isCard(method)) {
            orderDepositCard += amount;
          } else {
            orderDepositCash += amount;
          }
        }
        // 2. Sipariş Teslimat / Ara Ödemesi (Bugün siparişe yapılan ödeme)
        else if (isOrder && (type == 'payment' || type == 'collection')) {
          if (_isCard(method)) {
            orderDeliveryCard += amount;
          } else {
            orderDeliveryCash += amount;
          }
        }
        // 3. Cari Borç Tahsilatı (Doğrudan müşteriden borç kapama)
        else if (!isSale && !isOrder && (type == 'collection' || type == 'payment')) {
          if (_isCard(method)) {
            collectionCard += amount;
          } else {
            collectionCash += amount;
          }

          collectionDetails.add(CollectionDetailLine(
            id: id,
            customerName: customerName,
            amount: amount,
            method: method,
            type: type,
            description: description,
            createdAt: createdAt,
          ));
        }
      }
    } catch (_) {}

    return _TransactionsDataResult(
      orderDepositCash: orderDepositCash,
      orderDepositCard: orderDepositCard,
      orderDeliveryCash: orderDeliveryCash,
      orderDeliveryCard: orderDeliveryCard,
      collectionCash: collectionCash,
      collectionCard: collectionCard,
      collectionDetails: collectionDetails,
    );
  }

  // ── 4. İadeler (refunds tablosu) ─────────────────────────────
  Future<_RefundDataResult> _fetchRefunds(String dayStr) async {
    double refundCash = 0;
    double refundCard = 0;

    try {
      final refundRows = await _gateway.rawQuery('''
        SELECT
          LOWER(COALESCE(refund_method, 'cash')) AS method,
          COALESCE(SUM(amount), 0) AS total
        FROM refunds
        WHERE (status != 'cancelled' OR status IS NULL)
          AND substr(created_at, 1, 10) = ?
        GROUP BY LOWER(COALESCE(refund_method, 'cash'))
      ''', [dayStr]);

      for (final r in refundRows) {
        final m = (r['method'] as String? ?? 'cash').toLowerCase();
        final tot = (r['total'] as num?)?.toDouble() ?? 0.0;
        if (_isCard(m)) {
          refundCard += tot;
        } else {
          refundCash += tot;
        }
      }
    } catch (_) {}

    return _RefundDataResult(
      refundCash: refundCash,
      refundCard: refundCard,
    );
  }

  // ── 5. Ciro Toplamları (sales tablosu) ───────────────────────
  Future<_TotalsRaw> _fetchTotals(String dayStr) async {
    final rows = await _gateway.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN status NOT IN ('cancelled','iptal') THEN total_amount ELSE 0 END), 0) AS revenue,
        COALESCE(SUM(CASE WHEN status NOT IN ('cancelled','iptal') THEN discount_amount ELSE 0 END), 0) AS discount,
        COALESCE(SUM(CASE WHEN status IN ('cancelled','iptal') THEN 1 ELSE 0 END), 0) AS cancelled_cnt
      FROM sales
      WHERE (is_deleted = 0 OR is_deleted IS NULL)
        AND substr(created_at, 1, 10) = ?
    ''', [dayStr]);

    final row = rows.first;
    return _TotalsRaw(
      revenue: (row['revenue'] as num?)?.toDouble() ?? 0.0,
      discount: (row['discount'] as num?)?.toDouble() ?? 0.0,
      cancelledCount: (row['cancelled_cnt'] as num?)?.toInt() ?? 0,
    );
  }

  // ── 6. Toplam Piyasa Alacağı ────────────────────────────────
  Future<double> _fetchTotalReceivables() async {
    try {
      final rows = await _gateway.rawQuery('''
        SELECT COALESCE(SUM(-balance), 0) AS total
        FROM customers
        WHERE balance < 0
      ''');
      return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  // ── Yardımcı Filtreler ──────────────────────────────────────
  bool _isCash(String m) =>
      m == 'cash' || m == 'nakit' || m == 'peşin' || m == 'pesin';

  bool _isCard(String m) =>
      m == 'card' ||
      m == 'credit_card' ||
      m == 'kredi_karti' ||
      m == 'kart' ||
      m == 'pos' ||
      m.contains('card');

  bool _isPending(String s) =>
      s == 'created' ||
      s == 'pending' ||
      s == 'confirmed' ||
      s == 'preparing' ||
      s == 'ready' ||
      s == 'hazirlaniyor' ||
      s == 'yeni' ||
      s == 'shipped' ||
      s == 'yolda';

  bool _isCancelled(String s) =>
      s == 'cancelled' || s == 'iptal';

  Future<void> _ensureCashTables() async {
    try {
      await _gateway.execute('''
        CREATE TABLE IF NOT EXISTS cash_expenses (
          id TEXT PRIMARY KEY,
          amount REAL NOT NULL,
          category TEXT NOT NULL DEFAULT 'genel',
          description TEXT NOT NULL,
          created_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await _gateway.execute(
          'CREATE INDEX IF NOT EXISTS idx_cash_expenses_date ON cash_expenses(created_at, is_deleted)');
      await _gateway.execute('''
        CREATE TABLE IF NOT EXISTS cash_counts (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL UNIQUE,
          opening_balance REAL NOT NULL DEFAULT 0.0,
          counted_cash REAL NOT NULL DEFAULT 0.0,
          expected_cash REAL NOT NULL DEFAULT 0.0,
          difference REAL NOT NULL DEFAULT 0.0,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    } catch (_) {}
  }

  Future<_DailyExpensesResult> _fetchDailyExpenses(String dayStr) async {
    await _ensureCashTables();
    double total = 0.0;
    final List<CashExpenseItem> list = [];

    try {
      final rows = await _gateway.rawQuery('''
        SELECT id, amount, category, description, created_at
        FROM cash_expenses
        WHERE is_deleted = 0
          AND substr(created_at, 1, 10) = ?
        ORDER BY created_at DESC
      ''', [dayStr]);

      for (final r in rows) {
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        total += amt;
        list.add(CashExpenseItem(
          id: r['id'] as String? ?? '',
          amount: amt,
          category: r['category'] as String? ?? 'Genel',
          description: r['description'] as String? ?? '',
          createdAt: r['created_at'] as String? ?? '',
        ));
      }
    } catch (_) {}

    return _DailyExpensesResult(total: total, list: list);
  }

  Future<_SavedCashCount?> _fetchSavedCashCount(String dayStr) async {
    await _ensureCashTables();
    try {
      final rows = await _gateway.rawQuery('''
        SELECT opening_balance, counted_cash, notes
        FROM cash_counts
        WHERE date = ?
        LIMIT 1
      ''', [dayStr]);
      if (rows.isNotEmpty) {
        return _SavedCashCount(
          openingBalance:
              (rows.first['opening_balance'] as num?)?.toDouble() ?? 0.0,
          countedCash: (rows.first['counted_cash'] as num?)?.toDouble(),
          notes: rows.first['notes'] as String?,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<double> _fetchPreviousDayClosingCash(String dayStr) async {
    await _ensureCashTables();
    try {
      final rows = await _gateway.rawQuery('''
        SELECT counted_cash
        FROM cash_counts
        WHERE date < ?
        ORDER BY date DESC
        LIMIT 1
      ''', [dayStr]);
      if (rows.isNotEmpty) {
        return (rows.first['counted_cash'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  /// Kasadan yapılan nakit harcamayı kaydeder
  Future<void> addCashExpense({
    required double amount,
    required String category,
    required String description,
    DateTime? date,
  }) async {
    await _ensureCashTables();
    final id = 'exp_${DateTime.now().millisecondsSinceEpoch}';
    final now = (date ?? DateTime.now()).toIso8601String();
    await _gateway.insert('cash_expenses', {
      'id': id,
      'amount': amount,
      'category': category.trim().isEmpty ? 'Genel' : category.trim(),
      'description': description.trim(),
      'created_at': now,
      'is_deleted': 0,
    });
  }

  /// Masraf kaydını siler (soft-delete)
  Future<void> deleteCashExpense(String id) async {
    await _ensureCashTables();
    await _gateway.update(
      'cash_expenses',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Gün sonu kasa sayımını ve açılış devrini kaydeder
  Future<void> saveCashCount({
    required String date,
    required double openingBalance,
    required double countedCash,
    required double expectedCash,
    String? notes,
  }) async {
    await _ensureCashTables();
    final diff = countedCash - expectedCash;
    final now = DateTime.now().toIso8601String();
    await _gateway.rawInsert('''
      INSERT INTO cash_counts (id, date, opening_balance, counted_cash, expected_cash, difference, notes, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        opening_balance = excluded.opening_balance,
        counted_cash = excluded.counted_cash,
        expected_cash = excluded.expected_cash,
        difference = excluded.difference,
        notes = excluded.notes,
        updated_at = excluded.updated_at
    ''', [
      'count_$date',
      date,
      openingBalance,
      countedCash,
      expectedCash,
      diff,
      notes,
      now,
      now,
    ]);
  }
}

// ════════════════════════════════════════════════════════════
// Ara DTOs (private)
// ════════════════════════════════════════════════════════════

class _SalesDataResult {
  final int cashCount;
  final int cardCount;
  final int debtCount;
  final int karmaCount;
  final double totalCashCollected;
  final double totalCardCollected;
  final double totalDebtIncurred;
  final double karmaTotal;
  final double karmaCash;
  final double karmaCard;
  final double karmaDebt;
  final List<SaleDetailLine> salesList;

  const _SalesDataResult({
    required this.cashCount,
    required this.cardCount,
    required this.debtCount,
    required this.karmaCount,
    required this.totalCashCollected,
    required this.totalCardCollected,
    required this.totalDebtIncurred,
    required this.karmaTotal,
    required this.karmaCash,
    required this.karmaCard,
    required this.karmaDebt,
    required this.salesList,
  });
}

class _TransactionsDataResult {
  final double orderDepositCash;
  final double orderDepositCard;
  final double orderDeliveryCash;
  final double orderDeliveryCard;
  final double collectionCash;
  final double collectionCard;
  final List<CollectionDetailLine> collectionDetails;

  const _TransactionsDataResult({
    required this.orderDepositCash,
    required this.orderDepositCard,
    required this.orderDeliveryCash,
    required this.orderDeliveryCard,
    required this.collectionCash,
    required this.collectionCard,
    required this.collectionDetails,
  });
}

class _RefundDataResult {
  final double refundCash;
  final double refundCard;

  const _RefundDataResult({
    required this.refundCash,
    required this.refundCard,
  });
}

class _TotalsRaw {
  final double revenue;
  final double discount;
  final int cancelledCount;

  const _TotalsRaw({
    required this.revenue,
    required this.discount,
    required this.cancelledCount,
  });
}

class _DailyExpensesResult {
  final double total;
  final List<CashExpenseItem> list;

  const _DailyExpensesResult({
    required this.total,
    required this.list,
  });
}

class _SavedCashCount {
  final double openingBalance;
  final double? countedCash;
  final String? notes;

  const _SavedCashCount({
    required this.openingBalance,
    this.countedCash,
    this.notes,
  });
}
