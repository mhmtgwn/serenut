import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Dual-Write Minor Currency (Kuruş) Contract Tests', () {
    late Database db;
    late DbGateway gateway;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 60,
        onCreate: (db, version) async {
          await DatabaseSchema.createTables(db);
        },
      );
      gateway = DbGatewayImpl.raw(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Product creation dual-writes price and price_minor accurately', () async {
      final repo = SqliteProductRepository(gateway);
      final product = ProductEntity(
        id: 'prod-dual-1',
        name: 'Dual Write Çikolata',
        description: 'Lezzetli Çikolata',
        price: 49.95,
        purchasePrice: 32.50,
        quantity: 20,
        category: 'Gıda',
      );

      await repo.create(product);

      final rows = await db.query('products', where: 'id = ?', whereArgs: ['prod-dual-1']);
      expect(rows.isNotEmpty, isTrue);
      expect(rows.first['price'], 49.95);
      expect(rows.first['price_minor'], 4995);
      expect(rows.first['purchase_price'], 32.50);
      expect(rows.first['purchase_price_minor'], 3250);
    });

    test('Customer creation and balance dual-writes balance and balance_minor accurately', () async {
      final repo = SqliteCustomerRepository(gateway);
      final customer = CustomerEntity(
        id: 'cust-dual-1',
        name: 'Ahmet Yılmaz',
        phone: '05551234567',
        balance: -250.75,
        createdAt: DateTime.now(),
      );

      await repo.create(customer);

      final rows = await db.query('customers', where: 'id = ?', whereArgs: ['cust-dual-1']);
      expect(rows.isNotEmpty, isTrue);
      expect(rows.first['balance'], -250.75);
      expect(rows.first['balance_minor'], -25075);
    });

    test('FinancialTransactionEntity.toMap dual-writes amount and amount_minor', () {
      final tx = FinancialTransactionEntity(
        id: 'ft-dual-1',
        type: 'sale',
        customerId: 'cust-1',
        amount: 199.90,
        paidAmount: 50.0,
        debtAmount: 149.90,
        date: DateTime.now(),
      );

      final map = tx.toMap();
      expect(map['amount'], 199.90);
      expect(map['amount_minor'], 19990);
      expect(map['paid_amount'], 50.0);
      expect(map['paid_amount_minor'], 5000);
      expect(map['debt_amount'], 149.90);
      expect(map['debt_amount_minor'], 14990);
    });

    test('SaleEntity.toMap dual-writes total_amount and total_amount_minor', () {
      final sale = SaleEntity(
        id: 'sale-dual-1',
        customerId: 'cust-1',
        totalAmount: 350.50,
        paidAmount: 350.50,
        discountAmount: 25.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        items: const [],
      );

      final map = sale.toMap();
      expect(map['total_amount'], 350.50);
      expect(map['total_amount_minor'], 35050);
      expect(map['paid_amount'], 350.50);
      expect(map['paid_amount_minor'], 35050);
      expect(map['discount_amount'], 25.0);
      expect(map['discount_amount_minor'], 2500);
    });
  });
}
