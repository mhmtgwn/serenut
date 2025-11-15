import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../shared/utils/bluetooth_printer_controller.dart'
    as printer_commands;
import 'database_service.dart';
import '../../shared/utils/timeout_config.dart';

/// Birleştirilmiş Bluetooth yazıcı servisi
/// Tüm Bluetooth yazıcı işlemlerini tek yerden yönetir
class UnifiedBluetoothService {
  static final UnifiedBluetoothService _instance =
      UnifiedBluetoothService._internal();

  // Bağlantı durumu
  bool _isConnected = false;
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;

  // Stream subscriptions
  StreamSubscription<List<BluetoothDevice>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BlueState>? _blueStateSubscription;
  StreamSubscription<ConnectState>? _connectStateSubscription;

  List<BluetoothDevice> _scanResults = [];

  factory UnifiedBluetoothService() => _instance;
  UnifiedBluetoothService._internal() {
    _initListeners();
  }

  /// Getters
  bool get isConnected => _isConnected;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  List<BluetoothDevice> get scanResults => _scanResults;
  bool get isConnecting => _isConnecting;

  /// Dinleyicileri başlat - CRASH ÖNLEME: onError handler'ları eklendi
  void _initListeners() {
    try {
      _scanResultsSubscription = BluetoothPrintPlus.scanResults.listen(
        (event) {
          _scanResults = event;
        },
        onError: (error) {
          debugPrint('Tarama sonuçları hatası: $error');
        },
        cancelOnError: false,
      );

      _isScanningSubscription = BluetoothPrintPlus.isScanning.listen(
        (event) {
          // Tarama durumu değişikliği
        },
        onError: (error) {
          debugPrint('Tarama durumu hatası: $error');
        },
        cancelOnError: false,
      );

      _blueStateSubscription = BluetoothPrintPlus.blueState.listen(
        (event) {
          // Bluetooth durumu değişikliği
        },
        onError: (error) {
          debugPrint('Bluetooth durumu hatası: $error');
        },
        cancelOnError: false,
      );

      _connectStateSubscription = BluetoothPrintPlus.connectState.listen(
        (event) {
          switch (event) {
            case ConnectState.connected:
              _isConnected = true;
              break;
            case ConnectState.disconnected:
              _isConnected = false;
              _connectedDevice = null;
              break;
          }
        },
        onError: (error) {
          debugPrint('Bağlantı durumu hatası: $error');
          _isConnected = false;
          _connectedDevice = null;
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('Bluetooth dinleyici başlatma hatası: $e');
    }
  }

  /// Bluetooth durumunu kontrol et
  Future<bool> isBluetoothEnabled() async {
    try {
      return BluetoothPrintPlus.isBlueOn;
    } catch (e) {
      debugPrint('Bluetooth durum kontrolü hatası: $e');
      return false;
    }
  }

  /// Tarama başlat
  Future<void> startScan({Duration? timeout}) async {
    try {
      await BluetoothPrintPlus.startScan(
          timeout: timeout ?? TimeoutConfig.bluetoothScan);
    } catch (e) {
      debugPrint('Bluetooth tarama başlatma hatası: $e');
      rethrow;
    }
  }

  /// Taramayı durdur
  Future<void> stopScan() async {
    try {
      await BluetoothPrintPlus.stopScan();
    } catch (e) {
      debugPrint('Bluetooth tarama durdurma hatası: $e');
    }
  }

  /// Cihaza bağlan
  Future<bool> connect(BluetoothDevice device) async {
    try {
      if (_isConnecting) {
        return false;
      }

      _isConnecting = true;
      _connectedDevice = device;

      try {
        final result = await BluetoothPrintPlus.connect(device).timeout(
          TimeoutConfig.bluetoothConnect,
          onTimeout: () => null,
        );

        if (result == true) {
          _isConnected = true;
          return true;
        } else if (result == false) {
          _isConnected = false;
          _connectedDevice = null;
          return false;
        } else {
          // result null ise optimistik yaklaşım
          await Future.delayed(const Duration(seconds: 2));
          _isConnected = true;
          return true;
        }
      } catch (connectError) {
        _isConnected = false;
        _connectedDevice = null;
        return false;
      }
    } catch (e) {
      _isConnecting = false;
      _connectedDevice = null;
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Bluetooth adresine göre direkt bağlan
  Future<bool> connectByAddress(String address) async {
    try {
      if (_isConnecting) {
        return false;
      }

      _isConnecting = true;

      // Önce mevcut bağlantıyı kes
      if (_isConnected) {
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      try {
        final device = BluetoothDevice('Unknown', address);
        final result = await BluetoothPrintPlus.connect(device).timeout(
          TimeoutConfig.bluetoothConnect,
          onTimeout: () => null,
        );

        if (result == true) {
          _connectedDevice = device;
          _isConnected = true;
          return true;
        } else if (result == false) {
          return false;
        } else {
          // result null ise optimistik yaklaşım
          await Future.delayed(const Duration(seconds: 3));
          _connectedDevice = device;
          _isConnected = true;
          return true;
        }
      } catch (e) {
        return false;
      }
    } finally {
      _isConnecting = false;
    }
  }

  /// Veri yazma
  Future<void> write(Uint8List data) async {
    try {
      if (!_isConnected) {
        throw Exception('Yazıcıya bağlı değil');
      }

      try {
        await BluetoothPrintPlus.write(data).timeout(
          TimeoutConfig.bluetoothWrite,
          onTimeout: () {
            throw TimeoutException(
                'Yazma timeout', TimeoutConfig.bluetoothWrite);
          },
        );
      } catch (e) {
        // EventSink hatası ise bağlantıyı kapat
        if (e.toString().contains('EventSink') ||
            e.toString().contains('NullPointerException')) {
          _isConnected = false;
          _connectedDevice = null;
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Bağlantıyı kes
  Future<void> disconnect() async {
    try {
      if (!_isConnected) {
        return;
      }

      await BluetoothPrintPlus.disconnect().timeout(
        TimeoutConfig.bluetoothDisconnect,
        onTimeout: () {},
      );

      _isConnected = false;
      _connectedDevice = null;
    } catch (e) {
      _isConnected = false;
      _connectedDevice = null;
    }
  }

  /// Test sayfası yazdır
  Future<bool> printTestPage({
    required String printerId,
    int paperWidth = 58,
    bool keepConnection = true,
  }) async {
    try {
      final db = DatabaseService.instance;
      final device = await db.getDeviceById(printerId);

      if (device == null) {
        return false;
      }

      final String address = device['bluetoothAddress'] ?? '';
      final String name = device['name'] ?? 'Bilinmeyen Yazıcı';

      if (address.isEmpty) {
        return false;
      }

      final BluetoothDevice bluetoothDevice = BluetoothDevice(name, address);

      // Bağlantı kontrolü
      bool connected = _isConnected && _connectedDevice?.address == address;

      if (!connected) {
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 500));

        connected = await connect(bluetoothDevice);
        if (!connected) {
          return false;
        }
      }

      // Test sayfası oluştur
      Uint8List testData;
      try {
        testData = await printer_commands.PrinterDocuments.createTestPage(
          title: 'Test Sayfası',
          printerName: name,
          address: address,
        );
      } catch (e) {
        // Basit test sayfası oluştur
        final simpleCmd = printer_commands.EscCommand();
        await simpleCmd.cleanCommand();
        await simpleCmd.text(content: 'TEST SAYFASI\n\n');
        await simpleCmd.text(content: 'Yazıcı: $name\n');
        await simpleCmd.text(content: 'Test Başarılı!\n\n\n\n\n');
        testData = await simpleCmd.getCommand();
      }

      // Yazdır
      try {
        await write(testData);
        await Future.delayed(const Duration(milliseconds: 500));

        if (!keepConnection) {
          await disconnect();
        }

        return true;
      } catch (printError) {
        if (printError.toString().contains('socket closed')) {
          // Yeniden bağlanmayı dene
          await disconnect();
          await Future.delayed(const Duration(milliseconds: 500));

          connected = await connect(bluetoothDevice);
          if (connected) {
            try {
              await write(testData);
              if (!keepConnection) {
                await disconnect();
              }
              return true;
            } catch (retryError) {
              await disconnect();
              return false;
            }
          }
        }

        if (connected) {
          await disconnect();
        }
        return false;
      }
    } catch (e) {
      try {
        await disconnect();
      } catch (disconnectError) {
        // Ignore disconnect errors
      }
      return false;
    }
  }

  /// Fiş yazdır
  Future<bool> printReceipt({
    required String printerId,
    required String title,
    required String storeName,
    required String address,
    required String phone,
    required List<Map<String, dynamic>> items,
    required double total,
    required String footer,
    String? qrData,
  }) async {
    try {
      if (!_isConnected) {
        return false;
      }

      final receiptData =
          await printer_commands.PrinterDocuments.createReceiptDocument(
        title: title,
        storeName: storeName,
        address: address,
        phone: phone,
        items: items,
        total: total,
        footer: footer,
        qrData: qrData,
      ).timeout(
        TimeoutConfig.printerOperation,
        onTimeout: () {
          throw TimeoutException(
              'Fiş verisi oluşturma timeout', TimeoutConfig.printerOperation);
        },
      );

      await write(receiptData).timeout(
        TimeoutConfig.printerReceipt,
        onTimeout: () {
          throw TimeoutException(
              'Yazma işlemi timeout', TimeoutConfig.printerReceipt);
        },
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Etiket yazdır
  Future<bool> printLabel({
    required String title,
    required String barcode,
    required Map<String, String> data,
    int width = 50,
    int height = 30,
    int copies = 1,
  }) async {
    try {
      if (!_isConnected) {
        return false;
      }

      final labelData =
          await printer_commands.PrinterDocuments.createLabelDocument(
        title: title,
        barcode: barcode,
        data: data,
        width: width,
        height: height,
        copies: copies,
      );

      await write(labelData);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Temizlik
  void dispose() {
    try {
      _scanResultsSubscription?.cancel();
      _isScanningSubscription?.cancel();
      _blueStateSubscription?.cancel();
      _connectStateSubscription?.cancel();
      _scanResults.clear();

      if (_isConnected) {
        disconnect();
      }
    } catch (e) {
      debugPrint('Dispose hatası: $e');
    }
  }
}
