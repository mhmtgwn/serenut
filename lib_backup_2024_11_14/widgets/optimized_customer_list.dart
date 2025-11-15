import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/pagination_service.dart';
import '../services/customer_service.dart';
import '../utils/error_handler.dart';

/// Optimize edilmiş müşteri listesi widget'ı
class OptimizedCustomerList extends StatefulWidget {
  final bool isSelectionMode;
  final Function(Map<String, dynamic>)? onCustomerSelected;
  final Function(Map<String, dynamic>)? onCustomerTap;

  const OptimizedCustomerList({
    Key? key,
    this.isSelectionMode = false,
    this.onCustomerSelected,
    this.onCustomerTap,
  }) : super(key: key);

  @override
  State<OptimizedCustomerList> createState() => _OptimizedCustomerListState();
}

class _OptimizedCustomerListState extends State<OptimizedCustomerList>
    with LazyLoadingMixin<OptimizedCustomerList> {
  
  late PaginationService<Map<String, dynamic>> _paginationService;
  final CustomerService _customerService = CustomerService.instance;
  final TextEditingController _searchController = TextEditingController();
  final CacheService<String, List<Map<String, dynamic>>> _cache = CacheService();
  final PerformanceMetrics _metrics = PerformanceMetrics();
  
  String _currentSearchQuery = '';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializePagination();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Pagination servisini başlat
  void _initializePagination() {
    _paginationService = PaginationService<Map<String, dynamic>>(
      dataLoader: _loadCustomers,
      pageSize: 20,
    );
    paginationService = _paginationService;
  }

  /// Müşterileri yükle (sayfalama ile)
  Future<List<Map<String, dynamic>>> _loadCustomers(
    int offset,
    int limit,
    String? searchQuery,
  ) async {
    _metrics.startMeasurement('load_customers');
    
    try {
      // Önbellekten kontrol et
      final cacheKey = 'customers_${offset}_${limit}_${searchQuery ?? ''}';
      final cachedData = _cache.get(cacheKey);
      
      if (cachedData != null) {
        _metrics.endMeasurement('load_customers');
        _metrics.incrementCounter('cache_hits');
        return cachedData;
      }

      // Veritabanından yükle
      List<Map<String, dynamic>> customers;
      
      if (searchQuery != null && searchQuery.isNotEmpty) {
        // Mock arama implementasyonu
        customers = await _customerService.searchCustomers(searchQuery);
        // Sayfalama simülasyonu
        final startIndex = offset;
        final endIndex = (startIndex + limit).clamp(0, customers.length);
        if (startIndex < customers.length) {
          customers = customers.sublist(startIndex, endIndex);
        } else {
          customers = [];
        }
      } else {
        // Mock tüm müşteriler implementasyonu
        customers = await _customerService.getAllCustomers();
        // Sayfalama simülasyonu
        final startIndex = offset;
        final endIndex = (startIndex + limit).clamp(0, customers.length);
        if (startIndex < customers.length) {
          customers = customers.sublist(startIndex, endIndex);
        } else {
          customers = [];
        }
      }

      // Önbelleğe kaydet
      _cache.put(cacheKey, customers);
      _metrics.incrementCounter('database_queries');
      
      return customers;
    } catch (e) {
      ErrorHandler.reportError(
        'Müşteri Yükleme Hatası',
        'Müşteriler yüklenirken bir sorun oluştu.',
        details: e.toString(),
      );
      return [];
    } finally {
      _metrics.endMeasurement('load_customers');
    }
  }

  /// İlk verileri yükle
  Future<void> _loadInitialData() async {
    await _paginationService.loadFirstPage();
    setState(() {
      _isInitialized = true;
    });
  }

  /// Sonraki sayfayı yükle
  @override
  void loadNextPageIfNeeded() {
    if (_paginationService.hasMoreData && !_paginationService.isLoading) {
      _paginationService.loadNextPage().then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  /// Arama yap (debounce ile)
  void _onSearchChanged(String query) {
    DebounceService.debounce(
      'customer_search',
      const Duration(milliseconds: 500),
      () async {
        if (_currentSearchQuery != query) {
          _currentSearchQuery = query;
          _cache.clear(); // Önbelleği temizle
          await _paginationService.search(query);
          if (mounted) {
            setState(() {});
          }
        }
      },
    );
  }

  /// Listeyi yenile
  Future<void> _refreshList() async {
    _cache.clear(); // Önbelleği temizle
    await _paginationService.refresh();
    if (mounted) {
      setState(() {});
    }
  }

  /// Müşteri ekle
  void _addCustomer(Map<String, dynamic> customer) {
    _paginationService.addItem(customer);
    _cache.clear(); // Önbelleği temizle
    setState(() {});
  }

  /// Müşteri güncelle
  void _updateCustomer(Map<String, dynamic> oldCustomer, Map<String, dynamic> newCustomer) {
    _paginationService.updateItem(oldCustomer, newCustomer);
    _cache.clear(); // Önbelleği temizle
    setState(() {});
  }

  /// Müşteri sil
  void _deleteCustomer(Map<String, dynamic> customer) {
    _paginationService.removeItem(customer);
    _cache.clear(); // Önbelleği temizle
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
        // Arama çubuğu
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Müşteri ara...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: _onSearchChanged,
          ),
        ),

        // Performans bilgisi (debug modda)
        if (kDebugMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Toplam: ${_paginationService.totalItems}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Önbellek: ${_cache.getStats()['size']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

        // Müşteri listesi
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshList,
            child: _paginationService.items.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: scrollController,
                    itemCount: _paginationService.items.length + 
                              (_paginationService.hasMoreData ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Loading indicator
                      if (index >= _paginationService.items.length) {
                        return _buildLoadingIndicator();
                      }

                      final customer = _paginationService.items[index];
                      return _buildCustomerItem(customer, index);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// Boş durum widget'ı
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _currentSearchQuery.isNotEmpty
                ? 'Arama sonucu bulunamadı'
                : 'Henüz müşteri eklenmemiş',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          if (_currentSearchQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"$_currentSearchQuery" için sonuç bulunamadı',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Loading indicator widget'ı
  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _paginationService.isLoading
          ? const CircularProgressIndicator()
          : const SizedBox.shrink(),
    );
  }

  /// Müşteri öğesi widget'ı
  Widget _buildCustomerItem(Map<String, dynamic> customer, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor,
          child: Text(
            customer['displayName']?.toString().substring(0, 1).toUpperCase() ?? '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer['displayName']?.toString() ?? 'Bilinmeyen',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (customer['phone'] != null && customer['phone'].toString().isNotEmpty)
              Text('📞 ${customer['phone']}'),
            if (customer['email'] != null && customer['email'].toString().isNotEmpty)
              Text('📧 ${customer['email']}'),
            if (customer['company'] != null && customer['company'].toString().isNotEmpty)
              Text('🏢 ${customer['company']}'),
          ],
        ),
        trailing: widget.isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () => widget.onCustomerSelected?.call(customer),
              )
            : PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(value, customer),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 8),
                        Text('Düzenle'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Sil', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
        onTap: () => widget.onCustomerTap?.call(customer),
      ),
    );
  }

  /// Menü aksiyonlarını işle
  void _handleMenuAction(String action, Map<String, dynamic> customer) {
    switch (action) {
      case 'edit':
        // Düzenleme sayfasına git
        break;
      case 'delete':
        _showDeleteConfirmation(customer);
        break;
    }
  }

  /// Silme onayı göster
  void _showDeleteConfirmation(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Müşteriyi Sil'),
        content: Text(
          '${customer['displayName']} adlı müşteriyi silmek istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              try {
                await _customerService.deleteCustomer(customer['id']);
                _deleteCustomer(customer);
                ErrorHandler.showSuccess('Müşteri silindi');
              } catch (e) {
                ErrorHandler.reportError(
                  'Silme Hatası',
                  'Müşteri silinirken bir sorun oluştu.',
                  details: e.toString(),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
