// test/services/remote_data_sources_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/datasources/remote_data_sources.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

void main() {
  group('RemoteDataSources Mock Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
    });

    test('CloudProductRemoteDataSource fetches products list correctly', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"products": [{"id": "p1", "name": "Apple", "description": "Fresh Red Apple", "price": 10.5, "quantity": 100, "category": "Fruit", "vat": 8}]}',
          headers: {},
        );
      };

      final dataSource = CloudProductRemoteDataSource(apiClient);
      final products = await dataSource.fetchProducts();

      expect(products.length, 1);
      expect(products.first.id, 'p1');
      expect(products.first.name, 'Apple');
      expect(products.first.price, 10.5);
      expect(products.first.vat, 8);
    });

    test('CloudCustomerRemoteDataSource fetches debtors correctly', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"customers": [{"id": "c1", "name": "John Doe", "email": "john@doe.com", "phone": "123", "balance": -50.0, "created_at": "2026-07-04T10:00:00Z"}]}',
          headers: {},
        );
      };

      final dataSource = CloudCustomerRemoteDataSource(apiClient);
      final customers = await dataSource.fetchCustomers();

      expect(customers.length, 1);
      expect(customers.first.id, 'c1');
      expect(customers.first.name, 'John Doe');
      expect(customers.first.balance, -50.0);
    });

    test('CloudSalesRemoteDataSource pushes sale entity successfully', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"status": "ok"}',
          headers: {},
        );
      };

      final dataSource = CloudSalesRemoteDataSource(apiClient);
      final sale = SaleEntity(
        id: 's1',
        customerId: 'c1',
        paymentMethod: 'cash',
        totalAmount: 120.0,
        paidAmount: 120.0,
        status: 'completed',
        createdAt: DateTime.now(),
        items: const [
          {'product_id': 'p1', 'quantity': 2, 'unit_price': 60.0}
        ],
      );

      await expectLater(dataSource.pushSale(sale), completes);
    });
  });
}
