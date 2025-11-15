import 'database_helper.dart';

class ExpenseService {
  static final ExpenseService _instance = ExpenseService._internal();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  factory ExpenseService() => _instance;

  ExpenseService._internal();

  static ExpenseService get instance => _instance;

  // Tüm giderleri getir
  Future<List<Expense>> getAllExpenses() async {
    try {
      return await _dbHelper.getAllExpenses();
    } catch (e) {
      return [];
    }
  }

  // Kategoriye göre giderleri getir
  Future<List<Expense>> getExpensesByCategory(String category) async {
    try {
      return await _dbHelper.getExpensesByCategory(category);
    } catch (e) {
      return [];
    }
  }

  // Yeni gider ekle
  Future<int> addExpense(String title, double amount, String category, String notes) async {
    try {
      return await _dbHelper.addExpense(title, amount, category, notes);
    } catch (e) {
      throw Exception('Gider eklenirken bir hata oluştu: $e');
    }
  }

  // Gider sil
  Future<int> deleteExpense(int expenseId) async {
    try {
      return await _dbHelper.deleteExpense(expenseId);
    } catch (e) {
      throw Exception('Gider silinirken bir hata oluştu: $e');
    }
  }

  // Giderleri kategorilere göre grupla
  Future<Map<String, double>> getExpensesByCategories() async {
    try {
      final expenses = await getAllExpenses();
      final Map<String, double> result = {};
      
      for (var expense in expenses) {
        if (result.containsKey(expense.category)) {
          result[expense.category] = result[expense.category]! + expense.amount;
        } else {
          result[expense.category] = expense.amount;
        }
      }
      
      return result;
    } catch (e) {
      return {};
    }
  }

  // Toplam gider tutarını getir
  Future<double> getTotalExpenses() async {
    try {
      final expenses = await getAllExpenses();
      double total = 0;
      for (var expense in expenses) {
        total += expense.amount;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
} 
