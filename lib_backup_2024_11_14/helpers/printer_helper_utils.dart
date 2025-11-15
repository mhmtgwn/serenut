import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'printer_helper.dart';
import 'bluetooth_printer_helper_simple.dart';

Future<bool> connectToPrinter(Map<String, dynamic> device) async {
  try {
    debugPrint('Yazıcıya bağlanma işlemi başlatılıyor: ${device['name']}');
    
    if (device['isInternal'] == true) {
      // Dahili yazıcı, bağlantı gerekmez
      debugPrint('Dahili yazıcı, bağlantı gerekmez');
      return true;
    } else if (device['connection'] == 'bluetooth') {
      // BluetoothDevice nesnesi var mı kontrol et
      if (device['bluetoothDevice'] == null && 
          device['bluetoothAddress'] != null && 
          device['bluetoothAddress'].toString().isNotEmpty) {
        
        debugPrint('BluetoothDevice nesnesi oluşturuluyor: ${device['name']}, Adres: ${device['bluetoothAddress']}');
        try {
          // Adres kontrolü
          if (device['bluetoothAddress'] == null || device['bluetoothAddress'].toString().isEmpty) {
            debugPrint('Geçersiz Bluetooth adresi');
            return false;
          }
          
          device['bluetoothDevice'] = BluetoothDevice(
            device['name'] ?? 'Bilinmeyen Cihaz',
            device['bluetoothAddress'],
          );
        } catch (e) {
          debugPrint('BluetoothDevice oluşturma hatası: $e');
          return false;
        }
      }
      
      if (device['bluetoothDevice'] == null) {
        debugPrint('BluetoothDevice nesnesi bulunamadı');
        return false;
      }
      
      try {
        // Yeni bağlantı işleyicisini kullan
        final bluetoothHandler = BluetoothPrinterHelperSimple();
        
        // Bağlantı durumunu kontrol et
        try {
          final isBluetoothOn = await _isBluetoothEnabled();
          if (!isBluetoothOn) {
            debugPrint('Bluetooth kapalı, bağlantı kurulamaz');
            return false;
          }
        } catch (e) {
          debugPrint('Bluetooth durumu kontrolünde hata: $e');
          // Hatayı yut ve devam et
        }
        
        // EventSink null hatalarını önleyen güvenli bağlantı yöntemi
        final connected = await bluetoothHandler.connect(device['bluetoothDevice']);
        debugPrint('Bluetooth bağlantı sonucu: ${connected ? "Başarılı" : "Başarısız"}');
        return connected;
      } catch (e) {
        debugPrint('Bluetooth bağlantı hatası: $e');
        return false;
      }
    } else {
      debugPrint('Desteklenmeyen bağlantı türü: ${device['connection']}');
      return false;
    }
  } catch (e) {
    debugPrint('connectToPrinter hatası: $e');
    return false;
  }
}

// Bluetooth durumunu kontrol et
Future<bool> _isBluetoothEnabled() async {
  try {
    final blueState = await BluetoothPrintPlus.blueState.first;
    return blueState == BlueState.blueOn;
  } catch (e) {
    debugPrint('Bluetooth durumu kontrolünde hata: $e');
    // Hata durumunda varsayılan olarak açık kabul et
    return true;
  }
}

// Alternatif bağlantı yöntemi

Future<void> disconnectPrinter(Map<String, dynamic> device) async {
  try {
    if (device['isInternal'] == true) {
      // Dahili yazıcı, bağlantı kesme gerekmez
      return;
    } else if (device['connection'] == 'bluetooth') {
      // Yeni bağlantı işleyicisini kullan
      final bluetoothHandler = BluetoothPrinterHelperSimple();
      await bluetoothHandler.disconnect();
    }
  } catch (e) {
    debugPrint('disconnectPrinter hatası: $e');
  }
}

Future<bool> testPrint(Map<String, dynamic> device) async {
  try {
    if (device['isInternal'] == true) {
      return await PrinterHelper().printInternalDeviceTestPage(
        printerId: device['id'],
        protocol: device['protocol'] ?? 'esc_pos',
        paperWidth: device['paperWidth'] ?? 58,
      );
    } else if (device['connection'] == 'bluetooth') {
      return await PrinterHelper().printExternalDeviceTestPage(
        printerId: device['id'],
        protocol: device['protocol'] ?? 'esc_pos',
        paperWidth: device['paperWidth'] ?? 58,
      );
    }
    return false;
  } catch (e) {
    debugPrint('testPrint hatası: $e');
    return false;
  }
} 