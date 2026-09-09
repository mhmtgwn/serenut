import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/config/utils.dart';

class SqliteGlobalSearchRepository implements IGlobalSearchRepository {
  final DbGateway _gateway;

  SqliteGlobalSearchRepository(this._gateway);

  @override
  Future<GlobalSearchResult> searchAll(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const GlobalSearchResult(
        customers: [],
        products: [],
        sales: [],
        transactions: [],
      );
    }

    final rawPattern = '%$trimmed%';
    final qPattern = '%${trimmed.normalizeTurkish}%';

    // 1. Search Customers
    final customerRows = await _gateway.rawQuery('''
      SELECT * FROM customers 
      WHERE is_active = 1 
        AND (${sqliteTurkishFold('name')} LIKE ? OR email LIKE ? OR phone LIKE ?)
      LIMIT 50
    ''', [qPattern, rawPattern, rawPattern]);

    final List<CustomerEntity> customers =
        customerRows.map((map) => CustomerEntity.fromMap(map)).toList();

    // 2. Search Products
    final productRows = await _gateway.rawQuery('''
      SELECT * FROM products 
      WHERE is_active = 1 
        AND (
          ${sqliteTurkishFold('name')} LIKE ? 
          OR ${sqliteTurkishFold('category')} LIKE ? 
          OR ${sqliteTurkishFold('description')} LIKE ? 
          OR id LIKE ? 
          OR sku LIKE ?
        )
      LIMIT 50
    ''', [
      qPattern,
      qPattern,
      qPattern,
      rawPattern,
      rawPattern,
    ]);

    final List<ProductEntity> products =
        productRows.map((map) => ProductEntity.fromMap(map)).toList();

    // 3. Search Sales
    final saleRows = await _gateway.rawQuery('''
      SELECT * FROM sales 
      WHERE (is_deleted = 0 OR is_deleted IS NULL)
        AND (
          id LIKE ? 
          OR customer_id LIKE ?
          OR ${sqliteTurkishFold('payment_method')} LIKE ? 
          OR ${sqliteTurkishFold('status')} LIKE ?
          OR ${sqliteTurkishFold('notes')} LIKE ?
        )
      LIMIT 50
    ''', [rawPattern, rawPattern, qPattern, qPattern, qPattern]);

    final List<SaleEntity> sales =
        saleRows.map((map) => SaleEntity.fromMap(map)).toList();

    // 4. Search Financial Transactions
    final txRows = await _gateway.rawQuery('''
      SELECT * FROM financial_transactions 
      WHERE (COALESCE(is_deleted, 0) = 0)
        AND (
          id LIKE ? 
          OR reference_id LIKE ? 
          OR type LIKE ? 
          OR customer_id IN (
            SELECT id FROM customers 
            WHERE ${sqliteTurkishFold('name')} LIKE ? OR phone LIKE ?
          )
        )
      LIMIT 50
    ''', [rawPattern, rawPattern, rawPattern, qPattern, rawPattern]);

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

