import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import '../../shared/constants/app_theme.dart';
import '../../shared/constants/theme_provider.dart';
import '../../shared/utils/debug_config.dart';
import '../../data/datasources/bluetooth_service.dart';
import 'device_settings_page.dart';

/// Cihazlar sayfası - Yazıcılar ve diğer cihazları yönetmek için ekran
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final List<Map<String, dynamic>> _devices = [];
  final BluetoothService _bluetoothService = BluetoothService.instance;
  bool _isLoading = false;
  bool _isScanning = false;
  bool _bluetoothEnabled = false;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
    _loadDevices();
  }

  @override
  void dispose() {
    // Bluetooth servisini dispose etme - singleton olduğu için
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    try {
      final initialized = await _bluetoothService.initialize();
      if (initialized) {
        final enabled = await _bluetoothService.isBluetoothEnabled();
        if (mounted) {
          setState(() {
            _bluetoothEnabled = enabled;
          });
        }
      }
    } catch (e) {
      DebugConfig.logError('Bluetooth başlatma hatası', e);
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      // TODO: Veritabanından kaydedilmiş cihazları yükle
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() {
          // Örnek cihazlar
          _devices.clear();

          // Dahili yazıcı ekle
          _devices.add({
            'id': 'internal',
            'name': 'Dahili Yazıcı',
            'type': 'printer',
            'status': 'available',
            'connection': 'internal',
            'model': 'Sunmi Printer',
          });

          // Bağlı Bluetooth cihazı varsa ekle
          if (_bluetoothService.isConnected) {
            final connectedDevice = _bluetoothService.connectedDevice;
            if (connectedDevice != null) {
              _devices.add({
                'id': connectedDevice.address,
                'name': connectedDevice.name,
                'type': 'printer',
                'status': 'connected',
                'connection': 'bluetooth',
                'model': 'Bluetooth Printer',
                'bluetoothDevice': connectedDevice,
              });
            }
          }
        });
      }
    } catch (e) {
      DebugConfig.logError('Cihazlar yüklenirken hata', e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _scanDevices() async {
    if (!_bluetoothEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth kapalı. Lütfen Bluetooth\'u açın.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isScanning = true);
    try {
      DebugConfig.logDebug('Bluetooth cihazları aranıyor...');

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
      DebugConfig.logError('Cihaz tarama hatası', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tarama hatası: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isScanning = false);
    }
  }

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
                    _connectToBluetoothDevice(device);
                  },
                  child: const Text('Bağlan'),
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

  Future<void> _connectToBluetoothDevice(BluetoothDevice device) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${device.name} cihazına bağlanılıyor...'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      final success = await _bluetoothService.connect(device);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${device.name} bağlantısı başarılı'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _loadDevices(); // Cihaz listesini güncelle
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
      DebugConfig.logError('Bluetooth bağlantı hatası', e);
    }
  }

  void _showDeviceDetails(Map<String, dynamic> device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(device['name'] ?? 'Cihaz Detayı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Tip', _getDeviceTypeText(device['type'])),
            _buildDetailRow('Durum', _getStatusText(device['status'])),
            _buildDetailRow(
                'Bağlantı', _getConnectionText(device['connection'])),
            if (device['model'] != null)
              _buildDetailRow('Model', device['model']),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          if (device['status'] == 'disconnected')
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _connectDevice(device);
              },
              child: const Text('Bağlan'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openDeviceSettings(device);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.greenColor,
            ),
            child: const Text('Ayarlar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeviceSettings(Map<String, dynamic> device) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSettingsPage(device: device),
      ),
    );

    // Ayarlar değiştiyse cihaz listesini güncelle
    if (result == true) {
      await _loadDevices();
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
    );
  }

  String _getDeviceTypeText(String? type) {
    switch (type) {
      case 'printer':
        return 'Yazıcı';
      case 'scanner':
        return 'Tarayıcı';
      default:
        return 'Bilinmiyor';
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'connected':
        return 'Bağlı';
      case 'disconnected':
        return 'Bağlı Değil';
      case 'connecting':
        return 'Bağlanıyor...';
      default:
        return 'Bilinmiyor';
    }
  }

  String _getConnectionText(String? connection) {
    switch (connection) {
      case 'bluetooth':
        return 'Bluetooth';
      case 'usb':
        return 'USB';
      case 'wifi':
        return 'Wi-Fi';
      case 'internal':
        return 'Dahili';
      default:
        return 'Bilinmiyor';
    }
  }

  Future<void> _connectDevice(Map<String, dynamic> device) async {
    try {
      if (device['connection'] == 'bluetooth') {
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

        if (device['bluetoothDevice'] != null) {
          await _connectToBluetoothDevice(
              device['bluetoothDevice'] as BluetoothDevice);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth cihaz bilgisi bulunamadı'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else if (device['connection'] == 'internal') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dahili yazıcı her zaman hazır'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      DebugConfig.logError('Cihaz bağlantı hatası', e);
    }
  }

  Future<void> _disconnectDevice(Map<String, dynamic> device) async {
    try {
      if (device['connection'] == 'bluetooth') {
        final success = await _bluetoothService.disconnect();
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bağlantı kesildi'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            await _loadDevices();
          }
        }
      }
    } catch (e) {
      DebugConfig.logError('Bağlantı kesme hatası', e);
    }
  }

  Future<void> _deleteDevice(Map<String, dynamic> device) async {
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _devices.remove(device);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cihaz silindi'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode
        ? AppTheme.darkBackgroundColor
        : AppTheme.lightBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Cihazlar'),
        centerTitle: false,
        elevation: 0,
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.devices_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz cihaz eklenmemiş',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
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
                    final isConnected = device['status'] == 'connected';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isConnected
                                ? AppTheme.greenColor
                                : Colors.grey[400],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getDeviceIcon(device['type']),
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          device['name'] ?? 'Bilinmeyen Cihaz',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${_getDeviceTypeText(device['type'])} • ${_getStatusText(device['status'])}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'details':
                                _showDeviceDetails(device);
                                break;
                              case 'settings':
                                _openDeviceSettings(device);
                                break;
                              case 'connect':
                                _connectDevice(device);
                                break;
                              case 'disconnect':
                                _disconnectDevice(device);
                                break;
                              case 'delete':
                                _deleteDevice(device);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'details',
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 20),
                                  SizedBox(width: 8),
                                  Text('Detaylar'),
                                ],
                              ),
                            ),
                            if (device['type'] == 'printer')
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
                            if (!isConnected &&
                                device['connection'] == 'bluetooth')
                              const PopupMenuItem(
                                value: 'connect',
                                child: Row(
                                  children: [
                                    Icon(Icons.link, size: 20),
                                    SizedBox(width: 8),
                                    Text('Bağlan'),
                                  ],
                                ),
                              ),
                            if (isConnected &&
                                device['connection'] == 'bluetooth')
                              const PopupMenuItem(
                                value: 'disconnect',
                                child: Row(
                                  children: [
                                    Icon(Icons.link_off, size: 20),
                                    SizedBox(width: 8),
                                    Text('Bağlantıyı Kes'),
                                  ],
                                ),
                              ),
                            if (device['connection'] != 'internal')
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
                        onTap: () => _showDeviceDetails(device),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Cihaz ekleme ekranı
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cihaz ekleme özelliği yakında eklenecek'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Cihaz Ekle'),
        backgroundColor: AppTheme.greenColor,
      ),
    );
  }

  IconData _getDeviceIcon(String? type) {
    switch (type) {
      case 'printer':
        return Icons.print;
      case 'scanner':
        return Icons.scanner;
      default:
        return Icons.devices;
    }
  }
}
