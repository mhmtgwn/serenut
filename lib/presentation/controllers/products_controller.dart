// lib/presentation/controllers/products_controller.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/domain/services/pagination_service.dart';

import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/audit_provider.dart';

class ProductsController extends AsyncNotifier<List<ProductEntity>> {
  late IProductRepository _repository;
  PaginationService<ProductEntity>? _paginationService;

  @override
  FutureOr<List<ProductEntity>> build() async {
    _repository = await ref.watch(productRepositoryProvider.future);
    _loadCategories();

    final searchQuery = ref.watch(productSearchQueryProvider);
    final selectedCategory = ref.watch(productCategoryFilterProvider);

    _paginationService = PaginationService<ProductEntity>(
      dataLoader: (offset, limit, query) async {
        return _repository.findFiltered(
          searchQuery: query,
          category: selectedCategory,
          offset: offset,
          limit: limit,
        );
      },
      pageSize: 150,
    );

    await _paginationService!.loadFirstPage(searchQuery: searchQuery);
    return _paginationService!.items;
  }

  bool get hasMoreData => _paginationService?.hasMoreData ?? false;
  bool get isLoadingMore => _paginationService?.isLoading ?? false;

  Future<void> _loadCategories() async {
    try {
      final cats = await _repository.getCategories();
      ref.read(productCategoriesStateProvider.notifier).state = cats;
    } catch (_) {}
  }

  Future<void> loadNextPage() async {
    if (_paginationService == null) return;
    if (_paginationService!.isLoading || !_paginationService!.hasMoreData) return;
    try {
      await _paginationService!.loadNextPage();
      state = AsyncValue.data(List.from(_paginationService!.items));
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> addProduct(ProductEntity product) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.create(product);
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logEvent(
          eventType: 'product_created',
          entityType: 'product',
          entityId: product.id,
          newValue: 'Ad: ${product.name}, Fiyat: ₺${product.price}, Miktar: ${product.quantity}',
          notes: 'Yeni ürün eklendi: ${product.name}',
        );
      } catch (_) {}
      ref.read(auditLogServiceProvider).log(
        action: 'product_created',
        details: jsonEncode({
          'id': product.id,
          'name': product.name,
          'price': product.price,
          'quantity': product.quantity,
        }),
      );
      await _loadCategories();
      await _paginationService?.refresh();
      ref.invalidate(salesProductsControllerProvider);
      ref.invalidate(ordersProductsControllerProvider);
      return _paginationService?.items ?? [];
    });
  }

  Future<void> updateProduct(ProductEntity product, {String? oldId}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final original = await _repository.findById(oldId ?? product.id);
      await _repository.update(product, oldId: oldId);
      
      final Map<String, dynamic> changes = {};
      String logAction = 'product_updated';
      
      if (original != null) {
        if (original.price != product.price) {
          changes['price'] = {'old': original.price, 'new': product.price};
          logAction = 'price_changed';
        }
        if (original.quantity != product.quantity) {
          changes['quantity'] = {'old': original.quantity, 'new': product.quantity};
          if (logAction != 'price_changed') logAction = 'stock_adjusted';
        }
        if (original.name != product.name) {
          changes['name'] = {'old': original.name, 'new': product.name};
        }
      }

      try {
        final auditService = await ref.read(auditServiceProvider.future);
        if (original != null && original.price != product.price) {
          await auditService.logPriceChange(product.id, product.name, original.price, product.price);
        } else {
          await auditService.logEvent(
            eventType: logAction,
            entityType: 'product',
            entityId: product.id,
            oldValue: original != null ? 'Ad: ${original.name}, Fiyat: ₺${original.price}, Miktar: ${original.quantity}' : null,
            newValue: 'Ad: ${product.name}, Fiyat: ₺${product.price}, Miktar: ${product.quantity}',
            notes: 'Ürün güncellendi: ${product.name}',
          );
        }
      } catch (_) {}
      
      ref.read(auditLogServiceProvider).log(
        action: logAction,
        details: jsonEncode({
          'id': product.id,
          'old_id': oldId,
          'name': product.name,
          'changes': changes,
        }),
      );
      await _loadCategories();
      await _paginationService?.refresh();
      ref.invalidate(salesProductsControllerProvider);
      ref.invalidate(ordersProductsControllerProvider);
      return _paginationService?.items ?? [];
    });
  }

  Future<void> deleteProduct(String id, {String? approvedByUserId, String? approvedByUserName}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final original = await _repository.findById(id);
      await _repository.delete(id);
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logDelete(
          'product',
          id,
          original?.name ?? 'Bilinmeyen Ürün',
          approvedByUserId: approvedByUserId,
          approvedByUserName: approvedByUserName,
        );
      } catch (_) {}
      ref.read(auditLogServiceProvider).log(
        action: 'product_deleted',
        details: jsonEncode({
          'id': id,
          'name': original?.name ?? 'Bilinmeyen Ürün',
        }),
      );
      await _loadCategories();
      await _paginationService?.refresh();
      ref.invalidate(salesProductsControllerProvider);
      ref.invalidate(ordersProductsControllerProvider);
      return _paginationService?.items ?? [];
    });
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _loadCategories();
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
  }
}

