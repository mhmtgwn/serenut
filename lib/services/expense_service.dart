import 'database_service.dart';
import '../models/expense.dart';

class ExpenseService {
  Future<List<Expense>> getAll() async {
    final db = await DatabaseService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'expenses',
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => Expense.fromMap(maps[i]));
  }

  Future<int> add(Expense expense) async {
    final db = await DatabaseService.database;
    return await db.insert('expenses', expense.toMap());
  }

  Future<void> delete(int id) async {
    final db = await DatabaseService.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalByDate(String date) async {
    final db = await DatabaseService.database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE date LIKE ?',
      ['$date%'],
    );
    return result.first['total'] as double? ?? 0.0;
  }
}
