import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/constants/app_theme.dart';
import '../../shared/constants/theme_provider.dart';

class CustomBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final TextEditingController? searchController;
  final Function(String)? onSearchChanged;
  final VoidCallback? onScanPressed;
  final VoidCallback? onAddPressed;
  final VoidCallback? onSyncPressed;
  final VoidCallback? onFilterPressed;
  final String? searchHintText;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.searchController,
    this.onSearchChanged,
    this.onScanPressed,
    this.onAddPressed,
    this.onSyncPressed,
    this.onFilterPressed,
    this.searchHintText,
  });

  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav> {
  // Arama kutusunun görünürlüğünü kontrol etmek için
  bool _isSearchVisible = false;
  
  @override
  void initState() {
    super.initState();
    // Ana sayfa dışındaki sayfalarda arama kutusunu göster
    _isSearchVisible = widget.currentIndex > 0;
  }
  
  @override
  void didUpdateWidget(CustomBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sayfa değiştiğinde arama kutusunun görünürlüğünü güncelle
    if (oldWidget.currentIndex != widget.currentIndex) {
      setState(() {
        _isSearchVisible = widget.currentIndex > 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    // Tema renklerini kullan
    final backgroundColor = isDarkMode 
        ? AppTheme.darkSurfaceColor  // Koyu tema için tam siyah
        : AppTheme.lightBackgroundColor; // Açık tema için beyaz
    
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: const [], // Gölgeleri kaldır
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Arama kutusu ve butonlar
          if (_isSearchVisible) // Ana sayfa hariç diğer sayfalarda göster
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  // Sol buton (Barkod, Filtre veya Senkronizasyon)
                  if (_getActionCallback() != null)
                    _buildActionButton(
                      icon: _getActionIcon(),
                      onPressed: _getActionCallback(),
                      tooltip: _getActionTooltip(),
                      isDarkMode: isDarkMode,
                      margin: const EdgeInsets.only(right: 8),
                    ),
                  
                  // Arama kutusu
                  Expanded(
                    child: _buildSearchBar(context),
                  ),
                  
                  // Sağ buton (Ekleme)
                  if (widget.onAddPressed != null)
                    _buildActionButton(
                      icon: Icons.add,
                      onPressed: widget.onAddPressed,
                      tooltip: 'Ekle',
                      isDarkMode: isDarkMode,
                      margin: const EdgeInsets.only(left: 8),
                    ),
                ],
              ),
            ),
          
          // Bottom Navigation Bar
          Container(
            color: backgroundColor,
            child: BottomNavigationBar(
              currentIndex: widget.currentIndex,
              onTap: widget.onTap,
              type: BottomNavigationBarType.fixed,
              backgroundColor: backgroundColor,
              selectedItemColor: AppTheme.primaryColor, // Tema yeşil rengi
              unselectedItemColor: isDarkMode 
                  ? AppTheme.darkSecondaryTextColor 
                  : AppTheme.lightSecondaryTextColor,
              showSelectedLabels: true,
              showUnselectedLabels: true,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              elevation: 0,
              items: [
                _buildNavItem(Icons.home_outlined, Icons.home, 'Ana Sayfa', 0),
                _buildNavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Siparişler', 1),
                _buildNavItem(Icons.inventory_outlined, Icons.inventory, 'Ürünler', 2),
                _buildNavItem(Icons.people_outline, Icons.people, 'Müşteriler', 3),
                _buildNavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Finans', 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Sayfa indeksine göre sol buton ikonunu belirle
  IconData _getActionIcon() {
    switch (widget.currentIndex) {
      case 1:
        return Icons.qr_code_scanner;
      case 2:
        return Icons.filter_list;
      case 3:
        return Icons.sync;
      default:
        return Icons.search;
    }
  }

  // Sayfa indeksine göre sol buton callback'ini belirle
  VoidCallback? _getActionCallback() {
    switch (widget.currentIndex) {
      case 1:
        return widget.onScanPressed;
      case 2:
        return widget.onFilterPressed;
      case 3:
        return widget.onSyncPressed;
      default:
        return null;
    }
  }

  // Sayfa indeksine göre sol buton tooltip'ini belirle
  String _getActionTooltip() {
    switch (widget.currentIndex) {
      case 1:
        return 'Barkod Tara';
      case 2:
        return 'Filtrele';
      case 3:
        return 'Rehberi Senkronize Et';
      default:
        return '';
    }
  }

  // Buton widget'ı oluştur
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required bool isDarkMode,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    if (onPressed == null) return const SizedBox.shrink();
    
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor, // Tema yeşil rengi
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF424242) : Colors.transparent,
          width: 1,
        ),
        boxShadow: const [], // Gölgeleri kaldır
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                color: AppTheme.lightTextColor, // Tema beyaz rengi
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode 
        ? const Color(0xFF1E1E1E) 
        : Colors.white;
    final borderColor = isDarkMode 
        ? const Color(0xFF3A3A3A) 
        : const Color(0xFFE0E0E0);
    
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        onChanged: widget.onSearchChanged,
        decoration: InputDecoration(
          hintText: widget.searchHintText ?? 'Ara...',
          prefixIcon: Icon(Icons.search, color: textColor.withAlpha(179)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: TextStyle(color: textColor.withAlpha(128)),
        ),
        style: TextStyle(color: textColor),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(IconData unselectedIcon, IconData selectedIcon, String label, int index) {
    return BottomNavigationBarItem(
      icon: Icon(widget.currentIndex == index ? selectedIcon : unselectedIcon),
      label: label,
    );
  }
} 
