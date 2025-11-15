import 'package:flutter/foundation.dart';

/// Merkezi debug konfigürasyonu
/// Performans için debug mesajlarını kontrol eder
class DebugConfig {
  // Debug seviyesi
  static const bool _enableDebugPrints = kDebugMode;
  static const bool _enableVerboseLogging = false;
  static const bool _enableErrorLogging = true;
  
  /// Sadece kritik hatalar için debug mesajı
  static void logError(String message, [Object? error]) {
    if (_enableErrorLogging && kDebugMode) {
      debugPrint('❌ ERROR: $message${error != null ? ' - $error' : ''}');
    }
  }
  
  /// Genel debug mesajları (sadece debug modda)
  static void logDebug(String message) {
    if (_enableDebugPrints && kDebugMode) {
      debugPrint('🔍 DEBUG: $message');
    }
  }
  
  /// Detaylı loglama (normalde kapalı)
  static void logVerbose(String message) {
    if (_enableVerboseLogging && kDebugMode) {
      debugPrint('📝 VERBOSE: $message');
    }
  }
  
  /// Başarılı işlemler için
  static void logSuccess(String message) {
    if (_enableDebugPrints && kDebugMode) {
      debugPrint('✅ SUCCESS: $message');
    }
  }
  
  /// Uyarı mesajları
  static void logWarning(String message) {
    if (_enableDebugPrints && kDebugMode) {
      debugPrint('⚠️ WARNING: $message');
    }
  }
}
