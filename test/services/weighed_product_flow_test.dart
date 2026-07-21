import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

void main() {
  test('weighed product stores grams and prices by kilogram', () {
    final notifier = SalesFlowNotifier();
    final product = ProductEntity(
      id: 'tomato',
      name: 'Domates',
      description: '',
      price: 40,
      quantity: 100000,
      category: 'Sebze',
      saleType: 'weighed',
      minimumWeightGrams: 20,
    );

    notifier.addMeasuredToCart(product, 1245);

    expect(notifier.state.cartQuantities['tomato'], 1245);
    expect(notifier.state.total, closeTo(49.80, 0.001));
  });

  test('weighed product rejects values below product minimum', () {
    final notifier = SalesFlowNotifier();
    final product = ProductEntity(
      id: 'cheese',
      name: 'Peynir',
      description: '',
      price: 300,
      quantity: 100000,
      category: 'Şarküteri',
      saleType: 'weighed',
      minimumWeightGrams: 50,
    );

    expect(
      () => notifier.addMeasuredToCart(product, 20),
      throwsArgumentError,
    );
  });

  test('legacy product maps default to piece sales', () {
    final product = ProductEntity.fromMap({
      'id': 'legacy',
      'name': 'Eski Ürün',
      'description': '',
      'price': 10.0,
      'quantity': 5,
      'category': 'Genel',
    });
    expect(product.saleType, 'piece');
    expect(product.isWeighed, isFalse);
  });
}
