import '../models/customer.dart';
import 'database_service.dart';

class CustomerService {
  Future<List<Customer>> getAll() async {
    final db = await DatabaseService.database;
    final maps = await db.query('customers', orderBy: 'name ASC');
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  Future<Customer?> getById(int id) async {
    final db = await DatabaseService.database;
    final maps = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Customer.fromMap(maps.first);
  }

  Future<int> add(Customer customer) async {
    final db = await DatabaseService.database;
    return await db.insert('customers', customer.toMap());
  }

  Future<void> update(Customer customer) async {
    final db = await DatabaseService.database;
    await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await DatabaseService.database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Customer>> search(String query) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'customers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );
    return maps.map((map) => Customer.fromMap(map)).toList();
  }
}
