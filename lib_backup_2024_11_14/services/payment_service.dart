import 'database_helper.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  factory PaymentService() => _instance;

  PaymentService._internal();

  static PaymentService get instance => _instance;

  // Tüm ödemeleri getir
  Future<List<Payment>> getAllPayments() async {
    try {
      return await _dbHelper.getAllPayments();
    } catch (e) {
      return [];
    }
  }

  // Belirli bir siparişin ödemelerini getir
  Future<List<Payment>> getPaymentsByOrderId(int orderId) async {
    try {
      return await _dbHelper.getPaymentsByOrderId(orderId);
    } catch (e) {
      return [];
    }
  }

  // Yeni ödeme ekle
  Future<int> addPayment(int orderId, double amount, String notes, String method) async {
    try {
      return await _dbHelper.addPayment(orderId, amount, notes, method);
    } catch (e) {
      throw Exception('Ödeme eklenirken bir hata oluştu: $e');
    }
  }

  // Ödeme sil
  Future<int> deletePayment(int paymentId) async {
    try {
      return await _dbHelper.deletePayment(paymentId);
    } catch (e) {
      throw Exception('Ödeme silinirken bir hata oluştu: $e');
    }
  }

  // Borçlu müşterileri getir
  Future<List<Map<String, dynamic>>> getCustomersWithDebt() async {
    try {
      return await _dbHelper.getCustomersWithDebt();
    } catch (e) {
      return [];
    }
  }

  // Finansal özet bilgilerini getir
  Future<Map<String, double>> getFinancialSummary() async {
    try {
      final summary = await _dbHelper.getFinancialSummary();
      print('PaymentService - Finansal özet: $summary');
      return summary;
    } catch (e) {
      print('PaymentService - Finansal özet hatası: $e');
      return {
        'totalSales': 0.0,
        'totalPaid': 0.0,
        'totalDebt': 0.0,
        'totalExpenses': 0.0,
      };
    }
  }

  // Son ödemeleri getir
  Future<List<Map<String, dynamic>>> getRecentPayments({int limit = 10}) async {
    try {
      // Önce payment_history tablosunu kontrol et
      
      // Sonra normal ödemeleri al
      final recentPayments = await _dbHelper.getRecentPayments(limit: limit);
      
      return recentPayments;
    } catch (e) {
      return [];
    }
  }
} 
