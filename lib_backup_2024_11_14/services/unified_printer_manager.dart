import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'bluetooth_printer_manager.dart';
import 'printer_service.dart';
import '../utils/error_handler.dart';
import '../models/device_model.dart';

// Yazıcı türleri
enum PrinterType { receipt, label }

// Yazıcı teknolojileri
enum PrinterTechnology { bluetooth, sunmi, network }

/// Merkezi yazıcı yönetim servisi
/// Tüm yazıcı işlemlerini (Bluetooth, Sunmi, vs.) tek bir yerden yönetir
class UnifiedPrinterManager {
  static final UnifiedPrinterManager _instance = UnifiedPrinterManager._internal();
  factory UnifiedPrinterManager() => _instance;
  UnifiedPrinterManager._internal();

  // Alt servisler
  final BluetoothPrinterManager _bluetoothManager = BluetoothPrinterManager();
  final PrinterService _printerService = PrinterService.instance;

  /// Yazıcı yöneticisini başlat
  Future<void> initialize() async {
    try {
      await _bluetoothManager.initialize();
      ErrorHandler.showInfo('Yazıcı yönetimi başlatıldı');
    } catch (e) {
      ErrorHandler.reportError(
        'Yazıcı Yönetimi Başlatma Hatası',
        'Yazıcı servisleri başlatılamadı.',
        details: e.toString(),
      );
    }
  }

  /// Kaynakları temizle
  void dispose() {
    _bluetoothManager.dispose();
  }

