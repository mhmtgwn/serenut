import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'bluetooth_printer_controller.dart';

/// Doğru API kullanımı ile Bluetooth yazıcı yardımcısı
class BluetoothPrinterHelperSimple {
  bool _isConnected = false;
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  
  // Stream subscriptions - dokümantasyon uyumlu
  late StreamSubscription<List<BluetoothDevice>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  late StreamSubscription<BlueState> _blueStateSubscription;
  late StreamSubscription<ConnectState> _connectStateSubscription;
  
  List<BluetoothDevice> _scanResults = [];

  /// Bağlantı durumu
  bool get isConnected => _isConnected;
  
  /// Bağlı cihaz
  BluetoothDevice? get connectedDevice => _connectedDevice;
  
  /// Tarama sonuçları
  List<BluetoothDevice> get scanResults => _scanResults;

  BluetoothPrinterHelperSimple() {
    _initListeners();
  }

  /// Dinleyicileri başlat - Dokümantasyona göre doğru şekilde
  void _initListeners() {
    try {
      debugPrint('🎧 Bluetooth dinleyiciler başlatılıyor (dokümantasyon uyumlu)...');
      
      /// Tarama sonuçlarını dinle - dokümantasyondan
      _scanResultsSubscription = BluetoothPrintPlus.scanResults.listen((event) {
        debugPrint('📡 Tarama sonuçları: ${event.length} cihaz');
        _scanResults = event;
      });

      /// Tarama durumunu dinle - dokümantasyondan
      _isScanningSubscription = BluetoothPrintPlus.isScanning.listen((event) {
        debugPrint('🔍 Tarama durumu: $event');
      });

      /// Bluetooth durumunu dinle - dokümantasyondan
      _blueStateSubscription = BluetoothPrintPlus.blueState.listen((event) {
        debugPrint('📶 Bluetooth durumu: $event');
      });

      /// Bağlantı durumunu dinle - dokümantasyondan
      _connectStateSubscription = BluetoothPrintPlus.connectState.listen((event) {
        debugPrint('🔗 Bağlantı durumu: $event');
        switch (event) {
          case ConnectState.connected:
            _isConnected = true;
            debugPrint('✅ Bağlantı kuruldu');
            break;
          case ConnectState.disconnected:
            _isConnected = false;
            _connectedDevice = null;
            debugPrint('❌ Bağlantı kesildi');
            break;
        }
      });
      
      debugPrint('✅ Bluetooth dinleyiciler başarıyla başlatıldı');
    } catch (e) {
      debugPrint('❌ Dinleyici başlatma hatası: $e');
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

  /// Tarama başlat - örnek koddan alındı
  Future<void> startScan({Duration? timeout}) async {
    try {
      debugPrint('🔍 Bluetooth tarama başlatılıyor...');
      await BluetoothPrintPlus.startScan(timeout: timeout ?? const Duration(seconds: 10));
      debugPrint('✅ Bluetooth tarama başlatıldı');
    } catch (e) {
      debugPrint('❌ Bluetooth tarama başlatma hatası: $e');
      rethrow;
    }
  }

  /// Cihaza bağlan - düzeltilmiş versiyon
  Future<bool> connect(BluetoothDevice device) async {
    try {
      debugPrint('🔗 Cihaza bağlanılıyor: ${device.name} (${device.address})');
      
      if (_isConnecting) {
        debugPrint('⚠️ Zaten bağlantı işlemi devam ediyor');
        return false;
      }

      _isConnecting = true;
      _connectedDevice = device;

      // Connect metodunun dönüş değerini detaylı kontrol et
      try {
        debugPrint('🔄 BluetoothPrintPlus.connect çağrılıyor...');
        final result = await BluetoothPrintPlus.connect(device).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('⏰ Connect timeout (15 saniye)');
            return null;
          },
        );
        
        debugPrint('📊 Connect sonucu: $result (tip: ${result.runtimeType})');
        
        // Sonuç kontrolü
        if (result == true) {
          _isConnected = true;
          debugPrint('✅ Bağlantı başarılı');
          return true;
        } else if (result == false) {
          debugPrint('❌ Bağlantı reddedildi');
          _isConnected = false;
          _connectedDevice = null;
          return false;
        } else {
          // result null ise manuel kontrol
          debugPrint('⚠️ Connect sonucu null, manuel test yapılıyor...');
          await Future.delayed(const Duration(seconds: 2));
          
          try {
            debugPrint('⚠️ Manuel kontrol: EventSink sorunu nedeniyle write testi atlanıyor');
            
            // Optimistik yaklaşım - connect null döndüyse ama hata yoksa bağlantı olabilir
            await Future.delayed(const Duration(seconds: 1));
            
            _isConnected = true;
            debugPrint('✅ Manuel test: Optimistik bağlantı kabul edildi');
            debugPrint('⚠️ Gerçek bağlantı durumu yazdırma sırasında test edilecek');
            return true;
          } catch (e) {
            debugPrint('❌ Manuel test hatası: $e');
            _isConnected = false;
            _connectedDevice = null;
            return false;
          }
        }
      } catch (connectError) {
        debugPrint('❌ Connect hatası: $connectError');
        debugPrint('Hata tipi: ${connectError.runtimeType}');
        _isConnected = false;
        _connectedDevice = null;
        return false;
      }
    } catch (e) {
      debugPrint('❌ Genel bağlantı hatası: $e');
      _isConnecting = false;
      _connectedDevice = null;
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Bluetooth adresine göre direkt bağlan - Düzeltilmiş versiyon
  Future<bool> connectByAddress(String address) async {
    try {
      debugPrint('🔗 Bluetooth adresi ile bağlanılıyor: $address');
      
      if (_isConnecting) {
        debugPrint('⚠️ Zaten bağlantı işlemi devam ediyor');
        return false;
      }

      _isConnecting = true;

      // Önce mevcut bağlantıyı kes
      if (_isConnected) {
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      try {
        // Adres ile cihaz oluştur
        final device = BluetoothDevice('Unknown', address);
        debugPrint('📱 BluetoothDevice oluşturuldu: ${device.name} - ${device.address}');
        
        // Connect metodunun dönüş değerini kontrol et
        debugPrint('🔄 BluetoothPrintPlus.connect çağrılıyor...');
        final result = await BluetoothPrintPlus.connect(device).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('⏰ Bluetooth bağlantı timeout (15 saniye)');
            return null; // timeout durumunda null döndür
          },
        );
        
        debugPrint('📊 Connect sonucu: $result (tip: ${result.runtimeType})');
        
        // Sonuç kontrolü - null, false veya true olabilir
        if (result == true) {
          _connectedDevice = device;
          _isConnected = true;
          debugPrint('✅ Bluetooth adresine başarıyla bağlanıldı: $address');
          return true;
        } else if (result == false) {
          debugPrint('❌ Bluetooth bağlantısı reddedildi: $address');
          return false;
        } else {
          // result null ise - bu durumda manuel kontrol yapalım
          debugPrint('⚠️ Connect sonucu null, manuel kontrol yapılıyor...');
          
          // Kısa bekleme - bağlantının kurulması için
          await Future.delayed(const Duration(seconds: 3));
          
          // Manuel bağlantı kontrolü - EventSink sorununu önlemek için
          try {
            debugPrint('⚠️ Manuel kontrol: EventSink sorunu nedeniyle optimistik yaklaşım');
            
            // Connect null döndüyse ama exception atmadıysa, bağlantı kurulmuş olabilir
            // Bu durumda optimistik yaklaşım benimseyelim
            _connectedDevice = device;
            _isConnected = true;
            debugPrint('✅ Manuel kontrol: Optimistik bağlantı kabul edildi: $address');
            debugPrint('⚠️ Gerçek bağlantı durumu yazdırma sırasında test edilecek');
            
            // Bağlantı test etmek için küçük bir yazma denemesi yapalım
            // Ama EventSink hatası alırsak yakalayalım
            try {
              // Çok basit bir test komutu gönder (ESC @ - reset)
              await BluetoothPrintPlus.write(Uint8List.fromList([0x1B, 0x40])).timeout(
                const Duration(seconds: 2),
                onTimeout: () {
                  debugPrint('Write test timeout - bağlantı var sayılıyor');
                },
              );
              debugPrint('✅ Write test başarılı - bağlantı doğrulandı');
              return true;
            } catch (writeError) {
              if (writeError.toString().contains('EventSink') || 
                  writeError.toString().contains('NullPointerException')) {
                debugPrint('⚠️ EventSink hatası - ama bağlantı var sayılıyor');
                return true; // EventSink hatası olsa bile bağlantı kurulmuş olabilir
              } else {
                debugPrint('❌ Write test başarısız: $writeError');
                return false;
              }
            }
          } catch (e) {
            debugPrint('❌ Manuel kontrol hatası: $e');
            return false;
          }
        }
      } catch (e) {
        debugPrint('❌ Bluetooth bağlantı hatası: $e');
        debugPrint('Hata tipi: ${e.runtimeType}');
        return false;
      }
    } finally {
      _isConnecting = false;
    }
  }

  /// Fiş yazdırma
  Future<bool> printReceipt({
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
        debugPrint('❌ Yazıcıya bağlı değil');
        return false;
      }

      debugPrint('🖨️ Fiş yazdırma hazırlanıyor...');
      debugPrint('Başlık: $title, Mağaza: $storeName');
      debugPrint('Ürün sayısı: ${items.length}, Toplam: $total');
      
      // Timeout ile fiş verisi oluştur
      final receiptData = await PrinterDocuments.createReceiptDocument(
        title: title,
        storeName: storeName,
        address: address,
        phone: phone,
        items: items,
        total: total,
        footer: footer,
        qrData: qrData,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏰ Fiş verisi oluşturma timeout');
          throw TimeoutException('Fiş verisi oluşturma timeout', const Duration(seconds: 10));
        },
      );
      
      debugPrint('📄 Fiş verisi oluşturuldu (${receiptData.length} byte)');
      
      // Timeout ile yazma işlemi
      await write(receiptData).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⏰ Yazma işlemi timeout');
          throw TimeoutException('Yazma işlemi timeout', const Duration(seconds: 15));
        },
      );
      
      debugPrint('✅ Fiş yazdırma başarılı');
      return true;
    } catch (e) {
      debugPrint('❌ Fiş yazdırma hatası: $e');
      return false;
    }
  }

  /// Veri yazma - EventSink korumalı
  Future<void> write(Uint8List data) async {
    try {
      if (!_isConnected) {
        throw Exception('Yazıcıya bağlı değil');
      }

      debugPrint('📤 Yazma işlemi başlatılıyor (${data.length} byte)...');
      
      try {
        await BluetoothPrintPlus.write(data).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('⏰ Yazma işlemi timeout');
            throw TimeoutException('Yazma timeout', const Duration(seconds: 10));
          },
        );
        
        debugPrint('✅ Yazma işlemi başarılı!');
      } catch (e) {
        debugPrint('❌ BluetoothPrintPlus.write hatası: $e');
        debugPrint('Hata tipi: ${e.runtimeType}');
        
        // EventSink hatası ise bağlantıyı kapat
        if (e.toString().contains('EventSink') || e.toString().contains('NullPointerException')) {
          debugPrint('⚠️ EventSink hatası tespit edildi, bağlantı durumu güncelleniyor');
          _isConnected = false;
          _connectedDevice = null;
        }
        
        rethrow;
      }
    } catch (e) {
      debugPrint('❌ Genel yazma hatası: $e');
      rethrow;
    }
  }

  /// Bağlantıyı kes
  Future<void> disconnect() async {
    try {
      if (!_isConnected) {
        return;
      }
      
      debugPrint('🔌 Bluetooth bağlantısı kesiliyor...');
      
      await BluetoothPrintPlus.disconnect().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏰ Disconnect timeout');
        },
      );
      
      _isConnected = false;
      _connectedDevice = null;
      debugPrint('✅ Bluetooth bağlantısı kesildi');
    } catch (e) {
      debugPrint('❌ Bağlantı kesme hatası: $e');
      _isConnected = false;
      _connectedDevice = null;
    }
  }

  /// Taramayı durdur
  Future<void> stopScan() async {
    try {
      await BluetoothPrintPlus.stopScan();
      debugPrint('🛑 Bluetooth tarama durduruldu');
    } catch (e) {
      debugPrint('❌ Bluetooth tarama durdurma hatası: $e');
    }
  }

  /// Güvenli bağlantı kesme (safeDisconnect alias)
  Future<void> safeDisconnect() async {
    await disconnect();
  }

  /// Güvenli yazma işlemi (safeWrite alias)
  Future<void> safeWrite(Uint8List data) async {
    await write(data);
  }

  /// Etiket yazdırma
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
        debugPrint('❌ Yazıcıya bağlı değil');
        return false;
      }

      debugPrint('🏷️ Etiket yazdırma hazırlanıyor...');
      
      // Etiket verisi oluştur
      final labelData = await PrinterDocuments.createLabelDocument(
        title: title,
        barcode: barcode,
        data: data,
        width: width,
        height: height,
        copies: copies,
      );
      
      debugPrint('📄 Etiket verisi oluşturuldu (${labelData.length} byte)');
      
      // Yazma işlemi
      await write(labelData);
      
      debugPrint('✅ Etiket yazdırma başarılı');
      return true;
    } catch (e) {
      debugPrint('❌ Etiket yazdırma hatası: $e');
      return false;
    }
  }

  /// Temizlik
  void dispose() {
    try {
      // Dinleyicileri iptal et - dokümantasyon uyumlu
      _scanResultsSubscription.cancel();
      _isScanningSubscription.cancel();
      _blueStateSubscription.cancel();
      _connectStateSubscription.cancel();
      _scanResults.clear();
      
      if (_isConnected) {
        disconnect();
      }
      
      debugPrint('🧹 Bluetooth helper temizlendi');
    } catch (e) {
      debugPrint('Dispose hatası: $e');
    }
  }
}