final productsControllerProvider =
    AsyncNotifierProvider<ProductsController, List<ProductEntity>>(() {
  return ProductsController();
});

// Search and Category Filter Providers
final productSearchQueryProvider = StateProvider<String>((ref) => '');
final productCategoryFilterProvider = StateProvider<String?>((ref) => null);

final salesProductSearchQueryProvider = StateProvider<String>((ref) => '');
final salesProductCategoryFilterProvider = StateProvider<String?>((ref) => null);

final ordersProductSearchQueryProvider = StateProvider<String>((ref) => '');
final ordersProductCategoryFilterProvider = StateProvider<String?>((ref) => null);

final productPageProvider = StateProvider<int>((ref) => 1);

// State Provider to hold unique category names loaded from DB
final productCategoriesStateProvider = StateProvider<List<String>>((ref) => []);

// Public category provider pointing to the StateProvider
final productCategoriesProvider = Provider<List<String>>((ref) {
  return ref.watch(productCategoriesStateProvider);
});

final categoryPoolProvider = Provider<List<String>>((ref) {
  const defaultCats = [
    'Gıda', 'İçecek', 'Kuruyemiş', 'Şekerleme', 'Temizlik',
    'Kişisel Bakım', 'Ev & Yaşam', 'Kırtasiye', 'Elektronik',
    'Sigara & Tütün', 'Diğer',
  ];
  final existingCats = ref.watch(productCategoriesProvider);
  final settingsAsync = ref.watch(settingsNotifierProvider);
  final settingsCats = <String>[];
  
  settingsAsync.whenOrNull(
    data: (settings) {
      if (settings.vatCategories.isNotEmpty) {
        try {
          final decoded = jsonDecode(settings.vatCategories);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map && item['name'] != null) {
                settingsCats.add(item['name'].toString());
              }
            }
          }
        } catch (_) {}
      }
    },
  );

  return <String>{
    ...defaultCats,
    ...existingCats,
    ...settingsCats,
  }.where((cat) => cat.trim().isNotEmpty).toList()..sort();
});

// Reactive Filtered Products Provider pointing to productsControllerProvider
final filteredProductsProvider = Provider<AsyncValue<List<ProductEntity>>>((ref) {
  return ref.watch(productsControllerProvider);
});

// Sales-specific products list notifier and provider
class SalesProductsController extends ProductsController {
  @override
  FutureOr<List<ProductEntity>> build() async {
    _repository = await ref.watch(productRepositoryProvider.future);
    _loadCategories();

    final searchQuery = ref.watch(salesProductSearchQueryProvider);
    final selectedCategory = ref.watch(salesProductCategoryFilterProvider);

    _paginationService = PaginationService<ProductEntity>(
      dataLoader: (offset, limit, query) async {
        return _repository.findFiltered(
          searchQuery: query,
          category: selectedCategory,
          offset: offset,
          limit: limit,
        );
      },
      pageSize: 150,
    );

    await _paginationService!.loadFirstPage(searchQuery: searchQuery);
    return _paginationService!.items;
  }
}

final salesProductsControllerProvider =
    AsyncNotifierProvider<SalesProductsController, List<ProductEntity>>(() {
  return SalesProductsController();
});

// Orders-specific products list notifier and provider
class OrdersProductsController extends ProductsController {
  @override
  FutureOr<List<ProductEntity>> build() async {
    _repository = await ref.watch(productRepositoryProvider.future);
    _loadCategories();

    final searchQuery = ref.watch(ordersProductSearchQueryProvider);
    final selectedCategory = ref.watch(ordersProductCategoryFilterProvider);

    _paginationService = PaginationService<ProductEntity>(
      dataLoader: (offset, limit, query) async {
        return _repository.findFiltered(
          searchQuery: query,
          category: selectedCategory,
          offset: offset,
          limit: limit,
        );
      },
      pageSize: 150,
    );

    await _paginationService!.loadFirstPage(searchQuery: searchQuery);
    return _paginationService!.items;
  }
}

final ordersProductsControllerProvider =
    AsyncNotifierProvider<OrdersProductsController, List<ProductEntity>>(() {
  return OrdersProductsController();
});
