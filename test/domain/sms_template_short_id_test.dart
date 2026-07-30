import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/notifications/template_resolver.dart';

void main() {
  test('SMS template variables never expose a long order id', () {
    final vars = SmsTemplateVars.forOrder(
      customerName: 'Ayşe',
      totalAmount: 125,
      orderId: 'order-1782150318456-very-long-reference',
      businessName: 'Serenut',
    );

    expect(vars['id'], startsWith('O-'));
    expect(vars['id']!.length, lessThanOrEqualTo(8));
    expect(vars['id'], isNot(contains('very-long-reference')));
  });

  test('sale and collection ids are shortened consistently', () {
    final sale = SmsTemplateVars.forSale(
      customerName: 'Ali',
      totalAmount: 100,
      paidAmount: 50,
      saleId: 'sale-1782150318456',
      businessName: 'Serenut',
    );
    final collection = SmsTemplateVars.forCollection(
      customerName: 'Ali',
      collectedAmount: 50,
      remainingDebt: 0,
      transactionId: 'trans-1782150318456',
      businessName: 'Serenut',
    );

    expect(sale['id'], 'S-318456');
    expect(collection['id'], 'T-318456');
  });
}
