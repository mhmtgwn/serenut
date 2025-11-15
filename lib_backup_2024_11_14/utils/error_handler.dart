import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Merkezi hata yönetimi servisi
class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  static GlobalKey<NavigatorState>? _navigatorKey;
  
  /// Navigator key'i ayarla
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Global hata yakalayıcıyı başlat
  static void initialize() {
    FlutterError.onError = (FlutterErrorDetails details) {
      _handleFlutterError(details);
    };
  }

  /// Flutter hatalarını işle
  static void _handleFlutterError(FlutterErrorDetails details) {
    final errorMessage = details.exception.toString();
    final stackTrace = details.stack.toString();

    // Hata tipine göre kategorize et
    if (_isPrinterError(errorMessage)) {
      _handlePrinterError(errorMessage, stackTrace);
    } else if (_isBluetoothError(errorMessage)) {
      _handleBluetoothError(errorMessage, stackTrace);
    } else if (_isDatabaseError(errorMessage)) {
      _handleDatabaseError(errorMessage, stackTrace);
    } else if (_isNetworkError(errorMessage)) {
      _handleNetworkError(errorMessage, stackTrace);
    } else {
      _handleGenericError(details);
    }
  }

  /// Yazıcı hatası kontrolü
  static bool _isPrinterError(String error) {
    return error.contains('SunmiPrinterPlus') ||
           error.contains('printer') ||
           error.contains('EscCommand') ||
           error.contains('com.sunmi.printer') ||
           error.contains('BluetoothPrint');
  }

  /// Bluetooth hatası kontrolü
  static bool _isBluetoothError(String error) {
    return error.contains('bluetooth') ||
           error.contains('Bluetooth') ||
           error.contains('BluetoothAdapter') ||
           error.contains('BluetoothDevice');
  }

  /// Veritabanı hatası kontrolü
  static bool _isDatabaseError(String error) {
    return error.contains('sqlite') ||
           error.contains('database') ||
           error.contains('DatabaseException') ||
           error.contains('SQL');
  }

  /// Ağ hatası kontrolü
  static bool _isNetworkError(String error) {
    return error.contains('SocketException') ||
           error.contains('HttpException') ||
           error.contains('TimeoutException') ||
           error.contains('Connection');
  }

  /// Yazıcı hatalarını işle
  static void _handlePrinterError(String error, String stackTrace) {
    debugPrint('📄 Yazıcı Hatası: $error');
    debugPrint('📄 Stack Trace: $stackTrace');
    
    _showUserFriendlyError(
      'Yazıcı Hatası',
      'Yazıcı ile bağlantı kurulurken bir sorun oluştu. Lütfen yazıcının açık ve bağlı olduğundan emin olun.',
      Colors.orange,
      Icons.print_disabled,
    );
  }

  /// Bluetooth hatalarını işle
  static void _handleBluetoothError(String error, String stackTrace) {
    debugPrint('📶 Bluetooth Hatası: $error');
    debugPrint('📶 Stack Trace: $stackTrace');
    
    _showUserFriendlyError(
      'Bluetooth Hatası',
      'Bluetooth bağlantısında sorun oluştu. Bluetooth\'un açık olduğundan ve cihazın eşleştirildiğinden emin olun.',
      Colors.blue,
      Icons.bluetooth_disabled,
    );
  }

  /// Veritabanı hatalarını işle
  static void _handleDatabaseError(String error, String stackTrace) {
    debugPrint('💾 Veritabanı Hatası: $error');
    debugPrint('💾 Stack Trace: $stackTrace');
    
    _showUserFriendlyError(
      'Veri Hatası',
      'Veri kaydedilirken bir sorun oluştu. Lütfen tekrar deneyin.',
      Colors.red,
      Icons.storage,
    );
  }

  /// Ağ hatalarını işle
  static void _handleNetworkError(String error, String stackTrace) {
    debugPrint('🌐 Ağ Hatası: $error');
    debugPrint('🌐 Stack Trace: $stackTrace');
    
    _showUserFriendlyError(
      'Bağlantı Hatası',
      'İnternet bağlantınızı kontrol edin ve tekrar deneyin.',
      Colors.purple,
      Icons.wifi_off,
    );
  }

  /// Genel hataları işle
  static void _handleGenericError(FlutterErrorDetails details) {
    debugPrint('⚠️ Genel Hata: ${details.exception}');
    debugPrint('⚠️ Stack Trace: ${details.stack}');
    
    // Sadece debug modda göster
    if (kDebugMode) {
      FlutterError.presentError(details);
    } else {
      _showUserFriendlyError(
        'Beklenmeyen Hata',
        'Bir sorun oluştu. Lütfen uygulamayı yeniden başlatın.',
        Colors.red,
        Icons.error,
      );
    }
  }

  /// Kullanıcı dostu hata mesajı göster
  static void _showUserFriendlyError(
    String title,
    String message,
    Color color,
    IconData icon,
  ) {
    if (_navigatorKey?.currentContext != null) {
      final context = _navigatorKey!.currentContext!;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      message,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: color,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Manuel hata raporlama
  static void reportError(String title, String message, {String? details}) {
    debugPrint('🔴 Manuel Hata Raporu: $title - $message');
    if (details != null) {
      debugPrint('🔴 Detaylar: $details');
    }
    
    _showUserFriendlyError(
      title,
      message,
      Colors.red,
      Icons.error_outline,
    );
  }

  /// Başarı mesajı göster
  static void showSuccess(String message) {
    if (_navigatorKey?.currentContext != null) {
      final context = _navigatorKey!.currentContext!;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Bilgi mesajı göster
  static void showInfo(String message) {
    if (_navigatorKey?.currentContext != null) {
      final context = _navigatorKey!.currentContext!;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}
