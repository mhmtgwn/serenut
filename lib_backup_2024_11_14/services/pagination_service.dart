import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/error_handler.dart';

/// Sayfalama ve lazy loading servisi
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

  /// İlk sayfayı yükle
  Future<void> loadFirstPage({String? searchQuery}) async {
    if (_isLoading) return;

    try {
      _isLoading = true;
      _currentPage = 0;
      _currentSearchQuery = searchQuery ?? '';
      
      final newItems = await _dataLoader(0, _pageSize, _currentSearchQuery);
      
      _items = newItems;
      _hasMoreData = newItems.length == _pageSize;
      
      debugPrint('İlk sayfa yüklendi: ${newItems.length} öğe');
    } catch (e) {
      ErrorHandler.reportError(
        'Veri Yükleme Hatası',
        'İlk sayfa yüklenirken bir sorun oluştu.',
        details: e.toString(),
      );
    } finally {
      _isLoading = false;
    }
  }

  /// Sonraki sayfayı yükle
  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMoreData) return;

    try {
      _isLoading = true;
      _currentPage++;
      
      final offset = _currentPage * _pageSize;
      final newItems = await _dataLoader(offset, _pageSize, _currentSearchQuery);
      
      _items.addAll(newItems);
      _hasMoreData = newItems.length == _pageSize;
      
      debugPrint('Sonraki sayfa yüklendi: ${newItems.length} öğe (Toplam: ${_items.length})');
    } catch (e) {
      _currentPage--; // Hata durumunda sayfa numarasını geri al
      ErrorHandler.reportError(
        'Veri Yükleme Hatası',
        'Sonraki sayfa yüklenirken bir sorun oluştu.',
        details: e.toString(),
      );
    } finally {
      _isLoading = false;
    }
  }

  /// Arama yap
  Future<void> search(String query) async {
    if (_currentSearchQuery == query) return;

    await loadFirstPage(searchQuery: query);
  }

  /// Verileri yenile
  Future<void> refresh() async {
    _hasMoreData = true;
    await loadFirstPage(searchQuery: _currentSearchQuery);
  }

  /// Servisi sıfırla
  void reset() {
    _items.clear();
    _isLoading = false;
    _hasMoreData = true;
    _currentPage = 0;
    _currentSearchQuery = '';
  }

  /// Belirli bir öğeyi ekle
  void addItem(T item) {
    _items.insert(0, item); // Başa ekle
  }

  /// Belirli bir öğeyi güncelle
  void updateItem(T oldItem, T newItem) {
    final index = _items.indexOf(oldItem);
    if (index != -1) {
      _items[index] = newItem;
    }
  }

  /// Belirli bir öğeyi sil
  void removeItem(T item) {
    _items.remove(item);
  }

  /// Öğeyi ID ile bul ve güncelle
  void updateItemById(bool Function(T) predicate, T newItem) {
    final index = _items.indexWhere(predicate);
    if (index != -1) {
      _items[index] = newItem;
    }
  }

  /// Öğeyi ID ile bul ve sil
  void removeItemById(bool Function(T) predicate) {
    _items.removeWhere(predicate);
  }
}

/// Lazy loading widget'ı için mixin
mixin LazyLoadingMixin<T extends StatefulWidget> on State<T> {
  late ScrollController scrollController;
  late PaginationService paginationService;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
    scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }

  /// Scroll dinleyicisi
  void _onScroll() {
    if (scrollController.position.pixels >= 
        scrollController.position.maxScrollExtent - 200) {
      // Sayfanın sonuna yaklaşıldığında sonraki sayfayı yükle
      loadNextPageIfNeeded();
    }
  }

  /// Sonraki sayfayı yükle (alt sınıflar tarafından implement edilmeli)
  void loadNextPageIfNeeded();
}

/// Performans metrikleri servisi
class PerformanceMetrics {
  static final PerformanceMetrics _instance = PerformanceMetrics._internal();
  factory PerformanceMetrics() => _instance;
  PerformanceMetrics._internal();

