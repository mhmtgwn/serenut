import 'package:flutter_test/flutter_test.dart';

// Mock veri yükleyici
Future<List<String>> mockDataLoader(int offset, int limit, String? searchQuery) async {
  await Future.delayed(const Duration(milliseconds: 100)); // Simüle edilmiş gecikme
  
  final allData = List.generate(100, (index) => 'Item $index');
  
  // Arama filtresi
  List<String> filteredData = allData;
  if (searchQuery != null && searchQuery.isNotEmpty) {
    filteredData = allData.where((item) => 
      item.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();
  }
  
  // Sayfalama
  final startIndex = offset;
  final endIndex = (startIndex + limit).clamp(0, filteredData.length);
  
  if (startIndex >= filteredData.length) {
    return [];
  }
  
  return filteredData.sublist(startIndex, endIndex);
}

// Basit PaginationService implementasyonu (test için)
class TestPaginationService<T> {
  final Future<List<T>> Function(int offset, int limit, String? searchQuery) _dataLoader;
  final int _pageSize;
  
  List<T> _items = [];
  bool _isLoading = false;
  bool _hasMoreData = true;
  int _currentPage = 0;
  String _currentSearchQuery = '';
  
  // Getters
  List<T> get items => _items;
  bool get isLoading => _isLoading;
  bool get hasMoreData => _hasMoreData;
  int get totalItems => _items.length;
  int get currentPage => _currentPage;
  String get currentSearchQuery => _currentSearchQuery;

  TestPaginationService({
    required Future<List<T>> Function(int offset, int limit, String? searchQuery) dataLoader,
    int pageSize = 20,
  }) : _dataLoader = dataLoader,
       _pageSize = pageSize;

  Future<void> loadFirstPage({String? searchQuery}) async {
    if (_isLoading) return;

    _isLoading = true;
    _currentPage = 0;
    _currentSearchQuery = searchQuery ?? '';
    
    final newItems = await _dataLoader(0, _pageSize, _currentSearchQuery);
    
    _items = newItems;
    _hasMoreData = newItems.length == _pageSize;
    _isLoading = false;
  }

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMoreData) return;

    _isLoading = true;
    _currentPage++;
    
    final offset = _currentPage * _pageSize;
    final newItems = await _dataLoader(offset, _pageSize, _currentSearchQuery);
    
    _items.addAll(newItems);
    _hasMoreData = newItems.length == _pageSize;
    _isLoading = false;
  }

  Future<void> search(String query) async {
    if (_currentSearchQuery == query) return;
    await loadFirstPage(searchQuery: query);
  }

  Future<void> refresh() async {
    _hasMoreData = true;
    await loadFirstPage(searchQuery: _currentSearchQuery);
  }

  void reset() {
    _items.clear();
    _isLoading = false;
    _hasMoreData = true;
    _currentPage = 0;
    _currentSearchQuery = '';
  }

  void addItem(T item) {
    _items.insert(0, item);
  }

  void removeItem(T item) {
    _items.remove(item);
  }
}

