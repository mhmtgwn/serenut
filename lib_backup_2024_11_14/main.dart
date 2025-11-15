import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'pages/home.dart';
import 'settings/receipt_label_designer.dart';
import 'pages/profile_settings.dart';
import 'utils/error_handler.dart';
import 'services/database_service.dart';
import 'services/default_printer_setup.dart';

// NavigatorKey'i burada tanımlıyorum
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Flutter bağlamlarını başlat
  WidgetsFlutterBinding.ensureInitialized();
  
  // Merkezi hata yönetimi sistemini başlat
  ErrorHandler.setNavigatorKey(navigatorKey);
  ErrorHandler.initialize();
  
  // Veritabanını önceden başlat (performans için)
  try {
    await DatabaseService.instance.database;
    debugPrint('Veritabanı başarıyla başlatıldı');
    
    // Varsayılan yazıcıları kur
    await DefaultPrinterSetup().setupDefaultPrinters();
    debugPrint('Varsayılan yazıcılar kuruldu');
  } catch (e) {
    debugPrint('Veritabanı başlatma hatası: $e');
  }
  
  // Tema tercihlerini yükle
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('is_dark_mode') ?? false;
  
  // Uygulamayı başlat
  runApp(MyApp(isDarkMode: isDarkMode));
}

class MyApp extends StatefulWidget {
  final bool isDarkMode;
  
  const MyApp({
    Key? key,
    required this.isDarkMode,
  }) : super(key: key);
  
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ThemeProvider _themeProvider;
  
  @override
  void initState() {
    super.initState();
    _themeProvider = ThemeProvider(widget.isDarkMode);
  }
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _themeProvider,
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Shaman',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: HomePage(themeProvider: themeProvider),
            routes: {
              '/receipt-designer': (context) => const ReceiptLabelDesigner(),
              '/profile-settings': (context) => const ProfileSettingsPage(),
            },
          );
        },
      ),
    );
  }
}
