import 'package:serenutos/domain/models/industry_template.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

const demoCustomerId = 'demo-customer-mehmet-guven';
const demoOrderId = 'demo-order-001';
const demoSaleId = 'demo-sale-001';

class DemoDataSeeder {
  final IProductRepository productRepository;
  final ICustomerRepository customerRepository;
  final IOrderRepository orderRepository;
  final ISaleRepository saleRepository;

  const DemoDataSeeder({
    required this.productRepository,
    required this.customerRepository,
    required this.orderRepository,
    required this.saleRepository,
  });

  Future<void> seed({required String businessType}) async {
    final template = IndustryTemplateRegistry.getTemplate(businessType) ??
        IndustryTemplateRegistry.templates.first;
    final seededProducts = <ProductEntity>[];

    for (var index = 0; index < template.products.length; index++) {
      final source = template.products[index];
      final product = ProductEntity(
        id: source.barcode ?? 'demo-product-${index + 1}',
        name: source.name,
        description: 'Deneme kurulumu örnek ürünü',
        price: source.price,
        purchasePrice: source.price * 0.65,
        quantity: 100,
        minStock: 10,
        category: source.category,
        vat: source.vatRate.round(),
        unit: source.isByWeight ? 'kg' : 'adet',
        saleType: source.isByWeight ? 'weighed' : 'piece',
      );
      seededProducts.add(product);
      if (!await productRepository.exists(product.id)) {
        await productRepository.create(product);
      }
    }

    if (!await customerRepository.exists(demoCustomerId)) {
      await customerRepository.create(CustomerEntity(
        id: demoCustomerId,
        name: 'Mehmet Güven',
        email: '',
        phone: '05380288202',
        balance: 0,
        createdAt: DateTime.now(),
      ));
    }

    final first = seededProducts.first;
    if (!await orderRepository.exists(demoOrderId)) {
      await orderRepository.create(OrderEntity(
        id: demoOrderId,
        customerId: demoCustomerId,
        status: 'created',
        createdAt: DateTime.now(),
        expectedDeliveryDate: DateTime.now().add(const Duration(days: 2)),
        notes: 'Deneme siparişi',
        items: [
          {
            'product_id': first.id,
            'product_name': first.name,
            'quantity': 2.0,
            'unit_price': first.price,
          },
        ],
      ));
    }

    final saleProduct = seededProducts.length > 1 ? seededProducts[1] : first;
    if (!await saleRepository.exists(demoSaleId)) {
      await saleRepository.create(SaleEntity(
        id: demoSaleId,
        customerId: demoCustomerId,
        totalAmount: saleProduct.price,
        paidAmount: saleProduct.price,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        idempotencyKey: 'demo-sale-seed-v1',
        items: [
          {
            'product_id': saleProduct.id,
            'product_name': saleProduct.name,
            'quantity': 1.0,
            'unit_price': saleProduct.price,
          },
        ],
      ));
    }
  }
}
