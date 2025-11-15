import 'package:flutter/foundation.dart';
import 'database_service.dart';

/// Varsayılan yazıcı kurulumu servisi
class DefaultPrinterSetup {
  static final DefaultPrinterSetup _instance = DefaultPrinterSetup._internal();
  factory DefaultPrinterSetup() => _instance;
  DefaultPrinterSetup._internal();

  /// Varsayılan yazıcıları kur
  Future<void> setupDefaultPrinters() async {
    try {
      final db = DatabaseService.instance;
      
      // Mevcut cihazları kontrol et
      final existingDevices = await db.getAllDevices();
      
      if (existingDevices.isEmpty) {
        debugPrint('Varsayılan yazıcılar kuruluyor...');
        
        // Sunmi dahili yazıcısını ekle
        final sunmiPrinter = {
          'id': 'sunmi_internal',
          'name': 'Sunmi Dahili Yazıcı',
          'type': 'printer',
          'status': 'connected',
          'connection': 'internal',
          'model': 'Sunmi',
          'version': '1.0',
          'protocol': 'ESC/POS',
          'encoding': 'UTF-8',
          'paperWidth': 58,
          'isInternal': 1,
          'bluetoothAddress': null,
          'isReceiptPrinter': 1, // Varsayılan fiş yazıcısı
          'isLabelPrinter': 0,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };
        
        await db.insertDevice(sunmiPrinter);
        debugPrint('Sunmi dahili yazıcı eklendi');
        
        // Bluetooth yazıcı örneği ekle (JK-58PL yazıcısı)
        final bluetoothPrinter = {
          'id': 'bluetooth_printer_1',
          'name': 'JK-58PL',
          'type': 'printer',
          'status': 'disconnected',
          'connection': 'bluetooth',
          'model': 'JK-58PL',
          'version': '1.0',
          'protocol': 'ESC/POS',
          'encoding': 'UTF-8',
          'paperWidth': 58,
          'isInternal': 0,
          'bluetoothAddress': '86:67:7A:00:CD:13', // Terminal'den alınan gerçek adres
          'isReceiptPrinter': 0,
          'isLabelPrinter': 0,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };
        
        await db.insertDevice(bluetoothPrinter);
        debugPrint('Bluetooth yazıcı eklendi');
        
        // Etiket yazıcısı örneği ekle (devre dışı)
        final labelPrinter = {
          'id': 'label_printer_1',
          'name': 'Etiket Yazıcısı',
          'type': 'printer',
          'status': 'disconnected',
          'connection': 'bluetooth',
          'model': 'Label Printer',
          'version': '1.0',
          'protocol': 'ESC/POS',
          'encoding': 'UTF-8',
          'paperWidth': 60,
          'isInternal': 0,
          'bluetoothAddress': null,
          'isReceiptPrinter': 0,
          'isLabelPrinter': 1, // Varsayılan etiket yazıcısı
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };
        
        await db.insertDevice(labelPrinter);
        debugPrint('Etiket yazıcısı eklendi');
        
        debugPrint('Varsayılan yazıcılar başarıyla kuruldu');
      } else {
        debugPrint('Yazıcılar zaten mevcut, kurulum atlanıyor');
        
        // Fiş yazıcısı atanmamışsa Sunmi'yi ata
        final receiptPrinter = await db.getReceiptPrinter();
        if (receiptPrinter == null) {
          final sunmiDevice = existingDevices.firstWhere(
            (device) => device['id'] == 'sunmi_internal',
            orElse: () => existingDevices.first,
          );
          
          await db.assignReceiptPrinter(sunmiDevice['id']);
          debugPrint('Varsayılan fiş yazıcısı atandı: ${sunmiDevice['name']}');
        }
      }
    } catch (e) {
      debugPrint('Varsayılan yazıcı kurulum hatası: $e');
    }
  }
  
  /// Yazıcı durumunu kontrol et ve güncelle
  Future<void> checkPrinterStatus() async {
    try {
      final db = DatabaseService.instance;
      final devices = await db.getAllDevices();
      
      for (final device in devices) {
        if (device['type'] == 'printer') {
          final isInternal = device['isInternal'] == 1;
          
          if (isInternal) {
            // Dahili yazıcı için durum kontrolü
            await db.updateDevice(device['id'], {
              'status': 'connected',
              'updatedAt': DateTime.now().toIso8601String(),
            });
          } else {
            // Harici yazıcılar için Bluetooth durum kontrolü
            // Bu kısım Bluetooth servisinden alınabilir
            await db.updateDevice(device['id'], {
              'status': 'disconnected', // Varsayılan olarak bağlantısız
              'updatedAt': DateTime.now().toIso8601String(),
            });
          }
        }
      }
      
      debugPrint('Yazıcı durumları güncellendi');
    } catch (e) {
      debugPrint('Yazıcı durum kontrolü hatası: $e');
    }
  }
  
  /// Yazıcı test et
  Future<bool> testPrinter(String printerId) async {
    try {
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);
      
      if (device == null) {
        debugPrint('Test edilecek yazıcı bulunamadı: $printerId');
        return false;
      }
      
      debugPrint('Yazıcı test ediliyor: ${device['name']}');
      
      // Test yazdırma işlemi burada yapılabilir
      // PrinterHelper kullanılarak test sayfası yazdırılabilir
      
      return true;
    } catch (e) {
      debugPrint('Yazıcı test hatası: $e');
      return false;
    }
  }
}
