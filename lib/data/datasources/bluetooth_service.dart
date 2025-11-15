import 'dart:async';
import 'dart:typed_data';
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../shared/utils/debug_config.dart';

/// Bluetooth yazıcı bağlantıları için yönetim servisi
/// bluetooth_print_plus paketi kullanılarak oluşturulmuştur
class BluetoothService {
  static final BluetoothService instance = BluetoothService._init();

  BluetoothService._init() {
    // Listener'lar initialize() içinde başlatılacak
  }

  // Bluetooth bağlantı durumu
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  bool _isInitialized = false;

  // Dinleyiciler
  StreamSubscription<List<BluetoothDevice>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BlueState>? _blueStateSubscription;
  StreamSubscription<ConnectState>? _connectStateSubscription;

  // Cihaz listesi
  List<BluetoothDevice> _devices = [];

  // Getters
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _connectedDevice != null;
  bool get isInitialized => _isInitialized;
  List<BluetoothDevice> get discoveredDevices => _devices;

  /// Listener'ları başlat - CRASH ÖNLEME: onError handler'ları eklendi
  void _initListeners() {
    try {
      DebugConfig.logDebug('Bluetooth listener\'ları başlatılıyor...');

      // CRASH ÖNLEME: onError handler'ları eklendi, cancelOnError: false
      _scanResultsSubscription = BluetoothPrintPlus.scanResults.listen(
        (event) {
          DebugConfig.logDebug('Tarama sonuçları: ${event.length} cihaz');
          _devices = event;
        },
        onError: (error) {
          DebugConfig.logError('Tarama sonuçları hatası', error);
        },
        cancelOnError: false,
      );

      _isScanningSubscription = BluetoothPrintPlus.isScanning.listen(
        (event) {
          DebugConfig.logDebug('Tarama durumu: $event');
        },
        onError: (error) {
          DebugConfig.logError('Tarama durumu hatası', error);
        },
        cancelOnError: false,
      );

      _blueStateSubscription = BluetoothPrintPlus.blueState.listen(
        (event) {
          DebugConfig.logDebug('Bluetooth durumu: $event');
        },
        onError: (error) {
          DebugConfig.logError('Bluetooth durumu hatası', error);
        },
        cancelOnError: false,
      );

      _connectStateSubscription = BluetoothPrintPlus.connectState.listen(
        (event) {
          DebugConfig.logDebug('Bağlantı durumu: $event');
          switch (event) {
            case ConnectState.connected:
              DebugConfig.logSuccess('Bağlantı kuruldu');
              break;
            case ConnectState.disconnected:
              _connectedDevice = null;
              DebugConfig.logWarning('Bağlantı kesildi');
              break;
          }
        },
        onError: (error) {
          DebugConfig.logError('Bağlantı durumu hatası', error);
          _connectedDevice = null;
        },
        cancelOnError: false,
      );

      DebugConfig.logSuccess('Bluetooth listener\'ları başlatıldı');
    } catch (e) {
      DebugConfig.logError('Listener başlatma hatası', e);
    }
  }

  /// Bluetooth'u başlat ve izinleri kontrol et
  Future<bool> initialize() async {
    if (_isInitialized) {
      DebugConfig.logWarning('Bluetooth servisi zaten başlatılmış');
      return true;
    }

    try {
      DebugConfig.logDebug('Bluetooth servisi başlatılıyor...');

      // Bluetooth izinlerini iste
      final bluetoothStatus = await Permission.bluetooth.request();
      final bluetoothScanStatus = await Permission.bluetoothScan.request();
      final bluetoothConnectStatus =
          await Permission.bluetoothConnect.request();
      final locationStatus = await Permission.location.request();

      if (!bluetoothStatus.isGranted ||
          !bluetoothScanStatus.isGranted ||
          !bluetoothConnectStatus.isGranted ||
          !locationStatus.isGranted) {
        DebugConfig.logError('Bluetooth izinleri reddedildi', null);
        return false;
      }

      // İzinler alındıktan SONRA listener'ları başlat
      _initListeners();

      _isInitialized = true;
      DebugConfig.logSuccess('Bluetooth servisi başarıyla başlatıldı');
      return true;
    } catch (e) {
      DebugConfig.logError('Bluetooth başlatma hatası', e);
      return false;
    }
  }

  /// Bluetooth'un açık olup olmadığını kontrol et
  Future<bool> isBluetoothEnabled() async {
    try {
      return BluetoothPrintPlus.isBlueOn;
    } catch (e) {
      DebugConfig.logError('Bluetooth durum kontrolü hatası', e);
      return false;
    }
  }

  /// Kaynakları serbest bırak
  void dispose() {
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _blueStateSubscription?.cancel();
    _connectStateSubscription?.cancel();

    // Bağlantıyı kes
    try {
      disconnect();
    } catch (e) {
      DebugConfig.logError('Bağlantı kesme hatası', e);
    }

    _isInitialized = false;
  }

  /// Bluetooth cihazlarını tara
  Future<List<BluetoothDevice>> startScan(
      {Duration duration = const Duration(seconds: 4)}) async {
    try {
      if (!_isInitialized) {
        final initialized = await initialize();
        if (!initialized) {
          DebugConfig.logError('Bluetooth başlatılamadı', null);
          return [];
        }
      }

      _devices.clear(); // Önceki sonuçları temizle

      DebugConfig.logDebug('Bluetooth tarama başlatılıyor...');

      // Taramayı başlat
      await BluetoothPrintPlus.startScan(timeout: duration);

      // Taranan cihazlar için bir gecikme ekle
      await Future.delayed(duration + const Duration(milliseconds: 500));

      DebugConfig.logSuccess(
          'Bluetooth tarama tamamlandı: ${_devices.length} cihaz bulundu');
      return _devices;
    } catch (e) {
      DebugConfig.logError('Bluetooth tarama hatası', e);
      return [];
    }
  }

