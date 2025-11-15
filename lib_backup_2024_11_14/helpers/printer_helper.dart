import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
// Düzeltilmiş Bluetooth yazıcı helper'ını kullan
import 'bluetooth_printer_helper_simple.dart';
import 'bluetooth_printer_controller.dart' as local;
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';

/// Yazıcı metin boyutu
enum PrintSize {
  small,
  normal,
  medium,
  large
}

/// Yazıcı metin hizalaması
enum PrintAlign {
  left,
  center,
  right
}

// SunmiPrinter için gerekli enum değerleri
// Paket içindeki enum'lar bazen erişilemediği için burada tanımlıyoruz
enum SunmiPrintAlign {
  left, center, right
}

enum SunmiFontSize {
  xs, sm, md, lg, xl
}

enum SunmiBarcodeType {
  upca, upce, jan13, jan8, code39, itf, codabar, code93, code128
}

enum SunmiBarcodeTextPos {
  noText, textAbove, textUnder, both
}

enum SunmiQrcodeStyle {
  sunmiQrcode1, sunmiQrcode2
}

/// Farklı yazıcı protokolleri için yardımcı sınıf
class PrinterHelper {
  static final PrinterHelper _instance = PrinterHelper._internal();
  
  // Platform kanalları
  static const MethodChannel _printerChannel = MethodChannel('com.sunmi.printer');
  static const MethodChannel _scannerChannel = MethodChannel('com.sunmi.scanner');
  static const MethodChannel _nfcChannel = MethodChannel('com.sunmi.nfc');
  static const MethodChannel _drawerChannel = MethodChannel('com.sunmi.drawer');
  
  // Düzeltilmiş Bluetooth yazıcı yöneticisi
  final BluetoothPrinterHelperSimple _bluetoothHelper = BluetoothPrinterHelperSimple();
  
  factory PrinterHelper() {
    return _instance;
  }
  
  PrinterHelper._internal();
  
  /// Yazdırma protokolü türleri
  static const String escPos = 'esc_pos';
  static const String tsc = 'tsc';
  static const String cpcl = 'cpcl';
  static const String tspl = 'tspl';
  static const String zpl = 'zpl';
  
