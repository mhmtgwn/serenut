import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import '../../data/datasources/database_service.dart';
import '../../data/datasources/bluetooth_service.dart';
import '../../data/datasources/sunmi_printer_service.dart';
import '../../shared/utils/debug_config.dart';
import 'device_settings_page.dart';

/// Cihazlar sayfası - Backup'taki çalışan yapı
class DevicesPageNew extends StatefulWidget {
  const DevicesPageNew({super.key});

  @override
  State<DevicesPageNew> createState() => _DevicesPageNewState();
}

class _DevicesPageNewState extends State<DevicesPageNew> {
  final List<Map<String, dynamic>> _devices = [];
  final List<String> _deviceIds = [];
  final BluetoothService _bluetoothService = BluetoothService.instance;

  bool _isLoading = false;
  bool _isScanning = false;
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    _loadDevices();

    // İlk yükleme sonrası bağlantı kontrolü
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _checkExistingConnections();
      }
    });

    // Periyodik bağlantı kontrolü
    _connectionCheckTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        _updateConnectionStatus();
      }
    });
  }

  /// Mevcut bağlantıları kontrol et
  Future<void> _checkExistingConnections() async {
    if (!mounted) return;

    try {
      DebugConfig.logDebug('Mevcut bağlantılar kontrol ediliyor...');

      // Bluetooth bağlantısı var mı kontrol et
      final isConnected = _bluetoothService.isConnected;
      final connectedDevice = _bluetoothService.connectedDevice;

      if (isConnected && connectedDevice != null) {
        DebugConfig.logSuccess(
            'Mevcut Bluetooth bağlantısı bulundu: ${connectedDevice.name}');

        // UI'yi güncelle
        if (mounted) {
          setState(() {
            for (var device in _devices) {
              if (device['connection'] == 'bluetooth' &&
                  device['bluetoothAddress'] == connectedDevice.address) {
                device['status'] = 'connected';
                DebugConfig.logSuccess(
                    'Cihaz durumu güncellendi: ${device['name']}');
              }
            }
          });
        }
      } else {
        DebugConfig.logDebug('Mevcut Bluetooth bağlantısı yok');
      }
    } catch (e) {
      DebugConfig.logError('Bağlantı kontrolü hatası', e);
    }
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    super.dispose();
  }

  /// Bağlantısız Bluetooth cihazlara otomatik bağlan
  /// DEVRE DIŞI - bluetooth_print_plus EventSink hatası nedeniyle
  // ignore: unused_element
  Future<void> _autoConnectDevices() async {
    if (!mounted) return;

    try {
      // Zaten bir bağlantı varsa yeni bağlantı deneme
      if (_bluetoothService.isConnected) {
        return; // Sessizce çık, log spam'i önle
      }

      // Bağlantısız cihaz var mı kontrol et
      bool hasDisconnectedDevice = false;
      for (var device in _devices) {
        if (device['connection'] == 'bluetooth' &&
            device['status'] != 'connected' &&
            device['bluetoothDevice'] != null) {
          hasDisconnectedDevice = true;
          break;
        }
      }

      // Bağlantısız cihaz yoksa deneme
      if (!hasDisconnectedDevice) {
        return;
      }

      for (var device in _devices) {
        if (device['connection'] == 'bluetooth' &&
            device['status'] != 'connected' &&
            device['bluetoothDevice'] != null) {
          try {
            DebugConfig.logDebug(
                'Otomatik bağlanma deneniyor: ${device['name']}');

            final success = await _bluetoothService.connect(
              device['bluetoothDevice'],
            );

            if (success) {
              DebugConfig.logSuccess(
                  'Otomatik bağlantı başarılı: ${device['name']}');
              _updateConnectionStatus();

              // Bir cihaza bağlandıysa diğerlerini deneme
              break;
            } else {
              DebugConfig.logDebug(
                  'Otomatik bağlantı başarısız: ${device['name']}');
            }
          } catch (e) {
            DebugConfig.logError(
                'Otomatik bağlantı hatası: ${device['name']}', e);
            // Hata olsa bile devam et, diğer cihazları dene
          }
        }
      }
    } catch (e) {
      DebugConfig.logError('autoConnectDevices genel hatası', e);
    }
  }

  /// Bağlantı durumunu güncelle
  void _updateConnectionStatus() {
    if (!mounted) return;

    try {
      setState(() {
        for (var device in _devices) {
          if (device['connection'] == 'bluetooth') {
            try {
              // Bluetooth bağlantı kontrolü
              final connectedDevice = _bluetoothService.connectedDevice;
              if (connectedDevice != null &&
                  device['bluetoothAddress'] != null &&
                  connectedDevice.address == device['bluetoothAddress']) {
                device['status'] = 'connected';
              } else {
                device['status'] = 'disconnected';
              }
            } catch (e) {
              DebugConfig.logError('Bağlantı durumu kontrol hatası', e);
              device['status'] = 'disconnected';
            }
          }
        }
      });
    } catch (e) {
      DebugConfig.logError('updateConnectionStatus hatası', e);
    }
  }

  /// Cihazları veritabanından yükle
  Future<void> _loadDevices() async {
    if (_isLoading) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      DebugConfig.logDebug('Cihazlar veritabanından yükleniyor...');

      // Verileri temizle
      _devices.clear();
      _deviceIds.clear();

      // Dahili yazıcı ekle (varsa) - await ekle
      await _addInternalPrinter();

      // Veritabanından harici cihazları yükle
      final dbDevices = await DatabaseService.instance.getAllDevices();
      DebugConfig.logDebug('Veritabanından ${dbDevices.length} cihaz yüklendi');

      for (final device in dbDevices) {
        try {
          final deviceId = device['id'];
          if (deviceId == null) continue;

          final isInternal = device['isInternal'] == 1;

          // Sadece harici cihazları ekle
          if (!isInternal && !_deviceIds.contains(deviceId)) {
            final deviceCopy = Map<String, dynamic>.from(device);

            // isInternal değerini boolean'a dönüştür
            deviceCopy['isInternal'] = false;

            // Bluetooth cihazı ise BluetoothDevice nesnesi oluştur
            if (deviceCopy['connection'] == 'bluetooth' &&
                deviceCopy['bluetoothAddress'] != null) {
              try {
                deviceCopy['bluetoothDevice'] = BluetoothDevice(
                  deviceCopy['name'] ?? 'Bilinmeyen Cihaz',
                  deviceCopy['bluetoothAddress'],
                );
              } catch (e) {
                DebugConfig.logError('BluetoothDevice oluşturma hatası', e);
                continue;
              }
            }

            _deviceIds.add(deviceId);
            _devices.add(deviceCopy);

            DebugConfig.logDebug(
                'Cihaz yüklendi: ${deviceCopy['name']} - ${deviceCopy['protocol']}');
          }
        } catch (e) {
          DebugConfig.logError('Cihaz işleme hatası', e);
          continue;
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          DebugConfig.logSuccess('Toplam ${_devices.length} cihaz yüklendi');
        });
      }
    } catch (e) {
      DebugConfig.logError('Cihazları yükleme hatası', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Dahili yazıcı ekle
  Future<void> _addInternalPrinter() async {
    try {
      // Gerçek donanımları kontrol et
      final actualDevices =
          await SunmiPrinterService.instance.checkActualDevices();
      DebugConfig.logDebug('Gerçek donanım durumu: $actualDevices');

      // Dahili yazıcı varsa ekle
      if (actualDevices['printer'] == true) {
        final hasPrinter = await SunmiPrinterService.instance.hasPrinter();

        if (hasPrinter) {
          final printerVersion =
              await SunmiPrinterService.instance.getPrinterVersion();
          final printerSerialNo =
              await SunmiPrinterService.instance.getPrinterSerialNo();

          DebugConfig.logSuccess(
              'Dahili yazıcı bulundu: $printerVersion, SN: $printerSerialNo');

          final internalPrinter = {
            'id': 'SUNMI_PRINTER_INTERNAL',
            'name': 'Dahili Yazıcı',
            'type': 'printer',
            'status': 'available',
            'connection': 'internal',
            'model': 'Sunmi Printer',
            'version': printerVersion,
            'serialNo': printerSerialNo,
            'protocol': 'esc_pos',
            'encoding': 'UTF-8',
            'paperWidth': 58,
            'isInternal': true,
          };

          _deviceIds.add(internalPrinter['id'] as String);
          _devices.add(internalPrinter);
        } else {
          DebugConfig.logWarning('Dahili yazıcı tespit edilemedi');
        }
      } else {
        DebugConfig.logDebug('Sunmi cihaz değil, dahili yazıcı yok');
      }
    } catch (e) {
      DebugConfig.logDebug('Dahili yazıcı kontrolü hatası (normal): $e');
    }
  }

  /// Bluetooth cihazlarını tara
  Future<void> _scanDevices() async {
    setState(() => _isScanning = true);

    try {
      DebugConfig.logDebug('Bluetooth cihazları taranıyor...');

      final devices = await _bluetoothService.startScan(
        duration: const Duration(seconds: 5),
      );

      if (mounted) {
        if (devices.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hiç Bluetooth cihazı bulunamadı'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          _showBluetoothDevicesDialog(devices);
        }
      }
    } catch (e) {
      DebugConfig.logError('Bluetooth tarama hatası', e);
    } finally {
      setState(() => _isScanning = false);
    }
  }

  /// Bulunan Bluetooth cihazlarını göster
  void _showBluetoothDevicesDialog(List<BluetoothDevice> devices) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bulunan Cihazlar (${devices.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(
                    device.name.isEmpty ? 'Bilinmeyen Cihaz' : device.name),
                subtitle: Text(device.address),
                trailing: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _addBluetoothDevice(device);
                  },
                  child: const Text('Ekle'),
                ),
              );
            },
          ),
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

  /// Bluetooth cihazını veritabanına ekle
  Future<void> _addBluetoothDevice(BluetoothDevice device) async {
    try {
      // DUPLİKASYON KONTROLÜ: Cihaz zaten var mı?
      final existingDevice =
          await DatabaseService.instance.getDeviceById(device.address);
      if (existingDevice != null) {
        DebugConfig.logWarning('Cihaz zaten mevcut: ${device.name}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${device.name} zaten ekli'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final deviceData = {
        'id': device.address,
        'name': device.name.isEmpty ? 'Bluetooth Yazıcı' : device.name,
        'type': 'printer',
        'status': 'disconnected',
        'connection': 'bluetooth',
        'model': 'Bluetooth Printer',
        'protocol': 'esc_pos',
        'encoding': 'UTF-8',
        'paperWidth': 58,
        'isInternal': 0,
        'bluetoothAddress': device.address,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await DatabaseService.instance.saveDevice(deviceData);

      DebugConfig.logSuccess('Cihaz veritabanına kaydedildi: ${device.name}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${device.name} eklendi'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Listeyi yenile
      await _loadDevices();
    } catch (e) {
      DebugConfig.logError('Cihaz ekleme hatası', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ekleme hatası: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Bluetooth cihazına bağlan
  Future<void> _connectToDevice(Map<String, dynamic> device) async {
    try {
      // CRASH ÖNLEME: bluetoothDevice null veya geçersizse yeniden oluştur
      if (device['bluetoothDevice'] == null &&
          device['bluetoothAddress'] != null) {
        DebugConfig.logDebug(
            'BluetoothDevice nesnesi yeniden oluşturuluyor...');
        try {
          device['bluetoothDevice'] = BluetoothDevice(
            device['name'] ?? 'Bilinmeyen Cihaz',
            device['bluetoothAddress'],
          );
        } catch (e) {
          DebugConfig.logError('BluetoothDevice oluşturma hatası', e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Bluetooth cihaz bilgisi oluşturulamadı: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      if (device['bluetoothDevice'] == null) {
        DebugConfig.logError('Bluetooth cihaz bilgisi bulunamadı', null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth cihaz bilgisi bulunamadı'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${device['name']} cihazına bağlanılıyor...'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      final success =
          await _bluetoothService.connect(device['bluetoothDevice']);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${device['name']} bağlantısı başarılı'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          _updateConnectionStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bağlantı başarısız'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      DebugConfig.logError('Bağlantı hatası', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bağlantı hatası: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Bluetooth bağlantısını kes
  Future<void> _disconnectFromDevice(Map<String, dynamic> device) async {
    try {
      final success = await _bluetoothService.disconnect();

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bağlantı kesildi'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _updateConnectionStatus();
        }
      }
    } catch (e) {
      DebugConfig.logError('Bağlantı kesme hatası', e);
    }
  }

  /// Cihaz ayarlarını aç
  Future<void> _openDeviceSettings(Map<String, dynamic> device) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSettingsPage(device: device),
      ),
    );

    // Ayarlar değiştiyse listeyi yenile
    if (result == true) {
      await _loadDevices();
    }
  }

  /// Cihazı sil
  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    if (device['isInternal'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dahili cihazlar silinemez'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cihazı Sil'),
        content: Text(
            '${device['name']} cihazını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await DatabaseService.instance.deleteDevice(device['id']);
        DebugConfig.logSuccess('Cihaz silindi: ${device['name']}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cihaz silindi'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        await _loadDevices();
      } catch (e) {
        DebugConfig.logError('Cihaz silme hatası', e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihazlar'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching),
            onPressed: _isScanning ? null : _scanDevices,
            tooltip: 'Cihaz Tara',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.devices_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('Henüz cihaz eklenmemiş',
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _scanDevices,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Cihaz Tara'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isInternal = device['isInternal'] == true;
                    final isConnected = device['status'] == 'connected';
                    final isBluetooth = device['connection'] == 'bluetooth';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: isInternal
                                  ? Colors.blue
                                  : (isConnected ? Colors.green : Colors.grey),
                              child: Icon(
                                isInternal ? Icons.print : Icons.bluetooth,
                                color: Colors.white,
                              ),
                            ),
                            if (isBluetooth && isConnected)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          device['name'] ?? 'Bilinmeyen Cihaz',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${device['protocol']?.toString().toUpperCase() ?? 'ESC/POS'} • ${device['paperWidth'] ?? 58}mm',
                            ),
                            if (isBluetooth)
                              Text(
                                isConnected ? '🟢 Bağlı' : '⚪ Bağlı Değil',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      isConnected ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'settings':
                                _openDeviceSettings(device);
                                break;
                              case 'connect':
                                _connectToDevice(device);
                                break;
                              case 'disconnect':
                                _disconnectFromDevice(device);
                                break;
                              case 'delete':
                                _deleteDevice(device);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'settings',
                              child: Row(
                                children: [
                                  Icon(Icons.settings, size: 20),
                                  SizedBox(width: 8),
                                  Text('Ayarlar'),
                                ],
                              ),
                            ),
                            if (isBluetooth && !isConnected)
                              const PopupMenuItem(
                                value: 'connect',
                                child: Row(
                                  children: [
                                    Icon(Icons.link,
                                        size: 20, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Bağlan',
                                        style: TextStyle(color: Colors.blue)),
                                  ],
                                ),
                              ),
                            if (isBluetooth && isConnected)
                              const PopupMenuItem(
                                value: 'disconnect',
                                child: Row(
                                  children: [
                                    Icon(Icons.link_off,
                                        size: 20, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Bağlantıyı Kes',
                                        style: TextStyle(color: Colors.orange)),
                                  ],
                                ),
                              ),
                            if (!isInternal)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 20, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Sil',
                                        style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        onTap: () => _openDeviceSettings(device),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanDevices,
        icon: const Icon(Icons.add),
        label: const Text('Cihaz Ekle'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
