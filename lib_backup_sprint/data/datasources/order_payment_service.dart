import 'package:sqflite/sqflite.dart';
import 'customer_service.dart';
import '../../shared/utils/debug_config.dart';

/// Sipariş ödeme işlemleri için ayrı servis
class OrderPaymentService {
  static final OrderPaymentService instance = OrderPaymentService._init();

  // Bekleyen ödemeleri tutacak map
  final Map<int, List<Map<String, dynamic>>> _pendingPayments = {};

  OrderPaymentService._init();

  /// Siparişe ödeme ekle
  Future<bool> addPaymentToOrder(int orderId, double paymentAmount,
      String paymentMethod, Database db) async {
    try {
      // Siparişi al
      final List<Map<String, dynamic>> orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
      );

      if (orders.isEmpty) {
        return false;
      }

      final order = orders.first;
      final customerId = order['customerId'] as int?;
      if (customerId == null) {
        return false;
      }

      final totalAmount = order['totalAmount'] as double? ?? 0.0;
      final currentPaidAmount = order['paidAmount'] as double? ?? 0.0;

      // Yeni ödenen tutarı hesapla
      final newPaidAmount = currentPaidAmount + paymentAmount;

      // Ödeme durumunu belirle
      String paymentStatus = 'Kısmi Ödeme';
      if (newPaidAmount >= totalAmount) {
        paymentStatus = 'Ödendi';
      }

      // Ödeme geçmişine ekle
      final now = DateTime.now().toIso8601String();
      await db.insert('payment_history', {
        'orderId': orderId,
        'amount': paymentAmount,
        'method': paymentMethod,
        'paymentDate': now,
        'createdAt': now,
      });

      // Siparişi güncelle
      await db.update(
        'orders',
        {
          'paidAmount': newPaidAmount,
          'remainingAmount': totalAmount - newPaidAmount,
          'paymentStatus': paymentStatus,
          'paymentMethod': paymentMethod,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      // Fazla ödeme durumunu kontrol et
      if (newPaidAmount > totalAmount) {
        final excessPayment = newPaidAmount - totalAmount;

        // Müşterinin diğer borçlarından düş
        final bool debtReduced = await CustomerService.instance
            .reduceCustomerDebt(customerId, excessPayment);

        if (debtReduced) {
          DebugConfig.logSuccess(
              'Fazla ödeme müşterinin diğer borçlarından düşüldü');
        }
      }

      return true;
    } catch (e) {
      DebugConfig.logError('Ödeme eklenirken hata', e);
      return false;
    }
  }

  /// Ödeme geçmişini getir
  Future<List<Map<String, dynamic>>> getPaymentHistory(
      int orderId, Database db) async {
    try {
      // Ödeme geçmişini sorgula
      final List<Map<String, dynamic>> payments = await db.query(
        'payment_history',
        where: 'orderId = ?',
        whereArgs: [orderId],
        orderBy: 'paymentDate DESC',
      );

      return payments;
    } catch (e) {
      DebugConfig.logError('Ödeme geçmişi alınırken hata', e);
      return [];
    }
  }

  /// Bekleyen ödeme ekle
  void addPendingPayment(int orderId, double amount, String method) {
    if (!_pendingPayments.containsKey(orderId)) {
      _pendingPayments[orderId] = [];
    }

    _pendingPayments[orderId]!.add({
      'amount': amount,
      'method': method,
      'date': DateTime.now().toIso8601String(),
    });
  }

  /// Bekleyen ödemeleri getir
  List<Map<String, dynamic>> getPendingPayments(int orderId) {
    return _pendingPayments[orderId] ?? [];
  }

  /// Bekleyen ödemelerin toplam tutarını hesapla
  double getPendingPaymentsTotal(int orderId) {
    final payments = _pendingPayments[orderId] ?? [];
    return payments.fold(
        0.0, (sum, payment) => sum + (payment['amount'] as double));
  }

  /// Bekleyen ödemeleri temizle
  void clearPendingPayments(int orderId) {
    _pendingPayments.remove(orderId);
  }

  /// Bekleyen ödemeleri onayla ve veritabanına kaydet
  Future<bool> confirmPendingPayments(int orderId, Database db) async {
    final payments = _pendingPayments[orderId] ?? [];
    if (payments.isEmpty) {
      return true;
    }

    bool allSuccess = true;
    for (var payment in payments) {
      final success = await addPaymentToOrder(
        orderId,
        payment['amount'],
        payment['method'],
        db,
      );

      if (!success) {
        allSuccess = false;
        break;
      }
    }

    if (allSuccess) {
      // Başarılı olduysa bekleyen ödemeleri temizle
      clearPendingPayments(orderId);
    }

    return allSuccess;
  }

  /// Ödeme kaydını sil
  Future<bool> deletePayment(int paymentId, Database db) async {
    try {
      // Önce ödeme kaydını al
      final List<Map<String, dynamic>> payments = await db.query(
        'payment_history',
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      if (payments.isEmpty) {
        return false;
      }

      final payment = payments.first;
      final int orderId = payment['orderId'];
      final double paymentAmount = payment['amount'];

      // Siparişi al
      final List<Map<String, dynamic>> orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
      );

      if (orders.isEmpty) {
        return false;
      }

      final order = orders.first;
      final double totalAmount = order['totalAmount'] ?? 0.0;
      final double currentPaidAmount = order['paidAmount'] ?? 0.0;

      // Yeni ödenen tutarı hesapla
      final double newPaidAmount = currentPaidAmount - paymentAmount;

      // Ödeme kaydını sil
      final deleteResult = await db.delete(
        'payment_history',
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      if (deleteResult == 0) {
        return false;
      }

      // Siparişi güncelle
      String paymentStatus = 'Bekliyor';
      if (newPaidAmount > 0) {
        paymentStatus = newPaidAmount >= totalAmount ? 'Ödendi' : 'Kısmi Ödeme';
      }

      await db.update(
        'orders',
        {
          'paidAmount': newPaidAmount,
          'remainingAmount': totalAmount - newPaidAmount,
          'paymentStatus': paymentStatus,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      return true;
    } catch (e) {
      DebugConfig.logError('Ödeme silinirken hata', e);
      return false;
    }
  }
}
