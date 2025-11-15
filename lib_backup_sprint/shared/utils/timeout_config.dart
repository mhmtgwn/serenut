/// Merkezi timeout konfigürasyonu
/// Tüm uygulamada tutarlı timeout değerleri sağlar
class TimeoutConfig {
  // Bluetooth işlemleri
  static const Duration bluetoothScan = Duration(seconds: 10);
  static const Duration bluetoothConnect = Duration(seconds: 15);
  static const Duration bluetoothWrite = Duration(seconds: 10);
  static const Duration bluetoothDisconnect = Duration(seconds: 5);
  
  // Veritabanı işlemleri
  static const Duration databaseQuery = Duration(seconds: 30);
  static const Duration databaseTransaction = Duration(seconds: 60);
  
  // Ağ işlemleri
  static const Duration httpRequest = Duration(seconds: 30);
  static const Duration fileUpload = Duration(seconds: 120);
  static const Duration fileDownload = Duration(seconds: 180);
  
  // Yazıcı işlemleri
  static const Duration printerOperation = Duration(seconds: 15);
  static const Duration printerTestPage = Duration(seconds: 20);
  static const Duration printerReceipt = Duration(seconds: 25);
  
  // UI işlemleri
  static const Duration dialogTimeout = Duration(seconds: 5);
  static const Duration snackbarDuration = Duration(seconds: 3);
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration debounceDelay = Duration(milliseconds: 500);
  
  // Sistem işlemleri
  static const Duration systemOperation = Duration(seconds: 10);
  static const Duration fileOperation = Duration(seconds: 30);
  static const Duration cacheExpiry = Duration(hours: 24);
  
  // Özel durumlar için kısa timeout'lar
  static const Duration quickOperation = Duration(seconds: 3);
  static const Duration fastResponse = Duration(seconds: 5);
  
  // Uzun işlemler için
  static const Duration longOperation = Duration(minutes: 5);
  static const Duration backgroundSync = Duration(minutes: 10);
  
  /// Timeout değerini saniye olarak döndür
  static int toSeconds(Duration duration) => duration.inSeconds;
  
  /// Timeout değerini milisaniye olarak döndür
  static int toMilliseconds(Duration duration) => duration.inMilliseconds;
  
  /// Debug için timeout bilgilerini yazdır
  static Map<String, int> getAllTimeouts() {
    return {
      'bluetoothScan': bluetoothScan.inSeconds,
      'bluetoothConnect': bluetoothConnect.inSeconds,
      'bluetoothWrite': bluetoothWrite.inSeconds,
      'bluetoothDisconnect': bluetoothDisconnect.inSeconds,
      'databaseQuery': databaseQuery.inSeconds,
      'databaseTransaction': databaseTransaction.inSeconds,
      'httpRequest': httpRequest.inSeconds,
      'fileUpload': fileUpload.inSeconds,
      'fileDownload': fileDownload.inSeconds,
      'printerOperation': printerOperation.inSeconds,
      'printerTestPage': printerTestPage.inSeconds,
      'printerReceipt': printerReceipt.inSeconds,
      'dialogTimeout': dialogTimeout.inSeconds,
      'snackbarDuration': snackbarDuration.inSeconds,
      'systemOperation': systemOperation.inSeconds,
      'fileOperation': fileOperation.inSeconds,
      'quickOperation': quickOperation.inSeconds,
      'fastResponse': fastResponse.inSeconds,
      'longOperation': longOperation.inSeconds,
      'backgroundSync': backgroundSync.inSeconds,
    };
  }
}