  /// Yazıcı ata
  Future<bool> assignPrinter({
    required PrinterType type,
    required String deviceId,
    required String deviceName,
    required PrinterTechnology technology,
  }) async {
    try {
      bool success = false;
      
      switch (type) {
        case PrinterType.receipt:
          success = await _printerService.assignReceiptPrinter(deviceId);
          break;
        case PrinterType.label:
          success = await _printerService.assignLabelPrinter(deviceId);
          break;
      }

      if (success) {
        final typeText = type == PrinterType.receipt ? 'Fiş' : 'Etiket';
        ErrorHandler.showSuccess('$typeText yazıcısı başarıyla atandı: $deviceName');
      }

      return success;
    } catch (e) {
      ErrorHandler.reportError(
        'Yazıcı Atama Hatası',
        'Yazıcı atanırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Yazıcı atamasını kaldır
  Future<bool> removePrinter(PrinterType type) async {
    try {
      bool success = false;
      
      switch (type) {
        case PrinterType.receipt:
          success = await _printerService.removeReceiptPrinter();
          break;
        case PrinterType.label:
          success = await _printerService.removeLabelPrinter();
          break;
      }

      if (success) {
        final typeText = type == PrinterType.receipt ? 'Fiş' : 'Etiket';
        ErrorHandler.showSuccess('$typeText yazıcısı ataması kaldırıldı');
      }

      return success;
    } catch (e) {
      ErrorHandler.reportError(
        'Yazıcı Kaldırma Hatası',
        'Yazıcı ataması kaldırılırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Atanmış yazıcıyı getir
  Future<Map<String, dynamic>?> getAssignedPrinter(PrinterType type) async {
    try {
      switch (type) {
        case PrinterType.receipt:
          return await _printerService.getReceiptPrinter();
        case PrinterType.label:
          return await _printerService.getLabelPrinter();
      }
    } catch (e) {
      ErrorHandler.reportError(
        'Yazıcı Bilgisi Alma Hatası',
        'Atanmış yazıcı bilgisi alınamadı.',
        details: e.toString(),
      );
      return null;
    }
  }

  /// Tüm yazıcı atamalarını getir
  Future<Map<String, Map<String, dynamic>?>> getAllAssignments() async {
    try {
      return await _printerService.getAllPrinterAssignments();
    } catch (e) {
      ErrorHandler.reportError(
        'Yazıcı Atamaları Alma Hatası',
        'Yazıcı atamaları alınamadı.',
        details: e.toString(),
      );
      return {'receipt': null, 'label': null};
    }
  }

  /// Bluetooth cihazlarını tara
  Future<List<DeviceModel>> scanBluetoothDevices() async {
    try {
      final devices = await _bluetoothManager.startScan();
      
      // BluetoothDevice'ları DeviceModel'e dönüştür
      return devices.map((device) => DeviceModel(
        id: device.address,
        name: device.name,
        type: DeviceType.printer,
        isInternal: false,
      )).toList();
    } catch (e) {
      ErrorHandler.reportError(
        'Bluetooth Tarama Hatası',
        'Bluetooth cihazları taranırken bir sorun oluştu.',
        details: e.toString(),
      );
      return [];
    }
  }

  /// Bluetooth cihazına bağlan
  Future<bool> connectToBluetoothDevice(String deviceAddress, String deviceName) async {
    try {
      final device = _bluetoothManager.createBluetoothDevice(deviceAddress, deviceName);
      return await _bluetoothManager.connect(device);
    } catch (e) {
      ErrorHandler.reportError(
        'Bluetooth Bağlantı Hatası',
        'Bluetooth cihazına bağlanırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Bluetooth bağlantısını kes
  Future<bool> disconnectBluetooth() async {
    try {
      final success = await _bluetoothManager.disconnect();
      if (success) {
        ErrorHandler.showInfo('Bluetooth bağlantısı kesildi');
      }
      return success;
    } catch (e) {
      ErrorHandler.reportError(
        'Bluetooth Bağlantı Kesme Hatası',
        'Bluetooth bağlantısı kesilirken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Yazıcıya yazdır (genel yazdırma fonksiyonu)
  Future<bool> print({
    required PrinterType type,
    required Uint8List data,
    String? deviceAddress,
  }) async {
    try {
      // Atanmış yazıcıyı kontrol et
      final assignedPrinter = await getAssignedPrinter(type);
      if (assignedPrinter == null) {
        ErrorHandler.reportError(
          'Yazıcı Bulunamadı',
          '${type == PrinterType.receipt ? 'Fiş' : 'Etiket'} yazıcısı atanmamış.',
        );
        return false;
      }

      // Yazıcı türüne göre yazdırma işlemi
      final printerType = assignedPrinter['type'] as String?;
      
      switch (printerType) {
        case 'bluetooth':
          return await _printViaBluetooth(data, assignedPrinter);
        case 'sunmi':
          return await _printViaSunmi(data);
        case 'network':
          return await _printViaNetwork(data, assignedPrinter);
        default:
          ErrorHandler.reportError(
            'Desteklenmeyen Yazıcı Türü',
            'Bu yazıcı türü desteklenmiyor: $printerType',
          );
          return false;
      }
    } catch (e) {
      ErrorHandler.reportError(
        'Yazdırma Hatası',
        'Yazdırma işlemi sırasında bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Bluetooth ile yazdır
  Future<bool> _printViaBluetooth(Uint8List data, Map<String, dynamic> printerInfo) async {
    try {
      // Bluetooth bağlantısını kontrol et
      final deviceAddress = printerInfo['address'] as String;
      final deviceName = printerInfo['name'] as String;
      
      final device = _bluetoothManager.createBluetoothDevice(deviceAddress, deviceName);
      final isConnected = await _bluetoothManager.checkConnection(device);
      
      if (!isConnected) {
        ErrorHandler.reportError(
          'Bluetooth Bağlantı Hatası',
          'Yazıcıya bağlantı kurulamadı.',
        );
        return false;
      }

      // Veriyi gönder
      return await _bluetoothManager.sendData(data);
    } catch (e) {
      ErrorHandler.reportError(
        'Bluetooth Yazdırma Hatası',
        'Bluetooth yazıcıya yazdırırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Sunmi ile yazdır
  Future<bool> _printViaSunmi(Uint8List data) async {
    try {
      // Sunmi yazıcı implementasyonu buraya gelecek
      debugPrint('Sunmi yazıcı ile yazdırma: ${data.length} byte');
      
      // Şimdilik simülasyon
      await Future.delayed(const Duration(milliseconds: 500));
      ErrorHandler.showSuccess('Sunmi yazıcıya başarıyla yazdırıldı');
      return true;
    } catch (e) {
      ErrorHandler.reportError(
        'Sunmi Yazdırma Hatası',
        'Sunmi yazıcıya yazdırırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Ağ yazıcısı ile yazdır
  Future<bool> _printViaNetwork(Uint8List data, Map<String, dynamic> printerInfo) async {
    try {
      // Ağ yazıcısı implementasyonu buraya gelecek
      final ipAddress = printerInfo['ip_address'] as String?;
      debugPrint('Ağ yazıcısına yazdırma: $ipAddress, ${data.length} byte');
      
      // Şimdilik simülasyon
      await Future.delayed(const Duration(milliseconds: 1000));
      ErrorHandler.showSuccess('Ağ yazıcısına başarıyla yazdırıldı');
      return true;
    } catch (e) {
      ErrorHandler.reportError(
        'Ağ Yazıcısı Yazdırma Hatası',
        'Ağ yazıcısına yazdırırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Yazıcı durumunu test et
  Future<bool> testPrinter(PrinterType type) async {
    try {
      final testData = _generateTestPrintData(type);
      final success = await print(type: type, data: testData);
      
      if (success) {
        ErrorHandler.showSuccess('Yazıcı testi başarılı');
      }
      
      return success;
    } catch (e) {
      ErrorHandler.reportError(
        'Yazıcı Test Hatası',
        'Yazıcı testi sırasında bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Test yazdırma verisi oluştur
  Uint8List _generateTestPrintData(PrinterType type) {
    final testText = type == PrinterType.receipt 
        ? 'FİŞ YAZICI TEST\n\nTarih: ${DateTime.now()}\nTest başarılı!\n\n\n'
        : 'ETİKET YAZICI TEST\n\nTest başarılı!\n';
    
    return Uint8List.fromList(testText.codeUnits);
  }

  /// Bağlı Bluetooth cihazını getir
  String? getConnectedBluetoothDevice() {
    final device = _bluetoothManager.connectedDevice;
    return device?.name;
  }

  /// Bluetooth bağlantı durumu
  bool get isBluetoothConnected => _bluetoothManager.isConnected;

  /// Bluetooth bağlanma durumu
  bool get isBluetoothConnecting => _bluetoothManager.isConnecting;
}
