import '../models/customer.dart';
import '../models/product.dart';
import '../services/customer_service.dart';
import '../services/product_service.dart';

class SeedData {
  static Future<void> seedIfEmpty() async {
    final customerService = CustomerService();
    final productService = ProductService();

    // Müşteri kontrolü
    final customers = await customerService.getAll();
    if (customers.isEmpty) {
      await _seedCustomers(customerService);
    }

    // Ürün kontrolü
    final products = await productService.getAll();
    if (products.isEmpty) {
      await _seedProducts(productService);
    }
  }

  static Future<void> _seedCustomers(CustomerService service) async {
    final customers = [
      Customer(
        name: 'Ahmet Yılmaz',
        phone: '05551234567',
        address: 'Atatürk Cad. No:123 Kadıköy/İstanbul',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Customer(
        name: 'Ayşe Demir',
        phone: '05559876543',
        address: 'İstiklal Cad. No:45 Beyoğlu/İstanbul',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Customer(
        name: 'Mehmet Kaya',
        phone: '05551112233',
        address: 'Cumhuriyet Mah. No:67 Şişli/İstanbul',
        createdAt: DateTime.now().toIso8601String(),
      ),
    ];

    for (var customer in customers) {
      await service.add(customer);
    }
  }

  static Future<void> _seedProducts(ProductService service) async {
    final products = [
      // Yiyecekler
      Product(
        name: 'Hamburger',
        price: 45.00,
        stock: 50,
        category: 'Yiyecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Pizza',
        price: 65.00,
        stock: 30,
        category: 'Yiyecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Lahmacun',
        price: 25.00,
        stock: 100,
        category: 'Yiyecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Döner',
        price: 55.00,
        stock: 40,
        category: 'Yiyecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Pide',
        price: 50.00,
        stock: 35,
        category: 'Yiyecek',
        createdAt: DateTime.now().toIso8601String(),
      ),

      // İçecekler
      Product(
        name: 'Kola',
        price: 15.00,
        stock: 200,
        category: 'İçecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Ayran',
        price: 10.00,
        stock: 150,
        category: 'İçecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Su',
        price: 5.00,
        stock: 300,
        category: 'İçecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Çay',
        price: 8.00,
        stock: 100,
        category: 'İçecek',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Kahve',
        price: 20.00,
        stock: 80,
        category: 'İçecek',
        createdAt: DateTime.now().toIso8601String(),
      ),

      // Tatlılar
      Product(
        name: 'Baklava',
        price: 35.00,
        stock: 25,
        category: 'Tatlı',
        createdAt: DateTime.now().toIso8601String(),
      ),
      Product(
        name: 'Künefe',
        price: 40.00,
        stock: 20,
        category: 'Tatlı',
        createdAt: DateTime.now().toIso8601String(),
      ),
    ];

    for (var product in products) {
      await service.add(product);
    }
  }
}
