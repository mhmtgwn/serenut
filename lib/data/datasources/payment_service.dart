import '../../shared/utils/debug_config.dart';
import '../../data/models/payment.dart';
import 'order_service.dart';
import 'expense_service.dart';

class PaymentService {
  static final PaymentService instance = PaymentService._init();

  PaymentService._init();

  /// Tüm ödemeleri getir (payment_history tablosundan)
  Future<List<Payment>> getAllPayments() async {
    try {
      final db = await OrderService.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'payment_history',
        orderBy: 'paymentDate DESC',
      );

      return List.generate(maps.length, (i) {
        return Payment.fromMap({
          'id': maps[i]['id'],
          'orderId': maps[i]['orderId'],
          'amount': maps[i]['amount'],
          'method': maps[i]['method'],
          'notes': '',
          'date': maps[i]['paymentDate'],
          'createdAt': maps[i]['createdAt'],
        });
      });
    } catch (e) {
      DebugConfig.logError('Ödemeler alınırken hata', e);
      return [];
    }
  }

  /// Belirli bir siparişin ödemelerini getir
  Future<List<Payment>> getPaymentsByOrderId(int orderId) async {
    try {
      final db = await OrderService.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'payment_history',
        where: 'orderId = ?',
        whereArgs: [orderId],
        orderBy: 'paymentDate DESC',
      );

      return List.generate(maps.length, (i) {
        return Payment.fromMap({
          'id': maps[i]['id'],
          'orderId': maps[i]['orderId'],
          'amount': maps[i]['amount'],
          'method': maps[i]['method'],
          'notes': '',
          'date': maps[i]['paymentDate'],
          'createdAt': maps[i]['createdAt'],
        });
      });
    } catch (e) {
      DebugConfig.logError('Sipariş ödemeleri alınırken hata', e);
      return [];
    }
  }

  /// Yeni ödeme ekle
  Future<int> addPayment(
      int orderId, double amount, String notes, String method) async {
    try {
      final db = await OrderService.instance.database;
      final now = DateTime.now().toIso8601String();

      return await db.insert('payment_history', {
        'orderId': orderId,
        'amount': amount,
        'method': method,
        'paymentDate': now,
        'createdAt': now,
      });
    } catch (e) {
      DebugConfig.logError('Ödeme eklenirken hata', e);
      rethrow;
    }
  }

  /// Ödeme sil
  Future<int> deletePayment(int paymentId) async {
    try {
      final db = await OrderService.instance.database;
      return await db.delete(
        'payment_history',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    } catch (e) {
      DebugConfig.logError('Ödeme silinirken hata', e);
      rethrow;
    }
  }

  /// Borçlu müşterileri getir
  Future<List<Map<String, dynamic>>> getCustomersWithDebt() async {
    try {
      final db = await OrderService.instance.database;
      final List<Map<String, dynamic>> orders = await db.query(
        'orders',
        where: 'remainingAmount > 0',
        orderBy: 'remainingAmount DESC',
      );

      // Müşterilere göre grupla
      final Map<int, Map<String, dynamic>> customerDebts = {};

      for (var order in orders) {
        final customerId = order['customerId'] as int;
        final remainingAmount = order['remainingAmount'] as double;

        if (customerDebts.containsKey(customerId)) {
          customerDebts[customerId]!['totalDebt'] += remainingAmount;
        } else {
          customerDebts[customerId] = {
            'customerId': customerId,
            'customerName': order['customerName'],
            'customerPhone': order['customerPhone'],
            'totalDebt': remainingAmount,
          };
        }
      }

      return customerDebts.values.toList();
    } catch (e) {
      DebugConfig.logError('Borçlu müşteriler alınırken hata', e);
      return [];
    }
  }

  /// Finansal özet bilgilerini getir
  Future<Map<String, double>> getFinancialSummary() async {
    try {
      final db = await OrderService.instance.database;

      // Toplam satışlar
      final salesResult = await db.rawQuery(
        'SELECT SUM(totalAmount) as total FROM orders WHERE orderStatus = ?',
        ['Satış'],
      );
      final totalSales =
          (salesResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // Toplam ödenen
      final paidResult = await db.rawQuery(
        'SELECT SUM(paidAmount) as total FROM orders',
      );
      final totalPaid = (paidResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // Toplam borç
      final debtResult = await db.rawQuery(
        'SELECT SUM(remainingAmount) as total FROM orders WHERE remainingAmount > 0',
      );
      final totalDebt = (debtResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // Toplam giderler (expense_service'ten)
      double totalExpenses = 0.0;
      try {
        totalExpenses = await ExpenseService.instance.getTotalExpenses();
      } catch (e) {
        DebugConfig.logWarning('Giderler alınamadı: $e');
      }

      return {
        'totalSales': totalSales,
        'totalPaid': totalPaid,
        'totalDebt': totalDebt,
        'totalExpenses': totalExpenses,
      };
    } catch (e) {
      DebugConfig.logError('Finansal özet alınırken hata', e);
      return {
        'totalSales': 0.0,
        'totalPaid': 0.0,
        'totalDebt': 0.0,
        'totalExpenses': 0.0,
      };
    }
  }

  /// Son ödemeleri getir
  Future<List<Map<String, dynamic>>> getRecentPayments({int limit = 10}) async {
    try {
      final db = await OrderService.instance.database;
      final List<Map<String, dynamic>> payments = await db.rawQuery('''
        SELECT 
          ph.id,
          ph.orderId,
          ph.amount,
          ph.method,
          ph.paymentDate,
          o.customerName
        FROM payment_history ph
        LEFT JOIN orders o ON ph.orderId = o.id
        ORDER BY ph.paymentDate DESC
        LIMIT ?
      ''', [limit]);

      return payments;
    } catch (e) {
      DebugConfig.logError('Son ödemeler alınırken hata', e);
      return [];
    }
  }
}
