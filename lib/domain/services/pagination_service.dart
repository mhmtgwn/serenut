// lib/domain/services/pagination_service.dart

class PaginationService<T> {
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

  PaginationService({
    required Future<List<T>> Function(int offset, int limit, String? searchQuery) dataLoader,
    int pageSize = 20,
  }) : _dataLoader = dataLoader,
       _pageSize = pageSize;

  Future<void> loadFirstPage({String? searchQuery}) async {
    if (_isLoading) return;

    _isLoading = true;
    _currentPage = 0;
    _currentSearchQuery = searchQuery ?? '';
    
    try {
      final newItems = await _dataLoader(0, _pageSize, _currentSearchQuery);
      _items = List<T>.from(newItems);
      _hasMoreData = newItems.length == _pageSize;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMoreData) return;

    _isLoading = true;
    
    try {
      final nextPageIndex = _currentPage + 1;
      final offset = nextPageIndex * _pageSize;
      final newItems = await _dataLoader(offset, _pageSize, _currentSearchQuery);
      
      _currentPage = nextPageIndex;
      _items.addAll(newItems);
      _hasMoreData = newItems.length == _pageSize;
    } finally {
      _isLoading = false;
    }
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