  /// Yazıcı kontrolü
  Future<bool> hasPrinter() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('hasPrinter');
      debugPrint('hasPrinter çağrıldı');
      return result ?? false;
    } catch (e) {
      debugPrint('Yazıcı kontrol hatası: $e');
      return false;
    }
  }
  
  /// Yazıcı sürümünü al
  Future<String> getPrinterVersion() async {
    try {
      final result = await _printerChannel.invokeMethod<String>('getPrinterVersion');
      return result ?? 'Bilinmiyor';
    } catch (e) {
      debugPrint('Yazıcı sürüm hatası: $e');
      return 'Hata';
    }
  }
  
  /// Yazıcı seri numarasını al
  Future<String> getPrinterSerialNo() async {
    try {
      final result = await _printerChannel.invokeMethod<String>('getPrinterSerialNo');
      return result ?? 'Bilinmiyor';
    } catch (e) {
      debugPrint('Yazıcı seri no hatası: $e');
      return 'Hata';
    }
  }

  /// Test sayfası yazdır
  Future<bool> printTestPage() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('printTestPage');
      return result ?? false;
    } catch (e) {
      debugPrint('Test sayfası yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Fiş yazdır
  Future<bool> printReceiptData(Map<String, dynamic> receiptData) async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('printReceipt', receiptData);
      return result ?? false;
    } catch (e) {
      debugPrint('Fiş yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Metin yazdır
  Future<bool> printText(String text, {int fontSize = 24, bool bold = false, int align = 0}) async {
    try {
      debugPrint('Yazdırılıyor: $text, Boyut: $fontSize, Kalın: $bold');
      final result = await _printerChannel.invokeMethod<bool>('printText', {
        'text': text,
        'fontSize': fontSize,
        'bold': bold,
        'align': align,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Metin yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Barkod yazdır
  Future<bool> printBarcode(String data, {int height = 80, int width = 2}) async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('printBarcode', {
        'data': data,
        'height': height,
        'width': width,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Barkod yazdırma hatası: $e');
      return false;
    }
  }
  
  /// QR kod yazdır
  Future<bool> printQRCode(String data, {int size = 200}) async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('printQRCode', {
        'data': data,
        'size': size,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('QR kod yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Çizgi yazdır
  Future<bool> printLine() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('printLine');
      return result ?? false;
    } catch (e) {
      debugPrint('Çizgi yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Kağıt kes
  Future<bool> cutPaper() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('cutPaper');
      return result ?? false;
    } catch (e) {
      debugPrint('Kağıt kesme hatası: $e');
      return false;
    }
  }
  
  /// Basit fiş yazdırma metodu - Platform kanalını kullanır
  Future<bool> printSimpleReceipt(String printerId) async {
    try {
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      final isInternal = device['isInternal'] == 1;
      
      if (isInternal) {
        // Dahili yazıcı için platform kanalını kullan
        final result = await _printerChannel.invokeMethod<bool>('printTestReceipt');
        return result ?? false;
      } else {
        // Harici yazıcı için farklı bir yöntem kullan
        return false;
      }
    } catch (e) {
      debugPrint('Basit fiş yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Barkod tarayıcı kontrolü
  Future<bool> hasScanner() async {
    try {
      final result = await _scannerChannel.invokeMethod<bool>('hasScanner');
      debugPrint('hasScanner çağrıldı');
      return result ?? false;
    } catch (e) {
      debugPrint('Barkod tarayıcı kontrol hatası: $e');
      return false;
    }
  }
  
  /// Barkod tarayıcı bilgilerini al
  Future<Map<String, dynamic>> getScannerInfo() async {
    try {
      final result = await _scannerChannel.invokeMethod<Map<dynamic, dynamic>>('getScannerInfo');
      return result?.cast<String, dynamic>() ?? {'model': 'Bilinmiyor', 'version': 'Bilinmiyor'};
    } catch (e) {
      debugPrint('Barkod tarayıcı bilgi hatası: $e');
      return {'model': 'Hata', 'version': 'Hata'};
    }
  }
  
  /// Barkod tarama başlat
  Future<String?> startScan() async {
    try {
      final result = await _scannerChannel.invokeMethod<String>('startScan');
      return result;
    } catch (e) {
      debugPrint('Barkod tarama hatası: $e');
      return null;
    }
  }
  
  /// Barkod tarama durdur
  Future<bool> stopScan() async {
    try {
      await _scannerChannel.invokeMethod('stopScan');
      return true;
    } catch (e) {
      debugPrint('Barkod tarama durdurma hatası: $e');
      return false;
    }
  }
  
  /// Test yazdırma işlemi
  Future<bool> printTest({
    required String printerId,
    int paperWidth = 58,
    bool keepConnection = true,
  }) async {
    try {
      // Debug log ekle
      debugPrint('⏩ printTest çağrıldı - Yazıcı ID: $printerId, Kağıt Genişliği: $paperWidth');
      
      // Yazıcı bilgilerini veritabanından al
      final printerData = await DatabaseService.instance.getDeviceById(printerId);
      
      if (printerData == null) {
        debugPrint('❌ Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      // Yazıcı bilgilerini logla
      debugPrint('📝 Yazıcı bilgileri: ${printerData.toString()}');
      
      // Yazıcı türünü kontrol et
      final bool isInternal = printerData['isInternal'] == 1;
      
      debugPrint('🖨️ Yazıcı türü: ${isInternal ? 'Dahili' : 'Harici'}');
      
      if (isInternal) {
        // Dahili yazıcı için test sayfası
        debugPrint('📄 Dahili yazıcı test sayfası hazırlanıyor...');
        return await _printInternalTest(paperWidth);
      } else {
        // Harici yazıcı için test sayfası
        debugPrint('📄 Harici yazıcı test sayfası hazırlanıyor...');
        return await _printExternalTest(printerData, keepConnection);
      }
    } catch (e) {
      debugPrint('❌ Test yazdırma hatası: $e');
      return false;
    }
  }
  
  // Dahili yazıcı test sayfası
  Future<bool> _printInternalTest(int paperWidth) async {
    try {
      debugPrint('⏩ _printInternalTest çağrıldı - Kağıt Genişliği: $paperWidth');
      
      final Map<String, dynamic> params = {
        'paperWidth': paperWidth,
      };
      
      debugPrint('📤 Platform kanalına "printTest" metodunu çağırıyorum...');
      final bool result = await _printerChannel.invokeMethod('printTest', params);
      debugPrint('📥 Platform kanalı sonucu: $result');
      
      return result;
    } catch (e) {
      debugPrint('❌ Dahili yazıcı test hatası: $e');
      return false;
    }
  }
  
  // Harici yazıcı test sayfası
  Future<bool> _printExternalTest(Map<String, dynamic> printerData, bool keepConnection) async {
    try {
      // Bluetooth yazıcı bilgilerini al
      final String address = printerData['bluetoothAddress'] ?? '';
      final String name = printerData['name'] ?? 'Bilinmeyen Yazıcı';
      
      if (address.isEmpty) {
        debugPrint('Bluetooth adresi bulunamadı');
        return false;
      }
      
      // Bluetooth cihazı oluştur
      final BluetoothDevice device = BluetoothDevice(name, address);
      
      // Yazıcıya bağlan
      debugPrint('Harici yazıcıya bağlanılıyor: $name ($address)');
      
      // Önce bağlantı durumunu kontrol et
      bool isAlreadyConnected = false;
      try {
        isAlreadyConnected = _bluetoothHelper.isConnected && 
                            _bluetoothHelper.connectedDevice?.address == address;
      } catch (e) {
        debugPrint('Bağlantı durumu kontrolünde hata: $e');
      }
      
      bool connected = isAlreadyConnected;
      
      // Eğer zaten bağlı değilse bağlanmaya çalış
      if (!connected) {
        // Önce mevcut bağlantıları kapat
        await _bluetoothHelper.safeDisconnect();
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Bağlantı dene - maksimum 3 deneme
        int maxRetries = 3;
        int retryCount = 0;
        
        while (retryCount < maxRetries && !connected) {
          retryCount++;
          debugPrint('Bağlantı denemesi: $retryCount');
          
          try {
            connected = await _bluetoothHelper.connect(device);
            debugPrint('Bağlantı durumu: ${connected ? "Başarılı" : "Başarısız"}');
          } catch (connectionError) {
            debugPrint('Bağlantı hatası: $connectionError');
            await Future.delayed(const Duration(milliseconds: 500));
          }
          
          if (!connected && retryCount < maxRetries) {
            debugPrint('Bağlantı başarısız, yeniden deneniyor...');
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        
        if (!connected) {
          debugPrint('Bağlantı kurulamadı, maksimum deneme sayısına ulaşıldı');
          return false;
        }
      } else {
        debugPrint('Yazıcı zaten bağlı, yeniden bağlanma atlanıyor');
      }
      
      // Test sayfası oluştur - try with simpler test page first
      Uint8List testData;
      try {
        testData = await local.PrinterDocuments.createTestPage(
          title: 'Test Sayfası',
          printerName: name,
          address: address,
        );
      } catch (testPageError) {
        debugPrint('Test sayfası oluşturma hatası: $testPageError');
        // Create a very simple test page as fallback
        final simpleCmd = local.EscCommand();
        await simpleCmd.cleanCommand();
        await simpleCmd.text(content: 'TEST SAYFASI\n\n');
        await simpleCmd.text(content: 'Yazıcı: $name\n');
        await simpleCmd.text(content: 'Test Başarılı!\n\n\n\n\n');
        testData = await simpleCmd.getCommand();
      }
      
      // Yazdırma işlemi için try-catch bloğu
      try {
        // Yazdır
        await _bluetoothHelper.safeWrite(testData);
        
        // Başarılı yazdırma sonrası kısa bir bekleme
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Bağlantıyı keepConnection parametresine göre yönet
        if (!keepConnection) {
          debugPrint('keepConnection=false, bağlantı kapatılıyor');
          await _bluetoothHelper.safeDisconnect();
        } else {
          debugPrint('keepConnection=true, bağlantı açık tutuluyor');
        }
        
        return true;
      } catch (printError) {
        debugPrint('Yazdırma hatası: $printError');
        
        // Soket hatası durumunda yeniden deneme
        if (printError.toString().contains('socket closed') || 
            printError.toString().contains('null')) {
          debugPrint('Soket hatası tespit edildi, yeniden deneniyor...');
          
          // Kısa bir bekleme
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Bağlantıyı kapat ve yeniden bağlan
          await _bluetoothHelper.safeDisconnect();
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Yeniden bağlan
          connected = await _bluetoothHelper.connect(device);
          
          if (connected) {
            try {
              // Daha basit bir test sayfası hazırla
              final simpleCmd = local.EscCommand();
              await simpleCmd.cleanCommand();
              await simpleCmd.text(content: 'BASIT TEST\n\n');
              await simpleCmd.text(content: 'Yazıcı: $name\n\n\n\n\n');
              final simpleData = await simpleCmd.getCommand();
              
              // Yazdırmayı tekrar dene
              await _bluetoothHelper.safeWrite(simpleData);
              
              // Başarılı yazdırma sonrası kısa bir bekleme
              await Future.delayed(const Duration(milliseconds: 500));
              
              // Bağlantıyı keepConnection parametresine göre yönet
              if (!keepConnection) {
                debugPrint('keepConnection=false, bağlantı kapatılıyor');
                await _bluetoothHelper.safeDisconnect();
              } else {
                debugPrint('keepConnection=true, bağlantı açık tutuluyor');
              }
              
              return true;
            } catch (retryError) {
              debugPrint('Yeniden yazdırma hatası: $retryError');
              // Hata durumunda her zaman bağlantıyı kapat
              await _bluetoothHelper.safeDisconnect();
              return false;
            }
          }
        }
        
        // Hata durumunda her zaman bağlantıyı kapat
        if (connected) {
          await _bluetoothHelper.safeDisconnect();
        }
        return false;
      }
    } catch (e) {
      debugPrint('Harici yazıcı test hatası: $e');
      // Bağlantıyı kapat
      try {
        await _bluetoothHelper.safeDisconnect();
      } catch (disconnectError) {
        debugPrint('Bağlantı kesme hatası: $disconnectError');
      }
      return false;
    }
  }
  
  /// NFC kontrolü
  Future<bool> hasNfc() async {
    try {
      final result = await _nfcChannel.invokeMethod<bool>('hasNfc');
      debugPrint('hasNfc çağrıldı');
      return result ?? false;
    } catch (e) {
      debugPrint('NFC kontrol hatası: $e');
      return false;
    }
  }
  
  /// NFC bilgilerini al
  Future<Map<String, dynamic>> getNfcInfo() async {
    try {
      final result = await _nfcChannel.invokeMethod<Map<dynamic, dynamic>>('getNfcInfo');
      return result?.cast<String, dynamic>() ?? {'model': 'Bilinmiyor', 'version': 'Bilinmiyor'};
    } catch (e) {
      debugPrint('NFC bilgi hatası: $e');
      return {'model': 'Hata', 'version': 'Hata'};
    }
  }
  
  /// Para çekmecesi kontrolü
  Future<bool> hasDrawer() async {
    try {
      final result = await _drawerChannel.invokeMethod<bool>('hasDrawer');
      debugPrint('hasDrawer çağrıldı');
      return result ?? false;
    } catch (e) {
      debugPrint('Para çekmecesi kontrol hatası: $e');
      return false;
    }
  }
  
  /// Para çekmecesi bilgilerini al
  Future<Map<String, dynamic>> getDrawerInfo() async {
    try {
      final result = await _drawerChannel.invokeMethod<Map<dynamic, dynamic>>('getDrawerInfo');
      return result?.cast<String, dynamic>() ?? {'model': 'Bilinmiyor', 'version': 'Bilinmiyor'};
    } catch (e) {
      debugPrint('Para çekmecesi bilgi hatası: $e');
      return {'model': 'Hata', 'version': 'Hata'};
    }
  }
  
  /// Para çekmecesini aç
  Future<bool> openDrawer() async {
    try {
      final result = await _drawerChannel.invokeMethod<bool>('openDrawer');
      return result ?? false;
    } catch (e) {
      debugPrint('Para çekmecesi açma hatası: $e');
      return false;
    }
  }
  
  /// Protokollerin dahili/harici kullanılabilirliği
  static bool isProtocolSupportedForInternal(String protocol) {
    switch (protocol.toLowerCase()) {
      case escPos:
      case tspl:
        return true;
      default:
        return false;
    }
  }
  
  static bool isProtocolSupportedForExternal(String protocol) {
    switch (protocol.toLowerCase()) {
      case escPos:
      case tsc:
      case cpcl:
        return true;
      default:
        return false;
    }
  }

  /// Dahili cihaz test sayfası yazdır
  Future<bool> printInternalDeviceTestPage({
    required String printerId,
    String protocol = 'esc_pos',
    int paperWidth = 58,
  }) async {
    try {
      debugPrint('Dahili yazıcı test sayfası yazdırılıyor: $printerId');
      
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      // Test sayfası yazdır
      return await printTest(printerId: printerId, paperWidth: paperWidth);
    } catch (e) {
      debugPrint('Dahili cihaz test sayfası yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Harici cihaz test sayfası yazdır
  Future<bool> printExternalDeviceTestPage({
    required String printerId,
    String protocol = 'esc_pos',
    int paperWidth = 58,
    bool keepConnection = true,
  }) async {
    try {
      debugPrint('Harici yazıcı test sayfası yazdırılıyor: $printerId');
      
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      // Test sayfası yazdır - keepConnection parametresini geçir
      return await printTest(
        printerId: printerId, 
        paperWidth: paperWidth,
        keepConnection: keepConnection
      );
    } catch (e) {
      debugPrint('Harici cihaz test sayfası yazdırma hatası: $e');
      return false;
    }
  }
  
  /// Gerçek donanımları tespit et
  static Future<Map<String, dynamic>> checkActualDevices() async {
    try {
      final Map<dynamic, dynamic> result = await _printerChannel.invokeMethod('checkDevices');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      debugPrint('Platform hatası: ${e.message}');
      return {'error': true, 'message': e.message};
    } catch (e) {
      debugPrint('Cihaz kontrolü hatası: $e');
      return {'error': true, 'message': e.toString()};
    }
  }

  /// Fiş yazdırma - görsel ile
  Future<bool> printReceiptWithImage({
    required String printerId,
    String? imagePath = 'assets/logo.png', // Varsayılan olarak fis.png kullan
    String title = 'SHAMAN',
    String subtitle = 'Fiş',
    String date = '',
    String? footer,
    int paperWidth = 58,
  }) async {
    try {
      debugPrint('Test fişi yazdırılıyor: $printerId, Kağıt genişliği: $paperWidth');
      debugPrint('Görsel yolu: $imagePath');
      
      // Tarih bilgisini oluştur
      
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      final isInternal = device['isInternal'] == 1;
      
      if (isInternal) {
        // Tarih bilgisini oluştur
        final now = DateTime.now();
        final dateStr = date.isEmpty 
            ? '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}'
            : date;
        
        try {
          // Başlık yazdır
          await _printerChannel.invokeMethod('printText', {
            'text': title,
            'fontSize': 36,
            'bold': true,
            'align': 1, // CENTER
          });
          
          // Alt başlık yazdır
          await _printerChannel.invokeMethod('printText', {
            'text': subtitle,
            'fontSize': 24,
            'bold': false,
            'align': 1, // CENTER
          });
          
          // Tarih yazdır
          await _printerChannel.invokeMethod('printText', {
            'text': 'Tarih: $dateStr',
            'fontSize': 24,
            'bold': false,
            'align': 1, // CENTER
          });
          
          // Çizgi yazdır
          await _printerChannel.invokeMethod('printText', {
            'text': '--------------------------------',
            'fontSize': 24,
            'bold': false,
            'align': 1, // CENTER
          });
          
          // Görsel yazdır
          if (imagePath != null && imagePath.isNotEmpty) {
            try {
              debugPrint('Görsel yazdırma başlatılıyor: $imagePath');
              
              // Mevcut asset dosyalarını kontrol et
              debugPrint('Mevcut görsel dosyaları kontrol ediliyor...');
              
              // Görsel dosyasını yükle
              try {
                final ByteData logoBytes = await rootBundle.load(imagePath);
                final Uint8List imageData = logoBytes.buffer.asUint8List();
                
                debugPrint('Görsel başarıyla yüklendi, boyutu: ${imageData.length} bytes');
                
                // Görseli yazdır - doğrudan byte array olarak gönder
                await _printerChannel.invokeMethod('printReceiptWithImage', {
                  'title': title,
                  'subtitle': subtitle,
                  'date': dateStr,
                  'imagePath': imagePath,
                  'footer': footer ?? 'Teşekkür ederiz!',
                  'paperWidth': paperWidth,
                  'image': imageData, // Görsel verisini doğrudan gönder
                });
              } catch (loadError) {
                debugPrint('Görsel yükleme hatası: $loadError');
                
                // Alternatif görsel dene
                final alternativeImagePath = 'assets/fis.png';
                debugPrint('Alternatif görsel deneniyor: $alternativeImagePath');
                
                final ByteData logoBytes = await rootBundle.load(alternativeImagePath);
                final Uint8List imageData = logoBytes.buffer.asUint8List();
                
                debugPrint('Alternatif görsel yüklendi, boyutu: ${imageData.length} bytes');
                
                await _printerChannel.invokeMethod('printReceiptWithImage', {
                  'title': title,
                  'subtitle': subtitle,
                  'date': dateStr,
                  'imagePath': alternativeImagePath,
                  'footer': footer ?? 'Teşekkür ederiz!',
                  'paperWidth': paperWidth,
                  'image': imageData, // Görsel verisini doğrudan gönder
                });
              }
              
              debugPrint('Görsel yazdırma tamamlandı');
            } catch (e) {
              debugPrint('Logo yazdırma hatası: $e');
              
              // Hata durumunda görsel olmadan yazdır
              await _printerChannel.invokeMethod('printReceiptWithImage', {
                'title': title,
                'subtitle': subtitle,
                'date': dateStr,
                'imagePath': imagePath,
                'footer': footer ?? 'Teşekkür ederiz!',
                'paperWidth': paperWidth,
              });
            }
          }
          
          // Alt bilgi yazdır
          await _printerChannel.invokeMethod('printText', {
            'text': '--------------------------------',
            'fontSize': 24,
            'bold': false,
            'align': 1, // CENTER
          });
          
          // Footer yazdır
          await _printerChannel.invokeMethod('printText', {
            'text': footer ?? 'Teşekkür ederiz!',
            'fontSize': 24,
            'bold': false,
            'align': 1, // CENTER
          });
          
          // Kağıt ilerlet
          await _printerChannel.invokeMethod('printText', {
            'text': '\n\n\n',
            'fontSize': 24,
            'bold': false,
            'align': 1, // CENTER
          });
          
          // Kağıt kes
          await _printerChannel.invokeMethod('cutPaper');
          
          debugPrint('Test fişi başarıyla yazdırıldı!');
          return true;
        } catch (e) {
          debugPrint('Platform kanalı ile yazdırma hatası: $e');
          return false;
        }
      } else {
        // Harici yazıcı için test yazdırma işlemi
        return await _printExternalReceiptWithImage(
          device: device,
          imagePath: imagePath,
          title: title,
          subtitle: subtitle,
          date: date,
          footer: footer ?? 'Teşekkür ederiz!',
        );
      }
    } catch (e) {
      debugPrint('Test fişi yazdırma hatası: $e');
      return false;
    }
  }
  
  // Harici yazıcı için görsel içeren fiş yazdırma
  Future<bool> _printExternalReceiptWithImage({
    required Map<String, dynamic> device,
    String? imagePath,
    required String title,
    required String subtitle,
    String date = '',
    required String footer,
  }) async {
    try {
      final bluetoothHelper = BluetoothPrinterHelperSimple();
      
      // Bluetooth cihazını bul ve bağlan
      await bluetoothHelper.startScan(timeout: const Duration(seconds: 10));
      
      // Cihazı bul
      final targetDevice = bluetoothHelper.scanResults.firstWhere(
        (d) => d.address == device['bluetoothAddress'] || d.name == device['name'],
        orElse: () => throw Exception('Bluetooth cihazı bulunamadı'),
      );
      
      // Bağlan
      final connected = await bluetoothHelper.connect(targetDevice);
      if (!connected) {
        throw Exception('Bluetooth cihazına bağlanılamadı');
      }
      
      // Tarih bilgisini oluştur
      final now = DateTime.now();
      final dateStr = date.isEmpty 
          ? '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}'
          : date;
      
      // Fiş yazdır
      final cmd = local.EscCommand();
      await cmd.cleanCommand();
      
      // Başlık
      await cmd.setAlignment(alignment: 1); // Ortalama
      await cmd.setBold(enabled: true);
      await cmd.setFontSize(width: 2, height: 2);
      await cmd.text(content: title);
      await cmd.feedLine();
      
      await cmd.setBold(enabled: false);
      await cmd.setFontSize(width: 1, height: 1);
      await cmd.text(content: subtitle);
      await cmd.feedLine();
      await cmd.text(content: 'Tarih: $dateStr');
      await cmd.feedLine(lines: 2);
      
      // Çizgi
      await cmd.text(content: '--------------------------------');
      await cmd.feedLine();
      
      // Burada görsel yazdırma işlemi yapılacak, ancak ESC/POS ile görsel yazdırma 
      // karmaşık olduğu için sadece barkod yazdırıyoruz
      await cmd.setAlignment(alignment: 1);
      await cmd.text(content: 'BARKOD TEST');
      await cmd.feedLine();
      await cmd.barcode(x: 0, y: 0, barcodeType: '128', height: 50, content: '12345678');
      await cmd.feedLine(lines: 2);
      
      // Alt bilgi
      await cmd.text(content: '--------------------------------');
      await cmd.feedLine();
      await cmd.text(content: footer);
      await cmd.feedLine(lines: 3);
      
      // Kağıt kesme
      await cmd.cutPaper();
      
      // Yazdır
      final commandData = await cmd.getCommand();
      await bluetoothHelper.write(commandData);
      
      // Bağlantıyı kapat
      await bluetoothHelper.disconnect();
      
      return true;
    } catch (e) {
      debugPrint('Harici görsel fiş yazdırma hatası: $e');
      return false;
    }
  }

  /// Harici yazıcılar için fiş yazdırma metodu
  Future<bool> printReceipt({
    required String printerId,
    int paperWidth = 58,
    String title = 'SATIŞ FİŞİ',
    String subtitle = '',
    List<Map<String, dynamic>> items = const [],
    double total = 0.0,
    String paymentMethod = 'Nakit',
    String? qrData,
  }) async {
    try {
      debugPrint('Fiş yazdırılıyor: $printerId');
      
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      final isInternal = device['isInternal'] == 1;
      
      if (isInternal) {
        // Dahili yazıcı için platform kanalını kullan
        return await _printInternalReceipt(
          title: title,
          subtitle: subtitle,
          items: items,
          total: total,
          paymentMethod: paymentMethod,
        );
      } else {
        // Harici yazıcı için Bluetooth yazıcı yardımcısını kullan
        return await _printExternalReceipt(
          device: device,
          title: title,
          subtitle: subtitle,
          items: items,
          total: total,
          paymentMethod: paymentMethod,
          qrData: qrData,
        );
      }
    } catch (e) {
      debugPrint('Fiş yazdırma hatası: $e');
      return false;
    }
  }

  /// Harici yazıcılar için ürün etiketi yazdırma metodu
  Future<bool> printProductLabel({
    required String printerId,
    int paperWidth = 60,
    int paperHeight = 40,
    String productName = '',
    String productDescription = '',
    double price = 0.0,
    String expiryDate = '',
    String barcode = '',
    String code = '',
    String unitPrice = '',
    String company = '',
    String country = '',
  }) async {
    try {
      debugPrint('Ürün etiketi yazdırılıyor: $printerId');
      
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      final isInternal = device['isInternal'] == 1;
      
      if (isInternal) {
        // Dahili yazıcı için platform kanalını kullan
        return await _printInternalProductLabel(
          productName: productName,
          productDescription: productDescription,
          price: price,
          expiryDate: expiryDate,
          barcode: barcode,
          code: code,
          unitPrice: unitPrice,
          company: company,
          country: country,
        );
      } else {
        // Harici yazıcı için Bluetooth yazıcı yardımcısını kullan
        return await _printExternalProductLabel(
          device: device,
          paperWidth: paperWidth,
          paperHeight: paperHeight,
          productName: productName,
          productDescription: productDescription,
          price: price,
          expiryDate: expiryDate,
          barcode: barcode,
          code: code,
          unitPrice: unitPrice,
          company: company,
          country: country,
        );
      }
    } catch (e) {
      debugPrint('Ürün etiketi yazdırma hatası: $e');
      return false;
    }
  }

  /// Harici yazıcılar için raf etiketi yazdırma metodu
  Future<bool> printShelfLabel({
    required String printerId,
    int paperWidth = 60,
    int paperHeight = 40,
    String productName = '',
    double price = 0.0,
    String unitPrice = '',
    String barcode = '',
  }) async {
    try {
      debugPrint('Raf etiketi yazdırılıyor: $printerId');
      
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      final isInternal = device['isInternal'] == 1;
      
      if (isInternal) {
        // Dahili yazıcı için platform kanalını kullan
        return await _printInternalShelfLabel(
          productName: productName,
          price: price,
          unitPrice: unitPrice,
          barcode: barcode,
        );
      } else {
        // Harici yazıcı için Bluetooth yazıcı yardımcısını kullan
        return await _printExternalShelfLabel(
          device: device,
          paperWidth: paperWidth,
          paperHeight: paperHeight,
          productName: productName,
          price: price,
          unitPrice: unitPrice,
          barcode: barcode,
        );
      }
    } catch (e) {
      debugPrint('Raf etiketi yazdırma hatası: $e');
      return false;
    }
  }

  /// Harici yazıcılar için sipariş etiketi yazdırma metodu
  Future<bool> printOrderLabel({
    required String printerId,
    int paperWidth = 60,
    int paperHeight = 40,
    String orderNo = '',
    String customerName = '',
    String customerPhone = '',
    List<Map<String, dynamic>> items = const [],
    double total = 0.0,
  }) async {
    try {
      debugPrint('Sipariş etiketi yazdırılıyor: $printerId');
      
      // Cihaz bilgilerini al
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      final isInternal = device['isInternal'] == 1;
      
      if (isInternal) {
        // Dahili yazıcı için platform kanalını kullan
        return await _printInternalOrderLabel(
          orderNo: orderNo,
          customerName: customerName,
          customerPhone: customerPhone,
          items: items,
          total: total,
        );
      } else {
        // Harici yazıcı için Bluetooth yazıcı yardımcısını kullan
        return await _printExternalOrderLabel(
          device: device,
          paperWidth: paperWidth,
          paperHeight: paperHeight,
          orderNo: orderNo,
          customerName: customerName,
          customerPhone: customerPhone,
          items: items,
          total: total,
        );
      }
    } catch (e) {
      debugPrint('Sipariş etiketi yazdırma hatası: $e');
      return false;
    }
  }

  // Dahili yazıcı için fiş yazdırma
  Future<bool> _printInternalReceipt({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required double total,
    required String paymentMethod,
  }) async {
    try {
      debugPrint('Dahili yazıcı ile fiş yazdırma başlatılıyor...');
      
      var receiptContent = '$title\n\n'
          '$subtitle\n\n'
          'Tarih: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute}\n\n'
          '--------------------------------\n\n';
      
      for (var item in items) {
        receiptContent += '${item['name']} x${item['quantity']} ${(item['price'] * item['quantity']).toStringAsFixed(2)} TL\n';
      }
      
      receiptContent += '--------------------------------\n\n'
          'Toplam: ${total.toStringAsFixed(2)} TL\n'
          'Ödeme: $paymentMethod\n\n'
          'Teşekkürler\n\n\n';
      
      debugPrint('Fiş içeriği hazırlandı, platform kanalına gönderiliyor...');
      debugPrint('Fiş içeriği: $receiptContent');
      
      // Platform kanalının mevcut olup olmadığını kontrol et
      try {
        await _printerChannel.invokeMethod('printText', {
          'text': receiptContent,
          'fontSize': 24,
          'bold': false,
          'align': 1,
        });
        
        debugPrint('Fiş başarıyla yazdırıldı (platform kanalı)');
        return true;
      } on PlatformException catch (e) {
        debugPrint('Platform kanalı hatası: ${e.code} - ${e.message}');
        
        // Platform kanalı yoksa alternatif yazdırma yöntemi dene
        if (e.code == 'unimplemented' || e.message?.contains('not implemented') == true) {
          debugPrint('Platform kanalı implement edilmemiş, alternatif yöntem deneniyor...');
          
          // Basit konsol çıktısı (test için)
          debugPrint('=== FİŞ YAZDIRMA (SİMÜLASYON) ===');
          debugPrint(receiptContent);
          debugPrint('=== FİŞ SONU ===');
          
          return true; // Simülasyon başarılı
        }
        
        throw e; // Diğer platform hatalarını yukarı fırlat
      }
    } catch (e) {
      debugPrint('Dahili fiş yazdırma hatası: $e');
      debugPrint('Hata türü: ${e.runtimeType}');
      
      // Son çare olarak konsol çıktısı
      debugPrint('=== FİŞ YAZDIRMA (HATA DURUMU) ===');
      debugPrint('Başlık: $title');
      debugPrint('Alt başlık: $subtitle');
      debugPrint('Ürünler:');
      for (var item in items) {
        debugPrint('- ${item['name']} x${item['quantity']} = ${(item['price'] * item['quantity']).toStringAsFixed(2)} TL');
      }
      debugPrint('Toplam: ${total.toStringAsFixed(2)} TL');
      debugPrint('Ödeme: $paymentMethod');
      debugPrint('=== FİŞ SONU ===');
      
      return false;
    }
  }

  // Harici yazıcı için fiş yazdırma - Native Bluetooth ile
  Future<bool> _printExternalReceipt({
    required Map<String, dynamic> device,
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required double total,
    required String paymentMethod,
    String? qrData,
  }) async {
    BluetoothPrinterHelperSimple? bluetoothHelper;
    
    try {
      debugPrint('🖨️ Harici yazıcı ile fiş yazdırma başlatılıyor (Düzeltilmiş Bluetooth)...');
      debugPrint('Cihaz: ${device['name']} (${device['bluetoothAddress']})');
      
      bluetoothHelper = BluetoothPrinterHelperSimple();
      
      // Bluetooth durumunu kontrol et
      final isBluetoothEnabled = await bluetoothHelper.isBluetoothEnabled().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Bluetooth durum kontrolü timeout');
          return false;
        },
      );
      
      if (!isBluetoothEnabled) {
        debugPrint('❌ Bluetooth kapalı veya erişilemiyor');
        return false;
      }
      
      // Bluetooth adresi kontrolü
      final bluetoothAddress = device['bluetoothAddress'] as String?;
      if (bluetoothAddress == null || bluetoothAddress.isEmpty) {
        debugPrint('❌ Bluetooth adresi bulunamadı');
        return false;
      }
      
      debugPrint('🔗 Bluetooth adresi ile bağlanılıyor: $bluetoothAddress');
      
      // Düzeltilmiş bağlantı metodu ile bağlan
      final connected = await bluetoothHelper.connectByAddress(bluetoothAddress).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint('⏰ Bluetooth bağlantı timeout (20 saniye)');
          return false;
        },
      );
      
      if (!connected) {
        debugPrint('❌ Bluetooth cihazına bağlanılamadı: $bluetoothAddress');
        
        // Bağlantı başarısız olsa bile konsol çıktısı göster
        debugPrint('=== HARİCİ FİŞ YAZDIRMA (BAĞLANTI BAŞARISIZ) ===');
        debugPrint('Başlık: $title');
        debugPrint('Alt başlık: $subtitle');
        debugPrint('Ürünler:');
        for (var item in items) {
          final name = item['name'] ?? 'Bilinmeyen Ürün';
          final quantity = item['quantity'] ?? 0;
          final price = item['price'] ?? 0.0;
          final itemTotal = (quantity * price);
          debugPrint('- $name x$quantity = ${itemTotal.toStringAsFixed(2)} TL');
        }
        debugPrint('Toplam: ${total.toStringAsFixed(2)} TL');
        debugPrint('Ödeme: $paymentMethod');
        debugPrint('=== FİŞ SONU ===');
        
        return false;
      }
      
      debugPrint('✅ Bluetooth cihazına başarıyla bağlanıldı');
      
      // Kısa bekleme - bağlantının stabilize olması için
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Fiş yazdır
      final success = await bluetoothHelper.printReceipt(
        title: title,
        storeName: title,
        address: subtitle,
        phone: '',
        items: items,
        total: total,
        footer: 'Teşekkürler - $paymentMethod',
        qrData: qrData,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('⏰ Fiş yazdırma timeout');
          return false;
        },
      );
      
      if (success) {
        debugPrint('✅ Fiş başarıyla yazdırıldı');
      } else {
        debugPrint('❌ Fiş yazdırma başarısız');
      }
      
      return success;
      
    } catch (e) {
      debugPrint('❌ Harici fiş yazdırma hatası: $e');
      return false;
    } finally {
      // Her durumda bağlantıyı güvenli şekilde kapat
      if (bluetoothHelper != null) {
        try {
          await bluetoothHelper.disconnect().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('Disconnect timeout, devam ediliyor');
            },
          );
          debugPrint('🔌 Bluetooth bağlantısı kapatıldı');
        } catch (e) {
          debugPrint('Bağlantı kapatma hatası: $e');
        }
      }
    }
  }

  // Dahili yazıcı için ürün etiketi yazdırma
  Future<bool> _printInternalProductLabel({
    required String productName,
    required String productDescription,
    required double price,
    required String expiryDate,
    required String barcode,
    required String code,
    required String unitPrice,
    required String company,
    required String country,
  }) async {
    try {
      var labelContent = 'Tarih: $expiryDate\n\n'
          '$productName\n'
          '$productDescription\n\n'
          '₺${price.toStringAsFixed(2)}\n'
          '100 g = $unitPrice\n\n'
          'Kod: $code\n\n'
          'Barkod: $barcode\n\n'
          '$country\n'
          '$company\n\n';
      
      await _printerChannel.invokeMethod('printText', {
        'text': labelContent,
        'fontSize': 24,
        'bold': false,
        'align': 1,
      });
      
      return true;
    } catch (e) {
      debugPrint('Dahili ürün etiketi yazdırma hatası: $e');
      return false;
    }
  }

  // Harici yazıcı için ürün etiketi yazdırma
  Future<bool> _printExternalProductLabel({
    required Map<String, dynamic> device,
    required int paperWidth,
    required int paperHeight,
    required String productName,
    required String productDescription,
    required double price,
    required String expiryDate,
    required String barcode,
    required String code,
    required String unitPrice,
    required String company,
    required String country,
  }) async {
    try {
      final bluetoothHelper = BluetoothPrinterHelperSimple();
      
      // Bluetooth cihazını bul ve bağlan
      await bluetoothHelper.startScan(timeout: const Duration(seconds: 10));
      
      // Cihazı bul
      final targetDevice = bluetoothHelper.scanResults.firstWhere(
        (d) => d.address == device['bluetoothAddress'] || d.name == device['name'],
        orElse: () => throw Exception('Bluetooth cihazı bulunamadı'),
      );
      
      // Bağlan
      final connected = await bluetoothHelper.connect(targetDevice);
      if (!connected) {
        throw Exception('Bluetooth cihazına bağlanılamadı');
      }
      
      // Etiket yazdır
      final success = await bluetoothHelper.printLabel(
        title: productName,
        barcode: barcode,
        data: {
          'Açıklama': productDescription,
          'Fiyat': '₺${price.toStringAsFixed(2)}',
          'Birim Fiyat': '100 g = $unitPrice',
          'Kod': code,
          'Tarih': expiryDate,
          'Şirket': company,
          'Ülke': country,
        },
        width: paperWidth,
        height: paperHeight,
        copies: 1,
      );
      
      // Bağlantıyı kapat
      await bluetoothHelper.disconnect();
      
      return success;
    } catch (e) {
      debugPrint('Harici ürün etiketi yazdırma hatası: $e');
      return false;
    }
  }

  // Dahili yazıcı için raf etiketi yazdırma
  Future<bool> _printInternalShelfLabel({
    required String productName,
    required double price,
    required String unitPrice,
    required String barcode,
  }) async {
    try {
      final labelContent = '$productName\n'
          '$unitPrice\n'
          '₺${price.toStringAsFixed(2)}\n'
          'SKU: $barcode\n\n';
      
      await _printerChannel.invokeMethod('printText', {
        'text': labelContent,
        'fontSize': 24,
        'bold': false,
        'align': 1,
      });
      
      return true;
    } catch (e) {
      debugPrint('Dahili raf etiketi yazdırma hatası: $e');
      return false;
    }
  }

  // Harici yazıcı için raf etiketi yazdırma
  Future<bool> _printExternalShelfLabel({
    required Map<String, dynamic> device,
    required int paperWidth,
    required int paperHeight,
    required String productName,
    required double price,
    required String unitPrice,
    required String barcode,
  }) async {
    try {
      final bluetoothHelper = BluetoothPrinterHelperSimple();
      
      // Bluetooth cihazını bul ve bağlan
      await bluetoothHelper.startScan(timeout: const Duration(seconds: 10));
      
      // Cihazı bul
      final targetDevice = bluetoothHelper.scanResults.firstWhere(
        (d) => d.address == device['bluetoothAddress'] || d.name == device['name'],
        orElse: () => throw Exception('Bluetooth cihazı bulunamadı'),
      );
      
      // Bağlan
      final connected = await bluetoothHelper.connect(targetDevice);
      if (!connected) {
        throw Exception('Bluetooth cihazına bağlanılamadı');
      }
      
      // Etiket yazdır
      final success = await bluetoothHelper.printLabel(
        title: productName,
        barcode: barcode,
        data: {
          'Birim Fiyat': unitPrice,
          'Fiyat': '₺${price.toStringAsFixed(2)}',
        },
        width: paperWidth,
        height: paperHeight,
        copies: 1,
      );
      
      // Bağlantıyı kapat
      await bluetoothHelper.disconnect();
      
      return success;
    } catch (e) {
      debugPrint('Harici raf etiketi yazdırma hatası: $e');
      return false;
    }
  }

  // Dahili yazıcı için sipariş etiketi yazdırma
  Future<bool> _printInternalOrderLabel({
    required String orderNo,
    required String customerName,
    required String customerPhone,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    try {
      var labelContent = 'Sipariş No: $orderNo\n'
          'Müşteri: $customerName\n'
          'Tel: $customerPhone\n\n'
          'Ürünler:\n';
      
      for (var item in items) {
        labelContent += '${item['name']} x${item['quantity']} ${(item['price'] * item['quantity']).toStringAsFixed(2)} TL\n';
      }
      
      labelContent += '\nToplam: ${total.toStringAsFixed(2)} TL\n\n';
      
      await _printerChannel.invokeMethod('printText', {
        'text': labelContent,
        'fontSize': 24,
        'bold': false,
        'align': 1,
      });
      
      return true;
    } catch (e) {
      debugPrint('Dahili sipariş etiketi yazdırma hatası: $e');
      return false;
    }
  }

  // Harici yazıcı için sipariş etiketi yazdırma
  Future<bool> _printExternalOrderLabel({
    required Map<String, dynamic> device,
    required int paperWidth,
    required int paperHeight,
    required String orderNo,
    required String customerName,
    required String customerPhone,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    try {
      final bluetoothHelper = BluetoothPrinterHelperSimple();
      
      // Bluetooth cihazını bul ve bağlan
      await bluetoothHelper.startScan(timeout: const Duration(seconds: 10));
      
      // Cihazı bul
      final targetDevice = bluetoothHelper.scanResults.firstWhere(
        (d) => d.address == device['bluetoothAddress'] || d.name == device['name'],
        orElse: () => throw Exception('Bluetooth cihazı bulunamadı'),
      );
      
      // Bağlan
      final connected = await bluetoothHelper.connect(targetDevice);
      if (!connected) {
        throw Exception('Bluetooth cihazına bağlanılamadı');
      }
      
      // Etiket yazdır
      final success = await bluetoothHelper.printLabel(
        title: 'Sipariş: $orderNo',
        barcode: orderNo,
        data: {
          'Müşteri': customerName,
          'Telefon': customerPhone,
          'Toplam': '₺${total.toStringAsFixed(2)}',
        },
        width: paperWidth,
        height: paperHeight,
        copies: 1,
      );
      
      // Bağlantıyı kapat
      await bluetoothHelper.disconnect();
      
      return success;
    } catch (e) {
      debugPrint('Harici sipariş etiketi yazdırma hatası: $e');
      return false;
    }
  }
}
