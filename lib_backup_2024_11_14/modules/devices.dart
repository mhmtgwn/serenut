import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import '../helpers/printer_helper.dart';
import '../helpers/bluetooth_printer_helper_simple.dart';
import 'device_settings.dart';
import 'add_device.dart';
import '../services/database_service.dart';
import '../services/bluetooth_printer_manager.dart';
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';

/// Cihazlar modülü - Yazıcılar ve diğer cihazları yönetmek için ekran
class DevicesModule extends StatefulWidget {
  const DevicesModule({super.key});

  @override
  State<DevicesModule> createState() => _DevicesModuleState();
}

class _DevicesModuleState extends State<DevicesModule> with TickerProviderStateMixin {
  final List<Map<String, dynamic>> _devices = [];
  final List<String> _deviceIds = [];
  
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  String _connectionStatus = '';
  
  // Image picker
  
  // Bluetooth yazıcı değişkenleri
  List<BluetoothDevice> _bluetoothDevices = [];
  StreamSubscription<List<BluetoothDevice>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BlueState>? _blueStateSubscription;
  StreamSubscription<ConnectState>? _connectStateSubscription;

  // Platform kanalları
  
  final BluetoothPrinterManager _bluetoothManager = BluetoothPrinterManager();

  @override
  void initState() {
    super.initState();
    // Cihazları hemen yükle, sonra Bluetooth bağlantısını kur
    Future.microtask(() => _loadDevices());
    // Bluetooth bağlantısını biraz geciktirerek başlat
    Future.delayed(const Duration(milliseconds: 500), () => _initBluetooth());
    
    // Periyodik olarak bağlantı durumunu kontrol et
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _checkConnectionStatus();
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _blueStateSubscription?.cancel();
    _connectStateSubscription?.cancel();
    super.dispose();
  }
  
  /// Bluetooth Print Plus dinleyicilerini başlatır
  Future<void> _initBluetooth() async {
    try {
      // Bluetooth izinlerini iste
      await Permission.bluetooth.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.location.request();
      
      // Bluetooth yöneticisini başlat
      await _bluetoothManager.initialize();
      
      // Bluetooth tarama sonuçlarını dinle
      _scanResultsSubscription = BluetoothPrintPlus.scanResults.listen((devices) {
        if (mounted) {
          setState(() {
            _bluetoothDevices = devices;
            // Bulunan bluetooth cihazlarını listeye ekle
            for (var device in _bluetoothDevices) {
                _addBluetoothDevice(device);
            }
          });
        }
      });
      
      // Tarama durumunu dinle
      _isScanningSubscription = BluetoothPrintPlus.isScanning.listen((scanning) {
        if (mounted) {
          setState(() {
            _isScanning = scanning;
          });
        }
      });
        
      // Bluetooth durumunu dinle
      _blueStateSubscription = BluetoothPrintPlus.blueState.listen((state) {
        debugPrint('Bluetooth durumu: $state');
      });
      
      // Bağlantı durumunu dinle
      _connectStateSubscription = BluetoothPrintPlus.connectState.listen((state) {
        if (mounted) {
          setState(() {
            _connectionStatus = state == ConnectState.connected
                ? 'Bağlandı'
                : state == ConnectState.disconnected
                    ? 'Bağlantı kesildi'
                    : 'Bağlanıyor...';
          });
        }
      });
    } catch (e) {
      debugPrint('Bluetooth init hatası: $e');
    }
  }
  
  /// Bluetooth cihazını listeye ekler (yalnızca bir kez)
  void _addBluetoothDevice(BluetoothDevice device) {
    // ID zaten varsa ekleme (aynı cihazın tekrar eklenmesini önle)
    if (_deviceIds.contains(device.address)) return;
    
    // Boş isimli cihazları atlayabiliriz
    if (device.name.isEmpty) return;
    
    // Bluetooth cihazlarını otomatik eklemeyi durdurduk
    // Cihazlar sadece + butonu ile eklenir
    // _deviceIds.add(device.address);
    // _devices.add({
    //   'id': device.address,
    //   'name': device.name.isNotEmpty ? device.name : 'Bilinmeyen Cihaz',
    //   'type': 'printer', // Varsayılan olarak yazıcı
    //   'status': 'disconnected',
    //   'connection': 'bluetooth',
    //   'model': 'Bluetooth Yazıcı',
    //   'protocol': 'esc_pos',
    //   'encoding': 'UTF-8',
    //   'paperWidth': 58,
    //   'isInternal': false,
    //   'bluetoothDevice': device,
    // });
  }

