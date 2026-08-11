import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/demo_data_seeder.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';

void main() {
  setUp(InMemoryDb.reset);

  test('demo seed creates a small coherent market dataset exactly once',
      () async {
    final seeder = DemoDataSeeder(
      productRepository: InMemoryProductRepository(),
      customerRepository: InMemoryCustomerRepository(),
      orderRepository: InMemoryOrderRepository(),
      saleRepository: InMemorySaleRepository(),
    );

    await seeder.seed(businessType: 'Market');
    await seeder.seed(businessType: 'Market');

    expect(InMemoryDb.products, hasLength(7));
    expect(
      InMemoryDb.customers.where((customer) => customer.id == demoCustomerId),
      hasLength(1),
    );
    final customer = InMemoryDb.customers.singleWhere(
      (customer) => customer.id == demoCustomerId,
    );
    expect(customer.name, 'Mehmet Güven');
    expect(customer.phone, '05380288202');
    expect(InMemoryDb.orders.where((order) => order.id == demoOrderId),
        hasLength(1));
    expect(
        InMemoryDb.sales.where((sale) => sale.id == demoSaleId), hasLength(1));
  });

  test('industry templates remain between five and ten demo products',
      () async {
    final seeder = DemoDataSeeder(
      productRepository: InMemoryProductRepository(),
      customerRepository: InMemoryCustomerRepository(),
      orderRepository: InMemoryOrderRepository(),
      saleRepository: InMemorySaleRepository(),
    );

    await seeder.seed(businessType: 'Kuruyemişçi');

    expect(InMemoryDb.products.length, inInclusiveRange(5, 10));
    expect(InMemoryDb.orders, hasLength(1));
    expect(InMemoryDb.sales, hasLength(1));
  });
}
