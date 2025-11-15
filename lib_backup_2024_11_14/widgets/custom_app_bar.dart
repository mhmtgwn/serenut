import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../pages/settings.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showNotifications;
  final bool showSearch;
  final Function(String)? onSearchChanged;
  final String? searchHintText;
  final Color? backgroundColor;
  final Color? textColor;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final List<Widget>? actions;
  final Widget? _buildNotificationBar;
  
  const CustomAppBar({
    super.key,
    required this.title,
    this.showNotifications = false,
    this.showSearch = false,
    this.onSearchChanged,
    this.searchHintText,
    this.backgroundColor,
    this.textColor,
    this.systemOverlayStyle,
    this.actions,
    Widget? buildNotificationBar,
  }) : 
    _buildNotificationBar = buildNotificationBar,
    super();

  IconData _getPageIcon() {
    switch (title) {
      case 'Siparişler':
        return Icons.receipt_long;
      case 'Ürünler':
        return Icons.inventory_2;
      case 'Müşteriler':
        return Icons.people;
      case 'Finans':
        return Icons.account_balance_wallet;
      case 'Daha Fazla':
        return Icons.more_horiz;
      default:
        return Icons.dashboard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final iconColor = isDarkMode ? AppTheme.darkIconColor : AppTheme.lightIconColor;
    final shadowColor = isDarkMode ? AppTheme.darkShadowColor : AppTheme.lightShadowColor;
    final foregroundColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    
    return AppBar(
      backgroundColor: (backgroundColor ?? (isDarkMode ? AppTheme.darkSurfaceColor : AppTheme.lightBackgroundColor)),
      foregroundColor: foregroundColor,
      title: Row(
        children: [
          if (title == 'Kontrol Paneli') ...[
            Icon(Icons.dashboard, color: iconColor),
            const SizedBox(width: 8),
            const Text('Shaman'),
          ] else ...[
            Icon(_getPageIcon(), color: iconColor),
            const SizedBox(width: 8),
            Text(title),
          ],
        ],
      ),
      actions: actions ?? [
        // Settings ikonu (profile yerine)
        IconButton(
          icon: Icon(Icons.settings, color: iconColor),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
          },
        ),
      ],
      elevation: 0,
      shadowColor: shadowColor,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: (backgroundColor ?? (isDarkMode ? AppTheme.darkSurfaceColor : AppTheme.lightBackgroundColor)),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(30),
        child: _buildNotificationBar ?? Container(),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 30);
} 
