import 'package:flutter/services.dart';
import '../../shared/utils/debug_config.dart';

/// Sunmi dahili yazıcı servisi
class SunmiPrinterService {
  static final SunmiPrinterService instance = SunmiPrinterService._init();

  static const MethodChannel _printerChannel =
      MethodChannel('com.sunmi.printer');

  SunmiPrinterService._init();

  /// Dahili yazıcı var mı kontrol et
  Future<bool> hasPrinter() async {
    try {
      final result = await _printerChannel.invokeMethod<bool>('hasPrinter');
      DebugConfig.logDebug('Dahili yazıcı kontrolü: ${result ?? false}');
      return result ?? false;
    } catch (e) {
      DebugConfig.logDebug('Dahili yazıcı bulunamadı: $e');
      return false;
    }
  }

  /// Yazıcı sürümünü al
  Future<String> getPrinterVersion() async {
    try {
      final result =
          await _printerChannel.invokeMethod<String>('getPrinterVersion');
      return result ?? 'Bilinmiyor';
    } catch (e) {
      DebugConfig.logError('Yazıcı sürüm hatası', e);
      return 'Hata';
    }
  }

  /// Yazıcı seri numarasını al
  Future<String> getPrinterSerialNo() async {
    try {
      final result =
          await _printerChannel.invokeMethod<String>('getPrinterSerialNo');
      return result ?? 'Bilinmiyor';
    } catch (e) {
      DebugConfig.logError('Yazıcı seri no hatası', e);
      return 'Hata';
    }
  }

  /// Gerçek donanımları tespit et
  Future<Map<String, dynamic>> checkActualDevices() async {
    try {
      final Map<dynamic, dynamic> result =
          await _printerChannel.invokeMethod('checkDevices');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      DebugConfig.logError('Platform hatası', e);
      return {
        'printer': false,
        'scanner': false,
        'nfc': false,
        'drawer': false,
        'error': true,
        'message': e.message
      };
    } catch (e) {
      DebugConfig.logDebug('Cihaz kontrolü hatası (normal Android cihaz): $e');
      return {
        'printer': false,
        'scanner': false,
        'nfc': false,
        'drawer': false,
        'error': false,
      };
    }
  }

  /// Test sayfası yazdır (dahili yazıcı)
  Future<bool> printTestPage({int paperWidth = 58}) async {
    try {
      final Map<String, dynamic> params = {
        'paperWidth': paperWidth,
      };

      final bool result =
          await _printerChannel.invokeMethod('printTest', params);
      return result;
    } catch (e) {
      DebugConfig.logError('Dahili yazıcı test hatası', e);
      return false;
    }
  }
}
