// lib/infrastructure/datasources/remote_data_sources.dart
// Serenut Platform — Remote Data Source Interfaces and Mock Implementations
// Decoupled remote data logic using ApiClient, ready for Faz 2 VPS integration.
// Created: 04 Jul 2026

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

// ── Product Remote Data Source ───────────────────────────────────────────────
abstract class ProductRemoteDataSource {
  Future<List<ProductEntity>> fetchProducts({int? sinceTimestamp});
  Future<void> pushProduct(ProductEntity product);
}

class CloudProductRemoteDataSource implements ProductRemoteDataSource {
  final ApiClient _apiClient;

  CloudProductRemoteDataSource(this._apiClient);

  @override
  Future<List<ProductEntity>> fetchProducts({int? sinceTimestamp}) async {
    // Under the hood, this will call the client path
    final response = await _apiClient.get('/products?since=${sinceTimestamp ?? 0}');
    if (response.isSuccess) {
      final List<dynamic> list = response.json['products'] as List<dynamic>;
      return list.map((item) => ProductEntity(
        id: item['id'] as String,
        name: item['name'] as String,
        description: item['description'] as String? ?? '',
        price: (item['price'] as num).toDouble(),
        quantity: (item['quantity'] as num).toInt(),
        category: item['category'] as String,
        vat: item['vat'] != null ? (item['vat'] as num).toInt() : null,
      )).toList();
    }
    return [];
  }

  @override
  Future<void> pushProduct(ProductEntity product) async {
    await _apiClient.post('/products', {
      'id': product.id,
      'name': product.name,
      'description': product.description,
      'price': product.price,
      'quantity': product.quantity,
      'category': product.category,
      'vat': product.vat,
    });
  }
}

// ── Customer Remote Data Source ──────────────────────────────────────────────
abstract class CustomerRemoteDataSource {
  Future<List<CustomerEntity>> fetchCustomers({int? sinceTimestamp});
  Future<void> pushCustomer(CustomerEntity customer);
}

class CloudCustomerRemoteDataSource implements CustomerRemoteDataSource {
  final ApiClient _apiClient;

  CloudCustomerRemoteDataSource(this._apiClient);

  @override
  Future<List<CustomerEntity>> fetchCustomers({int? sinceTimestamp}) async {
    final response = await _apiClient.get('/customers?since=${sinceTimestamp ?? 0}');
    if (response.isSuccess) {
      final List<dynamic> list = response.json['customers'] as List<dynamic>;
      return list.map((item) => CustomerEntity(
        id: item['id'] as String,
        name: item['name'] as String,
        email: item['email'] as String? ?? '',
        phone: item['phone'] as String? ?? '',
        balance: (item['balance'] as num).toDouble(),
        createdAt: DateTime.parse(item['created_at'] as String),
      )).toList();
    }
    return [];
  }

  @override
  Future<void> pushCustomer(CustomerEntity customer) async {
    await _apiClient.post('/customers', {
      'id': customer.id,
      'name': customer.name,
      'email': customer.email,
      'phone': customer.phone,
      'balance': customer.balance,
      'created_at': customer.createdAt.toIso8601String(),
    });
  }
}

// ── Sales Remote Data Source ─────────────────────────────────────────────────
abstract class SalesRemoteDataSource {
  Future<List<SaleEntity>> fetchSales({int? sinceTimestamp});
  Future<void> pushSale(SaleEntity sale);
}

class CloudSalesRemoteDataSource implements SalesRemoteDataSource {
  final ApiClient _apiClient;

  CloudSalesRemoteDataSource(this._apiClient);

  @override
  Future<List<SaleEntity>> fetchSales({int? sinceTimestamp}) async {
    final response = await _apiClient.get('/sales?since=${sinceTimestamp ?? 0}');
    if (response.isSuccess) {
      final List<dynamic> list = response.json['sales'] as List<dynamic>;
      return list.map<SaleEntity>((item) => SaleEntity(
        id: item['id'] as String,
        customerId: item['customer_id'] as String,
        paymentMethod: item['payment_method'] as String,
        totalAmount: (item['total_amount'] as num).toDouble(),
        paidAmount: (item['paid_amount'] as num).toDouble(),
        status: item['status'] as String? ?? 'completed',
        createdAt: DateTime.parse(item['created_at'] as String),
        items: List<Map<String, dynamic>>.from(item['items'] as List),
      )).toList();
    }
    return [];
  }

  @override
  Future<void> pushSale(SaleEntity sale) async {
    String serverPaymentMethod = sale.paymentMethod;
    if (serverPaymentMethod == 'debt') {
      serverPaymentMethod = 'credit';
    } else if (serverPaymentMethod == 'karma' || serverPaymentMethod == 'mixed') {
      serverPaymentMethod = 'cash';
    } else if (!['cash', 'card', 'credit'].contains(serverPaymentMethod)) {
      serverPaymentMethod = 'cash';
    }

    await _apiClient.post('/sales', {
      'id': sale.id,
      'customer_id': sale.customerId,
      'payment_method': serverPaymentMethod,
      'total_amount': sale.totalAmount,
      'paid_amount': sale.paidAmount,
      'created_at': sale.createdAt.toIso8601String(),
      'items': sale.items,
    });
  }
}