void main() {
  group('PaginationService Tests', () {
    late TestPaginationService<String> paginationService;

    setUp(() {
      paginationService = TestPaginationService<String>(
        dataLoader: mockDataLoader,
        pageSize: 10,
      );
    });

    test('should initialize with empty state', () {
      expect(paginationService.items, isEmpty);
      expect(paginationService.isLoading, isFalse);
      expect(paginationService.hasMoreData, isTrue);
      expect(paginationService.currentPage, equals(0));
      expect(paginationService.currentSearchQuery, isEmpty);
    });

    test('should load first page correctly', () async {
      await paginationService.loadFirstPage();
      
      expect(paginationService.items.length, equals(10));
      expect(paginationService.items.first, equals('Item 0'));
      expect(paginationService.items.last, equals('Item 9'));
      expect(paginationService.hasMoreData, isTrue);
      expect(paginationService.currentPage, equals(0));
    });

    test('should load next page correctly', () async {
      await paginationService.loadFirstPage();
      await paginationService.loadNextPage();
      
      expect(paginationService.items.length, equals(20));
      expect(paginationService.items[10], equals('Item 10'));
      expect(paginationService.items.last, equals('Item 19'));
      expect(paginationService.currentPage, equals(1));
    });

    test('should handle search correctly', () async {
      await paginationService.search('Item 1');
      
      expect(paginationService.currentSearchQuery, equals('Item 1'));
      expect(paginationService.items.isNotEmpty, isTrue);
      expect(paginationService.items.every((item) => item.contains('1')), isTrue);
    });

    test('should handle empty search results', () async {
      await paginationService.search('NonExistentItem');
      
      expect(paginationService.items, isEmpty);
      expect(paginationService.hasMoreData, isFalse);
    });

    test('should refresh data correctly', () async {
      await paginationService.loadFirstPage();
      final initialItemCount = paginationService.items.length;
      
      await paginationService.refresh();
      
      expect(paginationService.items.length, equals(initialItemCount));
      expect(paginationService.currentPage, equals(0));
    });

    test('should reset state correctly', () async {
      await paginationService.loadFirstPage();
      await paginationService.search('test');
      
      paginationService.reset();
      
      expect(paginationService.items, isEmpty);
      expect(paginationService.isLoading, isFalse);
      expect(paginationService.hasMoreData, isTrue);
      expect(paginationService.currentPage, equals(0));
      expect(paginationService.currentSearchQuery, isEmpty);
    });

    test('should add item correctly', () async {
      await paginationService.loadFirstPage();
      final initialCount = paginationService.items.length;
      
      paginationService.addItem('New Item');
      
      expect(paginationService.items.length, equals(initialCount + 1));
      expect(paginationService.items.first, equals('New Item'));
    });

    test('should remove item correctly', () async {
      await paginationService.loadFirstPage();
      final itemToRemove = paginationService.items.first;
      final initialCount = paginationService.items.length;
      
      paginationService.removeItem(itemToRemove);
      
      expect(paginationService.items.length, equals(initialCount - 1));
      expect(paginationService.items.contains(itemToRemove), isFalse);
    });

    test('should not load more when no more data', () async {
      // Load all pages
      await paginationService.loadFirstPage();
      while (paginationService.hasMoreData) {
        await paginationService.loadNextPage();
      }
      
      final finalCount = paginationService.items.length;
      await paginationService.loadNextPage();
      
      expect(paginationService.items.length, equals(finalCount));
      expect(paginationService.hasMoreData, isFalse);
    });

    test('should handle concurrent loading correctly', () async {
      // Start multiple load operations
      final future1 = paginationService.loadFirstPage();
      final future2 = paginationService.loadFirstPage();
      
      await Future.wait([future1, future2]);
      
      // Should only load once
      expect(paginationService.items.length, equals(10));
    });
  });

  group('Performance Tests', () {
    test('should load data within reasonable time', () async {
      final paginationService = TestPaginationService<String>(
        dataLoader: mockDataLoader,
        pageSize: 50,
      );
      
      final stopwatch = Stopwatch()..start();
      await paginationService.loadFirstPage();
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(paginationService.items.length, equals(50));
    });

    test('should handle large datasets efficiently', () async {
      final paginationService = TestPaginationService<String>(
        dataLoader: (offset, limit, query) async {
          // Simulate large dataset
          final data = List.generate(limit, (index) => 'Item ${offset + index}');
          await Future.delayed(const Duration(milliseconds: 10));
          return data;
        },
        pageSize: 100,
      );
      
      final stopwatch = Stopwatch()..start();
      
      // Load multiple pages
      await paginationService.loadFirstPage();
      for (int i = 0; i < 5; i++) {
        await paginationService.loadNextPage();
      }
      
      stopwatch.stop();
      
      expect(paginationService.items.length, equals(600));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('Edge Cases', () {
    test('should handle empty data source', () async {
      final emptyPaginationService = TestPaginationService<String>(
        dataLoader: (offset, limit, query) async => [],
        pageSize: 10,
      );
      
      await emptyPaginationService.loadFirstPage();
      
      expect(emptyPaginationService.items, isEmpty);
      expect(emptyPaginationService.hasMoreData, isFalse);
    });

    test('should handle data loader errors gracefully', () async {
      final errorPaginationService = TestPaginationService<String>(
        dataLoader: (offset, limit, query) async {
          throw Exception('Data loading failed');
        },
        pageSize: 10,
      );
      
      expect(() => errorPaginationService.loadFirstPage(), throwsException);
    });

    test('should handle null search query', () async {
      final paginationService = TestPaginationService<String>(
        dataLoader: mockDataLoader,
        pageSize: 10,
      );
      
      await paginationService.search('');
      
      expect(paginationService.currentSearchQuery, isEmpty);
      expect(paginationService.items.isNotEmpty, isTrue);
    });
  });
}