  /// Harici yazıcıyı kalıcı olarak veritabanına ekler
  Future<bool> _saveExternalPrinter(Map<String, dynamic> device) async {
    try {
      debugPrint('Harici yazıcı veritabanına kaydediliyor: ${device['name']}');
      
      // Bluetooth cihazı bilgilerini kontrol et
      String? bluetoothAddress;
      if (device['bluetoothDevice'] != null) {
        bluetoothAddress = device['bluetoothDevice'].address;
        debugPrint('BluetoothDevice nesnesinden adres alındı: $bluetoothAddress');
      } else if (device['bluetoothAddress'] != null && device['bluetoothAddress'].toString().isNotEmpty) {
        bluetoothAddress = device['bluetoothAddress'];
        debugPrint('bluetoothAddress alanından adres alındı: $bluetoothAddress');
      }
      
      // Cihazın veritabanı formatında olduğundan emin ol
      final deviceData = {
        'id': device['id'],
        'name': device['name'],
        'type': device['type'] ?? 'printer',
        'status': device['status'] ?? 'disconnected',
        'connection': device['connection'] ?? 'bluetooth',
        'model': device['model'] ?? 'Bluetooth Yazıcı',
        'version': device['version'] ?? '',
        'protocol': device['protocol'] ?? 'esc_pos',
        'encoding': device['encoding'] ?? 'UTF-8',
        'paperWidth': device['paperWidth'] ?? 58,
        'isInternal': false, // Harici cihazlar için her zaman false
        'bluetoothAddress': bluetoothAddress ?? device['id'],
        'bluetoothDevice': device['bluetoothDevice'], // BluetoothDevice nesnesi de ekle
      };
      
      // Veritabanına kaydet
      await DatabaseService.instance.saveDevice(deviceData);
      
      // Cihaz listesini güncelle
      await _loadDevices();
      
      return true;
    } catch (e) {
      debugPrint('Harici yazıcı kaydedilirken hata: $e');
      return false;
    }
  }

  /// Cihazları yükle
  Future<void> _loadDevices() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    // Tüm verileri temizle
    _clearDeviceData();
    
