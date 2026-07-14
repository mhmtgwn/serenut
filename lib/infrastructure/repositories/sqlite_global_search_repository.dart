import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

class SqliteGlobalSearchRepository implements IGlobalSearchRepository {
  final DbGateway _gateway;

  SqliteGlobalSearchRepository(this._gateway);

  @override
  Future<GlobalSearchResult> searchAll(String query) async {
    if (query.trim().isEmpty) {
      return const GlobalSearchResult(
        customers: [],
        products: [],
        sales: [],
        transactions: [],
      );
    }

    final searchPattern = '%${query.trim()}%';

    // 1. Search Customers
    final customerRows = await _gateway.rawQuery('''
      SELECT * FROM customers 
      WHERE is_active = 1 
        AND (name LIKE ? OR email LIKE ? OR phone LIKE ?)
      LIMIT 50
    ''', [searchPattern, searchPattern, searchPattern]);

    final List<CustomerEntity> customers =
        customerRows.map((map) => CustomerEntity.fromMap(map)).toList();

    // 2. Search Products
    final productRows = await _gateway.rawQuery('''
      SELECT * FROM products 
      WHERE is_active = 1 
        AND (name LIKE ? OR category LIKE ? OR description LIKE ? OR id LIKE ? OR sku LIKE ?)
      LIMIT 50
    ''', [
      searchPattern,
      searchPattern,
      searchPattern,
      searchPattern,
      searchPattern
    ]);

    final List<ProductEntity> products =
        productRows.map((map) => ProductEntity.fromMap(map)).toList();

    // 3. Search Sales
    final saleRows = await _gateway.rawQuery('''
      SELECT * FROM sales 
      WHERE id LIKE ? OR customer_id LIKE ? OR payment_method LIKE ? OR status LIKE ?
      LIMIT 50
    ''', [searchPattern, searchPattern, searchPattern, searchPattern]);

    final List<SaleEntity> sales =
        saleRows.map((map) => SaleEntity.fromMap(map)).toList();

    // 4. Search Financial Transactions
    final txRows = await _gateway.rawQuery('''
      SELECT * FROM financial_transactions 
      WHERE id LIKE ? OR reference_id LIKE ? OR type LIKE ? OR customer_id LIKE ?
      LIMIT 50
    ''', [searchPattern, searchPattern, searchPattern, searchPattern]);

    final List<FinancialTransactionEntity> transactions =
        txRows.map((map) => FinancialTransactionEntity.fromMap(map)).toList();

    return GlobalSearchResult(
      customers: customers,
      products: products,
      sales: sales,
      transactions: transactions,
    );
  }
}
