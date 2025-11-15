import 'dart:async';
import 'package:flutter/services.dart';
import 'database_service.dart';
import '../../shared/utils/debug_config.dart';

/// Dahili (Sunmi) yazıcı işlemleri için servis
class InternalPrinterService {
  static final InternalPrinterService _instance = InternalPrinterService._internal();
  
  // Platform kanalları
  static const MethodChannel _printerChannel = MethodChannel('com.sunmi.printer');
  static const MethodChannel _scannerChannel = MethodChannel('com.sunmi.scanner');
  static const MethodChannel _nfcChannel = MethodChannel('com.sunmi.nfc');
  static const MethodChannel _drawerChannel = MethodChannel('com.sunmi.drawer');
  
  factory InternalPrinterService() => _instance;
  InternalPrinterService._internal();
  
  /// Yazıcı kontrolü
  Future<bool> hasPrinter() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('hasPrinter');
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('Yazıcı kontrol hatası', e);
      return false;
    }
  }
  
  /// Yazıcı sürümünü al
  Future<String> getPrinterVersion() async {
    try {
      final result = await _printerChannel.invokeMethod<String>('getPrinterVersion');
      return result ?? 'Bilinmiyor';
    } catch (e) {
      DebugConfig.logError('Yazıcı sürüm hatası', e);
      return 'Hata';
    }
  }
  
  /// Yazıcı seri numarasını al
  Future<String> getPrinterSerialNo() async {
    try {
      final result = await _printerChannel.invokeMethod<String>('getPrinterSerialNo');
      return result ?? 'Bilinmiyor';
    } catch (e) {
      DebugConfig.logError('Yazıcı seri no hatası', e);
      return 'Hata';
    }
  }

  /// Test sayfası yazdır
  Future<bool> printTestPage() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('printTestPage');
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('Test sayfası yazdırma hatası', e);
      return false;
    }
  }
  
  /// Metin yazdır
  Future<bool> printText(String text, {int fontSize = 24, bool bold = false, int align = 0}) async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('printText', {
        'text': text,
        'fontSize': fontSize,
        'bold': bold,
        'align': align,
      });
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('Metin yazdırma hatası', e);
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
      DebugConfig.logError('Barkod yazdırma hatası', e);
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
      DebugConfig.logError('QR kod yazdırma hatası', e);
      return false;
    }
  }
  
  /// Kağıt kes
  Future<bool> cutPaper() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('cutPaper');
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('Kağıt kesme hatası', e);
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
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        DebugConfig.logError('Yazıcı bulunamadı: $printerId');
        return false;
      }
      
      return await printTestPage();
    } catch (e) {
      DebugConfig.logError('Dahili cihaz test sayfası yazdırma hatası', e);
      return false;
    }
  }
  
  /// Gerçek donanımları tespit et
  static Future<Map<String, dynamic>> checkActualDevices() async {
    try {
      final Map<dynamic, dynamic> result = await _printerChannel.invokeMethod('checkDevices');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      DebugConfig.logError('Platform hatası: ${e.message}');
      return {'error': true, 'message': e.message};
    } catch (e) {
      DebugConfig.logError('Cihaz kontrolü hatası', e);
      return {'error': true, 'message': e.toString()};
    }
  }

  /// Barkod tarayıcı kontrolü
  Future<bool> hasScanner() async {
    try {
      final result = await _scannerChannel.invokeMethod<bool>('hasScanner');
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('Barkod tarayıcı kontrol hatası', e);
      return false;
    }
  }
  
  /// Barkod tarayıcı bilgilerini al
  Future<Map<String, dynamic>> getScannerInfo() async {
    try {
      final result = await _scannerChannel.invokeMethod<Map<dynamic, dynamic>>('getScannerInfo');
      return result?.cast<String, dynamic>() ?? {'model': 'Bilinmiyor', 'version': 'Bilinmiyor'};
    } catch (e) {
      DebugConfig.logError('Barkod tarayıcı bilgi hatası', e);
      return {'model': 'Hata', 'version': 'Hata'};
    }
  }
  
  /// Barkod tarama başlat
  Future<String?> startScan() async {
    try {
      final result = await _scannerChannel.invokeMethod<String>('startScan');
      return result;
    } catch (e) {
      DebugConfig.logError('Barkod tarama hatası', e);
      return null;
    }
  }
  
  /// Barkod tarama durdur
  Future<bool> stopScan() async {
    try {
      await _scannerChannel.invokeMethod('stopScan');
      return true;
    } catch (e) {
      DebugConfig.logError('Barkod tarama durdurma hatası', e);
      return false;
    }
  }

  /// NFC kontrolü
  Future<bool> hasNfc() async {
    try {
      final result = await _nfcChannel.invokeMethod<bool>('hasNfc');
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('NFC kontrol hatası', e);
      return false;
    }
  }
  
  /// NFC bilgilerini al
  Future<Map<String, dynamic>> getNfcInfo() async {
    try {
      final result = await _nfcChannel.invokeMethod<Map<dynamic, dynamic>>('getNfcInfo');
      return result?.cast<String, dynamic>() ?? {'model': 'Bilinmiyor', 'version': 'Bilinmiyor'};
    } catch (e) {
      DebugConfig.logError('NFC bilgi hatası', e);
      return {'model': 'Hata', 'version': 'Hata'};
    }
  }
  
  /// Para çekmecesi kontrolü
  Future<bool> hasDrawer() async {
    try {
      final result = await _drawerChannel.invokeMethod<bool>('hasDrawer');
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('Para çekmecesi kontrol hatası', e);
      return false;
    }
  }
  
  /// Para çekmecesi bilgilerini al
  Future<Map<String, dynamic>> getDrawerInfo() async {
    try {
      final result = await _drawerChannel.invokeMethod<Map<dynamic, dynamic>>('getDrawerInfo');
      return result?.cast<String, dynamic>() ?? {'model': 'Bilinmiyor', 'version': 'Bilinmiyor'};
    } catch (e) {
      DebugConfig.logError('Para çekmecesi bilgi hatası', e);
      return {'model': 'Hata', 'version': 'Hata'};
    }
  }
  
  /// Para çekmecesini aç
  Future<bool> openDrawer() async {
    try {
      final result = await _drawerChannel.invokeMethod<bool>('openDrawer');
      return result ?? false;
    } catch (e) {
      DebugConfig.logError('Para çekmecesi açma hatası', e);
      return false;
    }
  }
}
