// test/services/cloud_adaptive_repositories_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/cloud_adaptive_product_repository.dart';
import 'package:serenutos/infrastructure/repositories/cloud_adaptive_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/cloud_adaptive_sale_repository.dart';
import 'package:serenutos/infrastructure/datasources/remote_data_sources.dart';

class MockLocalProductRepository implements IProductRepository {
  bool findByIdCalled = false;
  bool createCalled = false;
  ProductEntity? stubbedProduct;

  @override
  Future<ProductEntity?> findById(id) async {
    findByIdCalled = true;
    return stubbedProduct;
  }

  @override
  Future<int> create(ProductEntity entity) async {
    createCalled = true;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockProductRemoteDS implements ProductRemoteDataSource {
  bool pushProductCalled = false;
  ProductEntity? pushedProduct;

  @override
  Future<void> pushProduct(ProductEntity product) async {
    pushProductCalled = true;
    pushedProduct = product;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CloudAdaptiveProductRepository Tests', () {
    late MockLocalProductRepository localRepo;
    late MockProductRemoteDS remoteDS;
    late CloudAdaptiveProductRepository adaptiveRepo;

    setUp(() {
      localRepo = MockLocalProductRepository();
      remoteDS = MockProductRemoteDS();
      adaptiveRepo = CloudAdaptiveProductRepository(localRepo, remoteDS);
    });

    test('Read delegates to local source', () async {
      final product = ProductEntity(
        id: 'p1',
        name: 'Apple',
        description: 'Red',
        price: 1.0,
        quantity: 10,
        category: 'Food',
      );
      localRepo.stubbedProduct = product;

      final res = await adaptiveRepo.findById('p1');
      expect(res, product);
      expect(localRepo.findByIdCalled, true);
    });

    test('Write writes locally and pushes to remote', () async {
      final product = ProductEntity(
        id: 'p1',
        name: 'Apple',
        description: 'Red',
        price: 1.0,
        quantity: 10,
        category: 'Food',
      );

      final res = await adaptiveRepo.create(product);
      expect(res, 1);
      expect(localRepo.createCalled, true);
      expect(remoteDS.pushProductCalled, true);
      expect(remoteDS.pushedProduct, product);
    });
  });
}
