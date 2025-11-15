import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode;
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeProvider(this._isDarkMode) {
    _loadThemePreference();
  }
  
  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _themeMode;
  
  ThemeData get currentTheme => _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme;
  
  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('theme_mode') ?? 'Sistem';
    
    switch (themeModeString) {
      case 'Açık':
        _themeMode = ThemeMode.light;
        _isDarkMode = false;
        break;
      case 'Koyu':
        _themeMode = ThemeMode.dark;
        _isDarkMode = true;
        break;
      case 'Sistem':
      default:
        _themeMode = ThemeMode.system;
        _isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
        break;
    }
    
    notifyListeners();
  }
  
  void toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    
    // Tema tercihini kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDarkMode);
    
    // Tema modunu da güncelle
    if (_isDarkMode) {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }
    
    await prefs.setString('theme_mode', _getThemeModeString());
    
    notifyListeners();
  }
  
  String _getThemeModeString() {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'Açık';
      case ThemeMode.dark:
        return 'Koyu';
      case ThemeMode.system:
        return 'Sistem';
    }
  }
  
  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    
    // Sistem teması kullanılıyorsa, sistem ayarlarına göre karanlık/açık mod belirle
    if (mode == ThemeMode.system) {
      _isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    } else {
      _isDarkMode = mode == ThemeMode.dark;
    }
    
    // Tema tercihini kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDarkMode);
    await prefs.setString('theme_mode', _getThemeModeString());
    
    notifyListeners();
  }
} 
