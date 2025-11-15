import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'shared/constants/app_theme.dart';
import 'shared/constants/theme_provider.dart';
import 'presentation/pages/home.dart';
// import 'presentation/pages/receipt_label_designer.dart'; // Geçici olarak devre dışı
import 'presentation/pages/profile_settings.dart';
import 'presentation/pages/security_settings.dart';
import 'presentation/pages/backup_settings.dart';
import 'presentation/pages/notification_settings.dart';
import 'presentation/pages/sms_settings.dart';
import 'presentation/pages/language_currency_settings.dart';
import 'presentation/pages/about.dart';
import 'shared/utils/error_handler.dart';
import 'data/datasources/database_service.dart';
import 'data/datasources/default_printer_setup.dart';
import 'data/datasources/bluetooth_service.dart';

// NavigatorKey'i burada tanımlıyorum
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Flutter bağlamlarını başlat
  WidgetsFlutterBinding.ensureInitialized();

  // Merkezi hata yönetimi sistemini başlat
  ErrorHandler.setNavigatorKey(navigatorKey);
  ErrorHandler.initialize();

  // Bluetooth servisini ÖNCELİKLE başlat (EventSink hatası için)
  try {
    debugPrint('Bluetooth servisi başlatılıyor...');
    await BluetoothService.instance.initialize();
    debugPrint('Bluetooth servisi başarıyla başlatıldı');

    // Kısa bir bekleme - EventChannel'ın tam olarak hazır olması için
    await Future.delayed(const Duration(milliseconds: 500));
  } catch (e) {
    debugPrint('Bluetooth servisi başlatma hatası: $e');
  }

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
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: HomePage(themeProvider: themeProvider),
            routes: {
              // '/receipt-designer': (context) => const ReceiptLabelDesigner(), // Geçici olarak devre dışı
              '/profile-settings': (context) => const ProfileSettingsPage(),
              '/security-settings': (context) => const SecuritySettingsPage(),
              '/backup-settings': (context) => const BackupSettingsPage(),
              '/notification-settings': (context) =>
                  const NotificationSettingsPage(),
              '/sms-settings': (context) => const SmsSettingsPage(),
              '/language-currency-settings': (context) =>
                  const LanguageCurrencySettingsPage(),
              '/about': (context) => const AboutPage(),
            },
          );
        },
      ),
    );
  }
}