    try {
      debugPrint('Cihazlar yükleniyor...');
      
      // Önce gerçek donanımları kontrol et
      final actualDevices = await PrinterHelper.checkActualDevices();
      debugPrint('Gerçek donanım durumu: $actualDevices');
      
      // Doğrudan Sunmi cihazlarını kontrol et ve ekle
      await _checkSunmiDevicesInBackground();
      
      // Veritabanından harici cihazları yükle
      final devices = await DatabaseService.instance.getAllDevices();
      debugPrint('Veritabanından yüklenen cihaz sayısı: ${devices.length}');
      
      // Harici cihazları filtrele ve ekle
      for (final device in devices) {
        final deviceId = device['id'];
        final isInternal = device['isInternal'] == 1;
        
        // Sadece harici cihazları ekle (dahili cihazlar zaten eklendi)
        if (!isInternal && !_deviceIds.contains(deviceId)) {
          debugPrint('Harici cihaz ekleniyor: ${device['name']}, ID: $deviceId');
          
          // Cihazı kopyala ve gerekli dönüşümleri yap
          final deviceCopy = Map<String, dynamic>.from(device);
          
          // isInternal değerini boolean'a dönüştür
          deviceCopy['isInternal'] = deviceCopy['isInternal'] == 1;
          
          // Bluetooth cihazı ise BluetoothDevice nesnesi oluştur
          if (deviceCopy['connection'] == 'bluetooth' && 
              deviceCopy['bluetoothAddress'] != null && 
              deviceCopy['bluetoothAddress'].toString().isNotEmpty) {
            
            debugPrint('Bluetooth cihazı için nesne oluşturuluyor: ${deviceCopy['name']}, Adres: ${deviceCopy['bluetoothAddress']}');
            deviceCopy['bluetoothDevice'] = BluetoothDevice(
              deviceCopy['name'] ?? 'Bilinmeyen Cihaz',
              deviceCopy['bluetoothAddress'],
            );
          }
          
          _deviceIds.add(deviceId);
          _devices.add(deviceCopy);
        }
      }
      
      // Cihaz listesini güncelle
      setState(() {
        _isLoading = false;
        debugPrint('Cihaz listesi güncellendi. Toplam cihaz sayısı: ${_devices.length}');
        debugPrint('Dahili cihaz sayısı: ${_devices.where((d) => d['isInternal'] == true).length}');
        debugPrint('Harici cihaz sayısı: ${_devices.where((d) => d['isInternal'] == false).length}');
        
        // Tüm cihazları logla
        for (var device in _devices) {
          debugPrint('Cihaz: ${device["name"]}, ID: ${device["id"]}, Dahili: ${device["isInternal"]}, Bluetooth Adresi: ${device["bluetoothAddress"]}');
        }
      });
    } catch (e) {
      debugPrint('Cihazları yükleme hatası: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// Cihaz verilerini temizler
  void _clearDeviceData() {
    debugPrint('Cihaz verileri temizleniyor...');
    _devices.clear();
    _deviceIds.clear();
  }
  


  /// Sunmi cihazlarını arka planda kontrol et
  Future<void> _checkSunmiDevicesInBackground() async {
    try {
      // İşlemi başlat
      debugPrint('Sunmi dahili cihazları kontrol ediliyor...');
      
      // Var olan dahili cihazları temizle (yeniden tespit için)
      _devices.removeWhere((device) => device['isInternal'] == true);
      _deviceIds.removeWhere((id) => 
        id.toString().startsWith('SUNMI_PRINTER_') || 
        id.toString().startsWith('SUNMI_SCANNER_') ||
        id.toString().startsWith('SUNMI_NFC_') ||
        id.toString().startsWith('SUNMI_DRAWER_')
      );
      
      // Önce gerçek donanımları kontrol et
      final actualDevices = await PrinterHelper.checkActualDevices();
      debugPrint('Gerçek donanım durumu: $actualDevices');
      
      // Sunmi dahili cihazlarını tespit et - sadece gerçekten var olanları
      if (actualDevices['printer']!) {
        await _checkSunmiPrinter();
      } else {
        debugPrint('Dahili yazıcı bulunamadı');
      }
      
      if (actualDevices['scanner']!) {
        await _checkSunmiScanner();
      } else {
        debugPrint('Dahili barkod okuyucu bulunamadı');
      }
      
      if (actualDevices['nfc']!) {
        await _checkSunmiNfc();
      } else {
        debugPrint('Dahili NFC bulunamadı');
      }
      
      if (actualDevices['drawer']!) {
        await _checkCashDrawer();
      } else {
        debugPrint('Dahili para çekmecesi bulunamadı');
      }
      
      // İşlem sonrası UI'ı güncelle
      if (mounted) {
        setState(() {
          debugPrint('Cihaz yükleme tamamlandı, toplam cihaz sayısı: ${_devices.length}');
          debugPrint('Dahili cihaz sayısı: ${_devices.where((d) => d['isInternal'] == true).length}');
          
          // İşlem sonrası tüm cihazları logla
          for (var device in _devices) {
            debugPrint('Eklenen cihaz: ${device["name"]}, ID: ${device["id"]}, Type: ${device["type"]}');
          }
        });
      }
    } catch (e) {
      debugPrint('Sunmi cihazları kontrolünde hata: $e');
    }
  }


  /// Dahili yazıcı kontrol et ve cihazlara ekle
  Future<void> _checkSunmiPrinter() async {
    try {
      debugPrint('Yazıcı kontrolü başlatılıyor...');
      final hasPrinter = await PrinterHelper().hasPrinter();
      debugPrint('Yazıcı var mı: $hasPrinter');
      
      if (hasPrinter) {
        final printerVersion = await PrinterHelper().getPrinterVersion();
        final printerSerialNo = await PrinterHelper().getPrinterSerialNo();
        debugPrint('Yazıcı sürümü: $printerVersion, Seri No: $printerSerialNo');
        
        // Sabit bir ID kullan
        final printerId = 'SUNMI_PRINTER_INTERNAL';
        
        // Yazıcı ID'si zaten varsa atla
        if (_deviceIds.contains(printerId)) {
          debugPrint('Bu yazıcı zaten eklenmiş, atlıyorum: $printerId');
          return;
        }
        
        _deviceIds.add(printerId);
        final deviceData = {
          'id': printerId,
          'name': 'Sunmi Dahili Yazıcı',
          'type': 'printer',
          'status': 'connected',
          'connection': 'internal',
          'model': 'Sunmi Dahili Yazıcı',
          'version': printerVersion,
          'serialNo': printerSerialNo,
          'protocol': 'esc_pos',
          'encoding': 'UTF-8',
          'paperWidth': 58,
          'isInternal': true,
        };
        
        _devices.add(deviceData);
        
        // Veritabanına kaydet (arka planda)
        DatabaseService.instance.saveDevice(deviceData).then((_) {
          debugPrint('Yazıcı veritabanına kaydedildi: $printerId');
        }).catchError((error) {
          debugPrint('Yazıcı veritabanına kaydedilirken hata: $error');
        });
        
        // Değişikliği log ile göster
        debugPrint('Yazıcı eklendi: $printerId');
        
        // UI güncellemesi için setState çağrısı
        if (mounted) {
          setState(() {
            debugPrint('Yazıcı ekleme: setState çağrıldı, cihaz sayısı: ${_devices.length}');
          });
        }
      } else {
        debugPrint('Sunmi yazıcı bulunamadı');
      }
      
      debugPrint('Yazıcı kontrolü tamamlandı');
    } catch (e) {
      debugPrint('Sunmi yazıcı kontrolü sırasında hata: $e');
    }
  }

  /// Dahili barkod okuyucu kontrol et ve cihazlara ekle
  Future<void> _checkSunmiScanner() async {
    try {
      debugPrint('Barkod okuyucu kontrolü başlatılıyor...');
      final hasScanner = await PrinterHelper().hasScanner();
      debugPrint('Barkod okuyucu var mı: $hasScanner');
      
      if (hasScanner) {
        final scannerInfo = await PrinterHelper().getScannerInfo();
        debugPrint('Barkod okuyucu bilgileri: $scannerInfo');
        
        // Sabit bir ID kullan
        final scannerId = 'SUNMI_SCANNER_INTERNAL';
        
        // Barkod okuyucu ID'si zaten varsa atla
        if (_deviceIds.contains(scannerId)) {
          debugPrint('Bu barkod okuyucu zaten eklenmiş, atlıyorum: $scannerId');
          return;
        }
        
        _deviceIds.add(scannerId);
        final deviceData = {
          'id': scannerId,
          'name': 'Sunmi Dahili Barkod Okuyucu',
          'type': 'scanner',
          'status': 'connected',
          'connection': 'internal',
          'model': scannerInfo['model'] ?? 'Dahili Barkod Okuyucu',
          'version': scannerInfo['version'] ?? 'Bilinmiyor',
          'isInternal': true,
        };
        
        _devices.add(deviceData);
        
        // Veritabanına kaydet (arka planda)
        DatabaseService.instance.saveDevice(deviceData).then((_) {
          debugPrint('Barkod okuyucu veritabanına kaydedildi: $scannerId');
        }).catchError((error) {
          debugPrint('Barkod okuyucu veritabanına kaydedilirken hata: $error');
        });
        
        debugPrint('Barkod okuyucu eklendi: $scannerId');
        
        // UI güncellemesi için setState çağrısı
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Barkod okuyucu kontrolü sırasında hata: $e');
    }
  }

  /// Dahili NFC kontrolü ve cihazlara ekleme
  Future<void> _checkSunmiNfc() async {
    try {
      debugPrint('NFC kontrolü başlatılıyor...');
      final hasNfc = await PrinterHelper().hasNfc();
      debugPrint('NFC var mı: $hasNfc');
      
      if (hasNfc) {
        final nfcInfo = await PrinterHelper().getNfcInfo();
        debugPrint('NFC bilgileri: $nfcInfo');
        
        // Sabit bir ID kullan
        final nfcId = 'SUNMI_NFC_INTERNAL';
        
        // NFC ID'si zaten varsa atla
        if (_deviceIds.contains(nfcId)) {
          debugPrint('Bu NFC zaten eklenmiş, atlıyorum: $nfcId');
          return;
        }
        
        _deviceIds.add(nfcId);
        final deviceData = {
          'id': nfcId,
          'name': 'Sunmi NFC Okuyucu',
          'type': 'nfc',
          'status': 'connected',
          'connection': 'internal',
          'model': nfcInfo['model'] ?? 'Dahili NFC',
          'version': nfcInfo['version'] ?? 'Bilinmiyor',
          'isInternal': true,
        };
        
        _devices.add(deviceData);
        
        // Veritabanına kaydet
        await DatabaseService.instance.saveDevice(deviceData);
        
        debugPrint('NFC eklendi: $nfcId');
      }
    } catch (e) {
      debugPrint('NFC kontrolü sırasında hata: $e');
    }
  }

  /// Para çekmecesi kontrolü ve cihazlara ekleme
  Future<void> _checkCashDrawer() async {
    try {
      debugPrint('Para çekmecesi kontrolü başlatılıyor...');
      final hasDrawer = await PrinterHelper().hasDrawer();
      debugPrint('Para çekmecesi var mı: $hasDrawer');
      
      if (hasDrawer) {
        final drawerInfo = await PrinterHelper().getDrawerInfo();
        debugPrint('Para çekmecesi bilgileri: $drawerInfo');
        
        // Sabit bir ID kullan
        final drawerId = 'SUNMI_DRAWER_INTERNAL';
        
        // Çekmece ID'si zaten varsa atla
        if (_deviceIds.contains(drawerId)) {
          debugPrint('Bu para çekmecesi zaten eklenmiş, atlıyorum: $drawerId');
          return;
        }
        
        _deviceIds.add(drawerId);
        final deviceData = {
          'id': drawerId,
          'name': 'Para Çekmecesi',
          'type': 'drawer',
          'status': 'connected',
          'connection': 'internal',
          'model': drawerInfo['model'] ?? 'Dahili Para Çekmecesi',
          'version': drawerInfo['version'] ?? 'Bilinmiyor',
          'isInternal': true,
        };
        
        _devices.add(deviceData);
        
        // Veritabanına kaydet
        await DatabaseService.instance.saveDevice(deviceData);
        
        debugPrint('Para çekmecesi eklendi: $drawerId');
      }
    } catch (e) {
      debugPrint('Para çekmecesi kontrolü sırasında hata: $e');
    }
  }


  
  /// Cihaz ayarlarını aç
  Future<void> _openDeviceSettings(Map<String, dynamic> device) async {
    try {
      debugPrint('Cihaz ayarları açılıyor: ${device['name']}');
      
      // Bluetooth cihazı için BluetoothDevice nesnesi var mı kontrol et
      if (device['connection'] == 'bluetooth' && device['bluetoothDevice'] == null && 
          device['bluetoothAddress'] != null && device['bluetoothAddress'].toString().isNotEmpty) {
        
        debugPrint('BluetoothDevice nesnesi oluşturuluyor: ${device['name']}, Adres: ${device['bluetoothAddress']}');
        try {
          device['bluetoothDevice'] = BluetoothDevice(
            device['name'] ?? 'Bilinmeyen Cihaz',
            device['bluetoothAddress'],
          );
        } catch (e) {
          debugPrint('BluetoothDevice oluşturma hatası: $e');
        }
      }
      
      // Cihaz ayarları sayfasını aç ve sonucu bekle
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceSettings(device: device),
        ),
      );
      
      // Eğer ayarlar kaydedildiyse, cihazları yeniden yükle
      if (result == true) {
        debugPrint('Cihaz ayarları kaydedildi, cihazlar yeniden yükleniyor...');
        await _loadDevices();
      }
    } catch (e) {
      debugPrint('Cihaz ayarları açılırken hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cihaz ayarları açılırken hata: ${e.toString().split('\n').first}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Yeni cihaz ekle
  Future<void> _addNewDevice() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AddDevicePage()),
      );
      
      if (result != null && result is Map<String, dynamic>) {
        setState(() {
          _isLoading = true;
        });
        
        // Önce veritabanına kaydet
        await _saveExternalPrinter(result);
        
        // Cihazı listeye ekle
        if (!_deviceIds.contains(result['id'])) {
          _deviceIds.add(result['id']);
          _devices.add(result);
        }
        
        setState(() {
          _isLoading = false;
        });
        
        // Başarı mesajı göster
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result['name']} başarıyla eklendi'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Cihaz eklenirken hata: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// Sunmi Test Panel sayfasını açar
  
  @override
  Widget build(BuildContext context) {
    // Dahili ve harici cihazları ayır
    final internalDevices = _devices.where((d) => d['isInternal'] == true || d['isInternal'] == 1).toList();
    final externalDevices = _devices.where((d) => d['isInternal'] == false || d['isInternal'] == 0).toList();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aygıtlar'),
        actions: [
          // Sadece yenileme butonu kalsın
          IconButton(
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDevices,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bluetooth tarama durumu
                      if (_isScanning)
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.blue.shade50,
                          child: Row(
                            children: [
                              Container(
                                width: 16, 
                                height: 16,
                                margin: const EdgeInsets.only(right: 8),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const Text("Bluetooth cihazları taranıyor..."),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  BluetoothPrintPlus.stopScan();
                                },
                                child: const Text("Durdur"),
                              ),
                            ],
                          ),
                        ),
                  
                      // Cihaz bağlantı durumu
                      if (_connectionStatus.isNotEmpty && _isConnecting)
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.green.shade50,
                          child: Row(
                            children: [
                              Icon(
                                _connectionStatus == 'Bağlandı'
                                    ? Icons.check_circle
                                    : _connectionStatus == 'Bağlanıyor...'
                                        ? Icons.hourglass_empty
                                        : Icons.error,
                                size: 16,
                                color: _connectionStatus == 'Bağlandı' 
                                    ? Colors.green 
                                    : _connectionStatus == 'Bağlanıyor...'
                                        ? Colors.amber
                                        : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Text(_connectionStatus),
                            ],
                          ),
                        ),
                      
                      // DAHİLİ CİHAZLAR BAŞLIĞI
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'DAHİLİ AYGITLAR',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Row(
                              children: [
                                if (internalDevices.isNotEmpty)
                                  TextButton.icon(
                                    icon: const Icon(Icons.developer_board, size: 18),
                                    label: const Text('Test Et'),
                                    onPressed: _openSunmiTestPanel,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                if (_isLoading)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // DAHİLİ CİHAZLAR LİSTESİ
                      if (internalDevices.isEmpty && !_isLoading)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text(
                                  'Dahili aygıt bulunamadı',
                                  style: TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: internalDevices.length,
                          itemBuilder: (context, index) {
                            final device = internalDevices[index];
                            return ListTile(
                              leading: Icon(
                                _getDeviceIcon(device),
                                color: _getDeviceStatusColor(device),
                              ),
                              title: Text(device['name'] ?? 'İsimsiz Cihaz'),
                              subtitle: Text(_getDeviceDescription(device)),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => _onInternalDeviceTap(device),
                            );
                          },
                        ),
                      
                      // HARİCİ CİHAZLAR BAŞLIĞI
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'HARİCİ AYGITLAR',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _addNewDevice,
                              tooltip: 'Harici Aygıt Ekle',
                            ),
                          ],
                        ),
                      ),
                      
                      // HARİCİ CİHAZLAR LİSTESİ
                      if (externalDevices.isEmpty && !_isLoading)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text(
                                  'Harici aygıt eklenmemiş',
                                  style: TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: externalDevices.length,
                          itemBuilder: (context, index) {
                            final device = externalDevices[index];
                            return ListTile(
                              leading: Icon(
                                _getDeviceIcon(device),
                                color: _getDeviceStatusColor(device),
                              ),
                              title: Text(device['name'] ?? 'İsimsiz Cihaz'),
                              subtitle: Text(_getDeviceDescription(device)),
                              trailing: _isConnecting && device['status'] == 'connecting'
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => _onExternalDeviceTap(device),
                            );
                          },
                        ),
                      
                      // Alt boşluk ekleyelim FAB'ın üzerini kapatmaması için
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewDevice,
        tooltip: 'Harici Aygıt Ekle',
        heroTag: 'addDevice',
        child: const Icon(Icons.add),
      ),
    );
  }
  
  /// Cihaz türüne göre icon döndürür
  IconData _getDeviceIcon(Map<String, dynamic> device) {
    final type = device['type'] ?? 'unknown';
    
    switch (type) {
      case 'printer':
        return Icons.print;
      case 'scanner':
        return Icons.qr_code_scanner;
      case 'display':
        return Icons.monitor;
      case 'cash_drawer':
        return Icons.point_of_sale;
      default:
        return Icons.device_unknown;
    }
  }
  
  /// Cihaz durumuna göre renk döndürür
  Color _getDeviceStatusColor(Map<String, dynamic> device) {
    final status = device['status'] ?? 'unknown';
    
    switch (status) {
      case 'connected':
        return Colors.green;
      case 'connecting':
        return Colors.orange;
      case 'disconnected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  /// Cihaz açıklaması döndürür
  String _getDeviceDescription(Map<String, dynamic> device) {
    final StringBuffer description = StringBuffer();
    
    // Cihaz türü
    if (device['type'] != null) {
      switch (device['type']) {
        case 'printer':
          description.write('Yazıcı');
          break;
        case 'scanner':
          description.write('Barkod Okuyucu');
          break;
        case 'display':
          description.write('Müşteri Ekranı');
          break;
        case 'cash_drawer':
          description.write('Para Çekmecesi');
          break;
        default:
          description.write('Bilinmeyen Cihaz');
          break;
      }
    }
    
    // Bağlantı türü
    if (device['connection'] != null) {
      description.write(' (');
      switch (device['connection']) {
        case 'bluetooth':
          description.write('Bluetooth');
          break;
        case 'usb':
          description.write('USB');
          break;
        case 'network':
          description.write('Ağ');
          break;
        case 'internal':
          description.write('Dahili');
          break;
        default:
          description.write(device['connection']);
          break;
      }
      description.write(')');
    }
    
    // Durum
    if (device['status'] != null) {
      description.write(' - ');
      switch (device['status']) {
        case 'connected':
          description.write('Bağlı');
          break;
        case 'connecting':
          description.write('Bağlanıyor...');
          break;
        case 'disconnected':
          description.write('Bağlı Değil');
          break;
        default:
          description.write(device['status']);
          break;
      }
    }
    
    return description.toString();
  }

  

  /// Dahili cihaza tıklandığında
  Future<void> _onInternalDeviceTap(Map<String, dynamic> device) async {
    debugPrint('Dahili cihaza tıklandı: ${device['name']}');
    
    if (device['type'] == 'printer') {
      // Yazıcı ayarlarını aç
      await _openDeviceSettings(device);
    }
  }

  /// Harici cihaza tıklandığında
  Future<void> _onExternalDeviceTap(Map<String, dynamic> device) async {
    try {
      debugPrint('Harici cihaza tıklandı: ${device['name']}');
      
      // Yazıcı ise seçenekler göster
      if (device['type'] == 'printer') {
        await _showPrinterOptions(device);
      } else {
        // Diğer cihazlar için doğrudan ayarlara git
        await _openDeviceSettings(device);
      }
      
    } catch (e) {
      debugPrint('_onExternalDeviceTap hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem hatası: ${e.toString().split('\n').first}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Yazıcı seçeneklerini göster
  Future<void> _showPrinterOptions(Map<String, dynamic> device) async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                device['name'] ?? 'Yazıcı',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.print, color: Colors.blue),
                title: const Text('Test Yazdır'),
                subtitle: const Text('Test fişi yazdır'),
                onTap: () {
                  Navigator.pop(context);
                  _testPrintReceipt(device);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bluetooth, color: Colors.green),
                title: const Text('Bağlan'),
                subtitle: const Text('Yazıcıya bağlan'),
                onTap: () {
                  Navigator.pop(context);
                  _connectToPrinter(device);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.grey),
                title: const Text('Ayarlar'),
                subtitle: const Text('Yazıcı ayarlarını düzenle'),
                onTap: () {
                  Navigator.pop(context);
                  _openDeviceSettings(device);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// Test fişi yazdır
  Future<void> _testPrintReceipt(Map<String, dynamic> device) async {
    try {
      debugPrint('Test fişi yazdırılıyor: ${device['name']}');
      
      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Test fişi yazdırılıyor...'),
            ],
          ),
        ),
      );

      final printerHelper = PrinterHelper();
      
      // Test verilerini oluştur
      final testItems = [
        {
          'name': 'Test Ürün 1',
          'quantity': 2.0,
          'price': 15.50,
          'subtotal': 31.0,
        },
        {
          'name': 'Test Ürün 2',
          'quantity': 1.0,
          'price': 25.75,
          'subtotal': 25.75,
        },
      ];

      final success = await printerHelper.printReceipt(
        printerId: device['id'],
        title: 'TEST FİŞİ',
        subtitle: 'Test Yazdırma #${DateTime.now().millisecondsSinceEpoch}',
        items: testItems,
        total: 56.75,
        paymentMethod: 'Test',
      );

      // Loading'i kapat
      Navigator.pop(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test fişi başarıyla yazdırıldı'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test fişi yazdırılamadı'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Loading'i kapat
      Navigator.pop(context);
      
      debugPrint('Test yazdırma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test yazdırma hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Yazıcıya bağlan
  Future<void> _connectToPrinter(Map<String, dynamic> device) async {
    try {
      debugPrint('Yazıcıya bağlanılıyor: ${device['name']}');
      
      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Yazıcıya bağlanılıyor...'),
            ],
          ),
        ),
      );

      // Bağlantı testi yap
      bool connected = false;
      
      if (device['isInternal'] == 1) {
        // Dahili yazıcı için her zaman başarılı
        connected = true;
      } else {
        // Harici yazıcı için gerçek Bluetooth bağlantısı test et
        final bluetoothAddress = device['bluetoothAddress'] as String?;
        if (bluetoothAddress != null && bluetoothAddress.isNotEmpty) {
          try {
            // BluetoothPrinterHelperSimple ile gerçek bağlantı test et
            final bluetoothHelper = BluetoothPrinterHelperSimple();
            
            debugPrint('🔗 Gerçek Bluetooth bağlantısı test ediliyor: $bluetoothAddress');
            
            // Bluetooth durumunu kontrol et
            final isBluetoothEnabled = await bluetoothHelper.isBluetoothEnabled();
            if (!isBluetoothEnabled) {
              debugPrint('❌ Bluetooth kapalı');
              connected = false;
            } else {
              // Bağlantı dene - EventSink sorununu önlemek için try-catch
              try {
                connected = await bluetoothHelper.connectByAddress(bluetoothAddress).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    debugPrint('⏰ Bağlantı timeout');
                    return false;
                  },
                );
                
                if (connected) {
                  debugPrint('✅ Bluetooth bağlantısı başarılı');
                  // Bağlantıyı güvenli şekilde kapat
                  try {
                    await bluetoothHelper.disconnect().timeout(
                      const Duration(seconds: 3),
                      onTimeout: () {
                        debugPrint('Disconnect timeout');
                      },
                    );
                  } catch (disconnectError) {
                    debugPrint('Disconnect hatası: $disconnectError');
                  }
                } else {
                  debugPrint('❌ Bluetooth bağlantısı başarısız');
                }
              } catch (connectError) {
                debugPrint('❌ Connect hatası: $connectError');
                // EventSink hatası ise bağlantıyı başarısız say ama uygulamayı çökertme
                if (connectError.toString().contains('EventSink') || 
                    connectError.toString().contains('NullPointerException')) {
                  debugPrint('⚠️ EventSink hatası tespit edildi, bağlantı başarısız sayılıyor');
                  connected = false;
                } else {
                  connected = false;
                }
              }
            }
          } catch (e) {
            debugPrint('❌ Bluetooth bağlantı test hatası: $e');
            connected = false;
          }
        }
      }

      // Loading'i kapat
      Navigator.pop(context);

      if (connected) {
        // Veritabanında durumu güncelle
        await DatabaseService.instance.updateDevice(device['id'], {
          'status': 'connected',
          'updatedAt': DateTime.now().toIso8601String(),
        });
        
        // Listeyi yenile
        await _loadDevices();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${device['name']} yazıcısına başarıyla bağlanıldı'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${device['name']} yazıcısına bağlanılamadı'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Loading'i kapat
      Navigator.pop(context);
      
      debugPrint('Bağlantı hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bağlantı hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Bluetooth bağlantısını kontrol et
  Future<bool> _checkBluetoothConnection(Map<String, dynamic> device) async {
    try {
      if (device['isInternal'] == true) {
        // Dahili cihaz için her zaman bağlı kabul et
        return true;
      }
      
      if (device['connection'] != 'bluetooth') {
        // Bluetooth dışındaki bağlantı türleri için şimdilik true dön
        return true;
      }
      
      // BluetoothDevice nesnesi var mı kontrol et
      if (device['bluetoothDevice'] == null) {
        // BluetoothDevice nesnesi yoksa oluşturmayı dene
        if (device['bluetoothAddress'] != null && device['bluetoothAddress'].toString().isNotEmpty) {
          try {
            device['bluetoothDevice'] = BluetoothDevice(
              device['name'] ?? 'Bilinmeyen Cihaz',
              device['bluetoothAddress'],
            );
          } catch (e) {
            debugPrint('BluetoothDevice oluşturma hatası: $e');
            return false;
          }
        } else {
          // Bluetooth adresi yoksa bağlantı kurulamaz
          return false;
        }
      }
      
      // Bağlantı durumunu güvenli bir şekilde kontrol et
      bool isConnected = false;
      try {
        isConnected = BluetoothPrintPlus.isConnected;
      } catch (e) {
        debugPrint('Bağlantı durumu kontrolünde hata: $e');
        isConnected = false;
      }
      
      return isConnected;
    } catch (e) {
      debugPrint('Bluetooth bağlantı kontrolü sırasında hata: $e');
      return false;
    }
  }
  
  /// Cihazların bağlantı durumunu kontrol et
  Future<void> _checkConnectionStatus() async {
    try {
      if (_devices.isEmpty) return;
      for (final device in _devices) {
        if (device['isInternal'] == true) {
          device['status'] = 'connected';
        } else if (device['connection'] == 'bluetooth') {
          try {
            bool isConnected = await _checkBluetoothConnection(device);
            device['status'] = isConnected ? 'connected' : 'disconnected';
          } catch (e) {
            debugPrint('Bluetooth bağlantı durumu kontrolünde hata: $e');
            device['status'] = 'disconnected';
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Bağlantı durumu kontrolü hatası: $e');
    }
  }

  // Sunmi test panelini aç
  void _openSunmiTestPanel() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sunmi Test Paneli'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Basit Test Sayfası Yazdır'),
              onTap: () async {
                Navigator.pop(context);
                
                setState(() {
                  _isLoading = true;
                });
                
                try {
                  // Yazıcıyı bul
                  final printerDevice = _devices.firstWhere(
                    (d) => d['type'] == 'printer' && d['isInternal'] == true,
                    orElse: () => <String, dynamic>{},
                  );
                  
                  if (printerDevice.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Dahili yazıcı bulunamadı'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  
                  final printerId = printerDevice['id'];
                  
                  final result = await PrinterHelper().printTest(
                    printerId: printerId,
                    paperWidth: printerDevice['paperWidth'] ?? 58,
                  );
                  
                  if (result) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test sayfası yazdırıldı')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Test sayfası yazdırılamadı'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } finally {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt),
              title: const Text('Görsel İçeren Fiş Yazdır'),
              onTap: () async {
                Navigator.pop(context);
                
                setState(() {
                  _isLoading = true;
                });
                
                try {
                  // Yazıcıyı bul
                  final printerDevice = _devices.firstWhere(
                    (d) => d['type'] == 'printer' && d['isInternal'] == true,
                    orElse: () => <String, dynamic>{},
                  );
                  
                  if (printerDevice.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Dahili yazıcı bulunamadı'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  
                  final printerId = printerDevice['id'];
                  final paperWidth = printerDevice['paperWidth'] ?? 58;
                  
                  debugPrint('Yazıcı ID: $printerId, Kağıt genişliği: $paperWidth');
                  
                  final result = await PrinterHelper().printReceiptWithImage(
                    printerId: printerId,
                    paperWidth: paperWidth,
                    imagePath: 'assets/fis.png',
                    title: 'SHAMAN TEST FİŞİ',
                    subtitle: 'Sunmi Yazıcı Testi',
                    footer: 'Teşekkür ederiz!\nwww.shaman.com.tr',
                  );
                  
                  if (result) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test fişi yazdırıldı')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Test fişi yazdırılamadı'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } finally {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

}

class SunmiDeviceTestPanel {
  const SunmiDeviceTestPanel();
}