  /// Taramayı durdur
  Future<void> stopScan() async {
    try {
      await BluetoothPrintPlus.stopScan();
      DebugConfig.logDebug('Bluetooth tarama durduruldu');
    } catch (e) {
      DebugConfig.logError('Tarama durdurma hatası', e);
    }
  }

  /// Bluetooth cihazına bağlan
  Future<bool> connect(BluetoothDevice device) async {
    if (_isConnecting) {
      DebugConfig.logWarning('Zaten bir bağlantı işlemi devam ediyor');
      return false;
    }

    if (isConnected && _connectedDevice?.address == device.address) {
      DebugConfig.logWarning('Bu cihaza zaten bağlı: ${device.name}');
      return true;
    }

    try {
      _isConnecting = true;

      DebugConfig.logDebug('Bluetooth cihazına bağlanılıyor: ${device.name}');

      // BACKUP'TAKİ ÇALIŞAN KOD - timeout ile await kullan
      try {
        DebugConfig.logDebug('BluetoothPrintPlus.connect çağrılıyor...');

        final result = await BluetoothPrintPlus.connect(device).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            DebugConfig.logWarning('Bluetooth bağlantı timeout (15 saniye)');
            return null; // NULL DÖNÜŞ - CRASH'İ ÖNLER!
          },
        );

        DebugConfig.logDebug(
            'Connect sonucu: $result (tip: ${result.runtimeType})');

        // Sonuç kontrolü
        if (result == true) {
          _connectedDevice = device;
          DebugConfig.logSuccess(
              'Bluetooth bağlantısı başarılı: ${device.name}');
          return true;
        } else if (result == false) {
          DebugConfig.logError('Bluetooth bağlantı reddedildi', null);
          _connectedDevice = null;
          return false;
        } else {
          // result null ise - BACKUP'TAKİ EXACT KOD!
          DebugConfig.logWarning(
              'Connect sonucu null, manuel test yapılıyor...');
          await Future.delayed(const Duration(seconds: 2));

          try {
            DebugConfig.logWarning(
                'Manuel kontrol: EventSink sorunu nedeniyle write testi atlanıyor');

            // Optimistik yaklaşım
            await Future.delayed(const Duration(seconds: 1));

            _connectedDevice = device;
            DebugConfig.logSuccess(
                'Manuel test: Optimistik bağlantı kabul edildi');
            DebugConfig.logWarning(
                'Gerçek bağlantı durumu yazdırma sırasında test edilecek');
            return true;
          } catch (e) {
            DebugConfig.logError('Manuel test hatası', e);
            _connectedDevice = null;
            return false;
          }
        }
      } catch (e) {
        // EventSink veya diğer hatalar
        DebugConfig.logError('Bluetooth bağlantı hatası', e);
        _connectedDevice = null;
        return false;
      }
    } catch (e) {
      DebugConfig.logError('Bluetooth bağlantı hatası', e);
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Bluetooth bağlantısını kes
  Future<bool> disconnect() async {
    try {
      DebugConfig.logDebug('Bluetooth bağlantısı kesiliyor...');

      await BluetoothPrintPlus.disconnect();

      _connectedDevice = null;
      DebugConfig.logSuccess('Bluetooth bağlantısı kesildi');
      return true;
    } catch (e) {
      DebugConfig.logError('Bluetooth bağlantı kesme hatası', e);
      return false;
    }
  }

  /// Bluetooth cihazı durumunu kontrol et
  Future<bool> checkConnection(BluetoothDevice device) async {
    if (_connectedDevice?.address != device.address) {
      // Farklı bir cihaza bağlıyız, önce bağlantıyı kes ve yeni cihaza bağlan
      await disconnect();
      return connect(device);
    }

    return isConnected;
  }

  /// Bluetooth cihazına veri gönder (ESC/POS komutları)
  Future<bool> sendData(Uint8List data) async {
    if (!isConnected) {
      DebugConfig.logError('Bluetooth bağlantısı yok', null);
      return false;
    }

    try {
      DebugConfig.logDebug('Veri gönderiliyor (${data.length} byte)...');

      await BluetoothPrintPlus.write(data);

      DebugConfig.logSuccess('Veri başarıyla gönderildi');
      return true;
    } catch (e) {
      DebugConfig.logError('Veri gönderme hatası', e);
      return false;
    }
  }

  /// Bluetooth cihaz adresinden BluetoothDevice nesnesi oluştur
  /// Bu fonksiyon veritabanından alınan cihaz adreslerini BluetoothDevice nesnesine dönüştürmek için kullanılır
  BluetoothDevice createBluetoothDevice(String address, String name) {
    return BluetoothDevice(name, address);
  }

  /// Bağlı cihaz bilgilerini al
  Map<String, dynamic>? getConnectedDeviceInfo() {
    if (_connectedDevice == null) return null;

    return {
      'name': _connectedDevice!.name,
      'address': _connectedDevice!.address,
      'type': _connectedDevice!.type,
      'connected': isConnected,
    };
  }

  /// Tüm eşleştirilmiş cihazları getir
  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      // bluetooth_print_plus paketinde bonded devices özelliği yoksa
      // tarama yaparak cihazları bulabiliriz
      return await startScan(duration: const Duration(seconds: 3));
    } catch (e) {
      DebugConfig.logError('Eşleştirilmiş cihazlar alınırken hata', e);
      return [];
    }
  }
}
