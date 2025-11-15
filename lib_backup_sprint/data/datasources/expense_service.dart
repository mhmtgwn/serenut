import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../shared/utils/debug_config.dart';
import '../../data/models/expense.dart';

class ExpenseService {
  static final ExpenseService instance = ExpenseService._init();
  static Database? _database;

  ExpenseService._init();

  Future<Database> get database async {
    if (_database != null) {
      try {
        await _database!.rawQuery('SELECT 1');
        return _database!;
      } catch (e) {
        _database = null;
      }
    }

    _database = await _initDB('expenses.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);

      return await openDatabase(
        path,
        version: 1,
        onCreate: _createDB,
        readOnly: false,
        singleInstance: true,
      );
    } catch (e) {
      DebugConfig.logError('Gider veritabanı başlatma hatası', e);
      rethrow;
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        notes TEXT,
        date TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  /// Tüm giderleri getir
  Future<List<Expense>> getAllExpenses() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'expenses',
        orderBy: 'date DESC',
      );

      return List.generate(maps.length, (i) {
        return Expense.fromMap(maps[i]);
      });
    } catch (e) {
      DebugConfig.logError('Giderler alınırken hata', e);
      return [];
    }
  }

  /// Kategoriye göre giderleri getir
  Future<List<Expense>> getExpensesByCategory(String category) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'expenses',
        where: 'category = ?',
        whereArgs: [category],
        orderBy: 'date DESC',
      );

      return List.generate(maps.length, (i) {
        return Expense.fromMap(maps[i]);
      });
    } catch (e) {
      DebugConfig.logError('Kategoriye göre giderler alınırken hata', e);
      return [];
    }
  }

  /// Yeni gider ekle
  Future<int> addExpense(
      String title, double amount, String category, String notes) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();

      return await db.insert('expenses', {
        'title': title,
        'amount': amount,
        'category': category,
        'notes': notes,
        'date': now,
        'createdAt': now,
      });
    } catch (e) {
      DebugConfig.logError('Gider eklenirken hata', e);
      rethrow;
    }
  }

  /// Gider sil
  Future<int> deleteExpense(int expenseId) async {
    try {
      final db = await database;
      return await db.delete(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
      );
    } catch (e) {
      DebugConfig.logError('Gider silinirken hata', e);
      rethrow;
    }
  }

  /// Giderleri kategorilere göre grupla
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
      DebugConfig.logError('Kategorilere göre giderler alınırken hata', e);
      return {};
    }
  }

  /// Toplam gider tutarını getir
  Future<double> getTotalExpenses() async {
    try {
      final expenses = await getAllExpenses();
      double total = 0;
      for (var expense in expenses) {
        total += expense.amount;
      }
      return total;
    } catch (e) {
      DebugConfig.logError('Toplam gider hesaplanırken hata', e);
      return 0;
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
