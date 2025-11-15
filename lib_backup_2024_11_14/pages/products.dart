import 'package:flutter/material.dart';
import '../widgets/add_product_form.dart';
import '../widgets/edit_product_form.dart';
import '../services/product_service.dart';
import 'dart:io';
import '../utils/notification_service.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
// Removed unnecessary import: dart:ui

class ProductsPage extends StatelessWidget {
  final bool isSelectionMode;
  final Function(Map<String, dynamic>)? onProductSelected;

  const ProductsPage({
    super.key, 
    this.isSelectionMode = false,
    this.onProductSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isSelectionMode ? 'Ürün Seç' : 'Ürünler'),
        actions: [
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
      body: ProductsContent(
        isSelectionMode: isSelectionMode,
        onProductSelected: onProductSelected,
      ),
    );
  }
}

class ProductsContent extends StatefulWidget {
  final bool isSelectionMode;
  final Function(Map<String, dynamic>)? onProductSelected;

  const ProductsContent({
    super.key, 
    this.isSelectionMode = false,
    this.onProductSelected,
  });
  @override
  State<ProductsContent> createState() => ProductsContentState();
}

class ProductsContentState extends State<ProductsContent> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  bool _isLoading = true;
  final bool _hasError = false;
  String _sortBy = 'name'; // Varsayılan sıralama
  bool _sortAscending = true; // Artan sıralama

  // Public erişim için getter
  TextEditingController get searchController => _searchController;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    
    // Arama kontrolcüsü değişiklikleri dinleme
    _searchController.addListener(() {
      _updateSearchQuery(_searchController.text);
    });
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    
    try {
      setState(() {
        _isLoading = true;
      });
      
      final products = await ProductService.instance.getAllProducts();
      
      if (!mounted) return;
      
      setState(() {
        _products = products;
        _isLoading = false;
        _applyFiltersAndSort();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        NotificationService.instance.showError(
          context,
          'Ürünler yüklenirken bir hata oluştu: ${e.toString()}',
        );
      }
    }
  }

  void _applyFiltersAndSort({String? searchQuery}) {
    if (searchQuery != null) {
      _searchQuery = searchQuery;
    }
    
    _filteredProducts = _products.where((product) {
      final name = product['name'].toString().toLowerCase();
      final code = product['code']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      return name.contains(searchLower) || code.contains(searchLower);
    }).toList();
    
    // Sıralama uygula
    _filteredProducts.sort((a, b) {
      if (_sortBy == 'name') {
        return _sortAscending
            ? a['name'].toString().compareTo(b['name'].toString())
            : b['name'].toString().compareTo(a['name'].toString());
      } else if (_sortBy == 'price') {
        final priceA = a['sellingPrice'] ?? 0.0;
        final priceB = b['sellingPrice'] ?? 0.0;
        return _sortAscending ? priceA.compareTo(priceB) : priceB.compareTo(priceA);
      } else if (_sortBy == 'stock') {
        final stockA = a['stock'] ?? 0;
        final stockB = b['stock'] ?? 0;
        return _sortAscending ? stockA.compareTo(stockB) : stockB.compareTo(stockA);
      }
      return 0;
    });
    
    setState(() {});
  }

  void _updateSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
      _applyFiltersAndSort(searchQuery: query);
    });
  }

  void _changeSortBy(String sortBy) {
    setState(() {
      _sortBy = sortBy;
      _applyFiltersAndSort();
    });
  }

  void _showSortFilterDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? AppTheme.darkCardColor : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Başlık
                  Row(
                    children: [
                      Icon(
                        Icons.filter_list,
                        color: AppTheme.primaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Sıralama ve Filtreleme',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Sıralama Kriteri
                  Text(
                    'Sıralama Kriteri:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildSortFilterChip(
                        value: 'name',
                        label: 'İsim',
                        isSelected: _sortBy == 'name',
                        onSortSelected: (value) {
                          setModalState(() {
                            _changeSortBy(value);
                          });
                        },
                      ),
                      _buildSortFilterChip(
                        value: 'price',
                        label: 'Fiyat',
                        isSelected: _sortBy == 'price',
                        onSortSelected: (value) {
                          setModalState(() {
                            _changeSortBy(value);
                          });
                        },
                      ),
                      _buildSortFilterChip(
                        value: 'stock',
                        label: 'Stok',
                        isSelected: _sortBy == 'stock',
                        onSortSelected: (value) {
                          setModalState(() {
                            _changeSortBy(value);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Sıralama Yönü
                  Text(
                    'Sıralama Yönü:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildSortDirectionChip(
                        label: 'Artan',
                        isSelected: _sortAscending,
                        isAscending: true,
                      ),
                      const SizedBox(width: 12),
                      _buildSortDirectionChip(
                        label: 'Azalan',
                        isSelected: !_sortAscending,
                        isAscending: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Uygula butonu
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _applyFiltersAndSort();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Uygula',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortFilterChip({
    required String value,
    required String label,
    required bool isSelected,
    required Function(String) onSortSelected,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _changeSortBy(value);
        });
      },
      showCheckmark: false,
      selectedColor: AppTheme.primaryColor.withAlpha(13005),
      backgroundColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
      labelStyle: TextStyle(
        color: isSelected
            ? AppTheme.primaryColor
            : (isDarkMode ? Colors.white : Colors.black87),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      side: BorderSide(
        color: isSelected
            ? AppTheme.primaryColor
            : Colors.transparent,
      ),
    );
  }
  
  Widget _buildSortDirectionChip({
    required String label,
    required bool isSelected,
    required bool isAscending,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _sortAscending = isAscending;
            _applyFiltersAndSort();
          });
        }
      },
      showCheckmark: false,
      selectedColor: AppTheme.primaryColor.withAlpha(13005),
      backgroundColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
      labelStyle: TextStyle(
        color: isSelected
            ? AppTheme.primaryColor
            : (isDarkMode ? Colors.white : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      side: BorderSide(
        color: isSelected
            ? AppTheme.primaryColor
            : Colors.transparent,
      ),
    );
  }

  Future<void> _deleteProduct(int id) async {
    try {
      await ProductService.instance.deleteProduct(id);
      if (mounted) {
        NotificationService.instance.showSuccess(
          context,
          'Ürün başarıyla silindi',
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationService.instance.showError(
          context,
          'Ürün silinirken hata oluştu: ${e.toString()}',
        );
      }
    }
  }

  void _showDeleteConfirmation(int id, String productName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text('"$productName" ürününü silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteProduct(id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  void _showEditProductForm(Map<String, dynamic> product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => EditProductForm(
          product: product,
          onProductUpdated: () {
            _loadProducts();
          },
        ),
      ),
    );
  }

  void _showAddProductDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => AddProductForm(
          onProductAdded: () {
            _loadProducts();
          },
        ),
      ),
    );
  }

  void _showOptions(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Düzenle'),
            onTap: () {
              Navigator.pop(context);
              _showEditProductForm(product);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Sil', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirmation(product['id'], product['name']);
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeProvider>(context);
    return Scaffold(
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _hasError 
          ? const Center(child: Text('Bir hata oluştu!')) 
          : _buildProductList(),
      // NavBar'da ekle butonu olduğu için FloatingActionButton kaldırıldı
    );
  }

  Widget _buildProductList() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return Stack(
      children: [
        // Ürün listesi
        _filteredProducts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 64,
                      color: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Henüz ürün eklenmemiş',
                      style: TextStyle(
                        fontSize: 18,
                        color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16), // Alt kısımda boşluk bırak
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  final product = _filteredProducts[index];
                  return _buildProductCard(product);
                },
              ),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final subtitleColor = isDarkMode ? AppTheme.darkSecondaryTextColor : AppTheme.lightSecondaryTextColor;
    final detailColor = isDarkMode ? Colors.grey.shade400 : Colors.grey;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: widget.isSelectionMode
            ? () {
                if (widget.onProductSelected != null) {
                  widget.onProductSelected!(product);
                } else {
                  Navigator.of(context).pop(product);
                }
              }
            : () => _showOptions(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Ürün resmi
              CircleAvatar(
                radius: 24,
                backgroundColor: isDarkMode ? AppTheme.darkCardColor : const Color(0xFFF5F5F5),
                backgroundImage: product['imagePath'] != null
                    ? FileImage(File(product['imagePath']))
                    : null,
                child: product['imagePath'] == null
                    ? Icon(
                        Icons.inventory_2_outlined,
                        color: isDarkMode ? Colors.white70 : Colors.grey,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              // Ürün bilgileri
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${product['price'] ?? '0'} TL',
                      style: TextStyle(
                        fontSize: 14,
                        color: subtitleColor,
                      ),
                    ),
                    Text(
                      'Stok: ${product['stock'] ?? '0'} ${product['unit'] ?? ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: detailColor,
                      ),
                    ),
                  ],
                ),
              ),
              // Seçim ikonu veya düzenleme ikonu
              widget.isSelectionMode
                  ? Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.primaryColor,
                    )
                  : Icon(
                      Icons.more_vert,
                      color: isDarkMode ? Colors.white70 : Colors.grey,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // Public erişim için metotlar
  void applyFiltersAndSort({String? searchQuery}) {
    _applyFiltersAndSort(searchQuery: searchQuery);
  }

  void showAddProductDialog() {
    _showAddProductDialog();
  }

  void showSortFilterDialog() {
    _showSortFilterDialog();
  }
} 