  final Map<String, DateTime> _startTimes = {};
  final Map<String, Duration> _durations = {};
  final Map<String, int> _counters = {};

  /// Performans ölçümünü başlat
  void startMeasurement(String key) {
    _startTimes[key] = DateTime.now();
  }

  /// Performans ölçümünü bitir
  void endMeasurement(String key) {
    final startTime = _startTimes[key];
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      _durations[key] = duration;
      _startTimes.remove(key);
      
      debugPrint('⏱️ $key: ${duration.inMilliseconds}ms');
    }
  }

  /// Sayaç artır
  void incrementCounter(String key) {
    _counters[key] = (_counters[key] ?? 0) + 1;
  }

  /// Performans raporunu al
  Map<String, dynamic> getReport() {
    return {
      'durations': _durations.map((key, value) => MapEntry(key, value.inMilliseconds)),
      'counters': Map.from(_counters),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Metrikleri temizle
  void clear() {
    _startTimes.clear();
    _durations.clear();
    _counters.clear();
  }

  /// Ortalama süreyi hesapla
  double getAverageDuration(String key) {
    final duration = _durations[key];
    final count = _counters[key];
    
    if (duration != null && count != null && count > 0) {
      return duration.inMilliseconds / count;
    }
    
    return 0.0;
  }
}

/// Önbellek servisi
class CacheService<K, V> {
  final Map<K, V> _cache = {};
  final Map<K, DateTime> _timestamps = {};
  final Duration _maxAge;
  final int _maxSize;

  CacheService({
    Duration maxAge = const Duration(minutes: 10),
    int maxSize = 100,
  }) : _maxAge = maxAge,
       _maxSize = maxSize;

  /// Önbelleğe veri ekle
  void put(K key, V value) {
    // Önbellek boyutu kontrolü
    if (_cache.length >= _maxSize) {
      _evictOldest();
    }

    _cache[key] = value;
    _timestamps[key] = DateTime.now();
  }

  /// Önbellekten veri al
  V? get(K key) {
    final timestamp = _timestamps[key];
    
    if (timestamp == null) {
      return null;
    }

    // Yaş kontrolü
    if (DateTime.now().difference(timestamp) > _maxAge) {
      remove(key);
      return null;
    }

    return _cache[key];
  }

  /// Önbellekten veri sil
  void remove(K key) {
    _cache.remove(key);
    _timestamps.remove(key);
  }

  /// Önbelleği temizle
  void clear() {
    _cache.clear();
    _timestamps.clear();
  }

  /// En eski öğeyi çıkar
  void _evictOldest() {
    if (_timestamps.isEmpty) return;

    K? oldestKey;
    DateTime? oldestTime;

    for (final entry in _timestamps.entries) {
      if (oldestTime == null || entry.value.isBefore(oldestTime)) {
        oldestKey = entry.key;
        oldestTime = entry.value;
      }
    }

    if (oldestKey != null) {
      remove(oldestKey);
    }
  }

  /// Önbellek istatistikleri
  Map<String, dynamic> getStats() {
    return {
      'size': _cache.length,
      'max_size': _maxSize,
      'max_age_minutes': _maxAge.inMinutes,
      'oldest_entry': _timestamps.values.isEmpty 
          ? null 
          : _timestamps.values.reduce((a, b) => a.isBefore(b) ? a : b).toIso8601String(),
    };
  }
}

/// Debounce servisi (arama için)
class DebounceService {
  static final Map<String, Timer?> _timers = {};

  /// Debounce işlemi
  static void debounce(
    String key,
    Duration delay,
    VoidCallback callback,
  ) {
    _timers[key]?.cancel();
    _timers[key] = Timer(delay, callback);
  }

  /// Tüm timer'ları iptal et
  static void cancelAll() {
    for (final timer in _timers.values) {
      timer?.cancel();
    }
    _timers.clear();
  }

  /// Belirli bir timer'ı iptal et
  static void cancel(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }
}

