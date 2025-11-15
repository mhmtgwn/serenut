import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sunmi_printer_service.dart';

/// Aygıt yönetim servisi - Dahili ve harici donanımları yönetir
class DeviceManagerService {
  static final DeviceManagerService _instance =
      DeviceManagerService._internal();
  factory DeviceManagerService() => _instance;
  DeviceManagerService._internal();

  final SunmiPrinterService _sunmiPrinter = SunmiPrinterService();

  static const String _devicesKey = 'registered_devices';
  static const String _defaultPrinterKey = 'default_printer_id';

  /// Tüm aygıtları al
  Future<List<Map<String, dynamic>>> getAllDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesJson = prefs.getStringList(_devicesKey) ?? [];

      return devicesJson.map((json) {
        final parts = json.split('|');
        return {
          'id': parts[0],
          'name': parts[1],
          'type': parts[2],
          'connection': parts[3],
          'status': parts[4],
          'isDefault': parts.length > 5 ? parts[5] == 'true' : false,
        };
      }).toList();
    } catch (e) {
      debugPrint('Aygıt listesi alma hatası: $e');
      return [];
    }
  }

  /// Varsayılan aygıtları kur (ilk çalıştırmada)
  Future<void> setupDefaultDevices() async {
    try {
      final devices = await getAllDevices();

      if (devices.isEmpty) {
        debugPrint('Varsayılan aygıtlar kuruluyor...');

        // Sunmi dahili yazıcısını kontrol et ve ekle
        final sunmiConnected = await _sunmiPrinter.isConnected();

        if (sunmiConnected) {
          final sunmiInfo = await _sunmiPrinter.getPrinterInfo();

          await _addDevice({
            'id': 'sunmi_internal',
            'name': 'Sunmi Dahili Yazıcı',
            'type': 'printer',
            'connection': 'internal',
            'status': 'connected',
            'model': sunmiInfo['model'] ?? 'Sunmi',
            'version': sunmiInfo['version'] ?? '1.0',
            'serial': sunmiInfo['serial'] ?? 'N/A',
          });

          // Varsayılan yazıcı olarak ata
          await setDefaultPrinter('sunmi_internal');

          debugPrint(
              '✓ Sunmi dahili yazıcı eklendi ve varsayılan olarak atandı');
        } else {
          debugPrint('⚠ Sunmi yazıcı bulunamadı');
        }

        debugPrint('Varsayılan aygıtlar başarıyla kuruldu');
      } else {
        debugPrint('Aygıtlar zaten mevcut (${devices.length} adet)');

        // Sunmi yazıcı durumunu güncelle
        await _updateSunmiStatus();
      }
    } catch (e) {
      debugPrint('Varsayılan aygıt kurulum hatası: $e');
    }
  }

  /// Sunmi yazıcı durumunu güncelle
  Future<void> _updateSunmiStatus() async {
    try {
      final devices = await getAllDevices();
      final sunmiDevice = devices.firstWhere(
        (d) => d['id'] == 'sunmi_internal',
        orElse: () => {},
      );

      if (sunmiDevice.isNotEmpty) {
        final connected = await _sunmiPrinter.isConnected();
        await _updateDeviceStatus(
            'sunmi_internal', connected ? 'connected' : 'disconnected');
      }
    } catch (e) {
      debugPrint('Sunmi durum güncelleme hatası: $e');
    }
  }

  /// Aygıt ekle
  Future<void> _addDevice(Map<String, dynamic> device) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devices = await getAllDevices();

      // Zaten varsa güncelle
      final existingIndex = devices.indexWhere((d) => d['id'] == device['id']);
      if (existingIndex != -1) {
        devices[existingIndex] = device;
      } else {
        devices.add(device);
      }

      // Kaydet
      final devicesJson = devices.map((d) {
        return '${d['id']}|${d['name']}|${d['type']}|${d['connection']}|${d['status']}|${d['isDefault'] ?? false}';
      }).toList();

      await prefs.setStringList(_devicesKey, devicesJson);
    } catch (e) {
      debugPrint('Aygıt ekleme hatası: $e');
    }
  }

  /// Aygıt durumunu güncelle
  Future<void> _updateDeviceStatus(String deviceId, String status) async {
    try {
      final devices = await getAllDevices();
      final deviceIndex = devices.indexWhere((d) => d['id'] == deviceId);

      if (deviceIndex != -1) {
        devices[deviceIndex]['status'] = status;

        final prefs = await SharedPreferences.getInstance();
        final devicesJson = devices.map((d) {
          return '${d['id']}|${d['name']}|${d['type']}|${d['connection']}|${d['status']}|${d['isDefault'] ?? false}';
        }).toList();

        await prefs.setStringList(_devicesKey, devicesJson);
      }
    } catch (e) {
      debugPrint('Aygıt durum güncelleme hatası: $e');
    }
  }

  /// Varsayılan yazıcıyı ayarla
  Future<void> setDefaultPrinter(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_defaultPrinterKey, deviceId);

      // Tüm aygıtların isDefault durumunu güncelle
      final devices = await getAllDevices();
      for (var device in devices) {
        device['isDefault'] = device['id'] == deviceId;
      }

      final devicesJson = devices.map((d) {
        return '${d['id']}|${d['name']}|${d['type']}|${d['connection']}|${d['status']}|${d['isDefault']}';
      }).toList();

      await prefs.setStringList(_devicesKey, devicesJson);

      debugPrint('Varsayılan yazıcı ayarlandı: $deviceId');
    } catch (e) {
      debugPrint('Varsayılan yazıcı ayarlama hatası: $e');
    }
  }

  /// Varsayılan yazıcıyı al
  Future<Map<String, dynamic>?> getDefaultPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final defaultId = prefs.getString(_defaultPrinterKey);

      if (defaultId != null) {
        final devices = await getAllDevices();
        return devices.firstWhere(
          (d) => d['id'] == defaultId,
          orElse: () => {},
        );
      }

      return null;
    } catch (e) {
      debugPrint('Varsayılan yazıcı alma hatası: $e');
      return null;
    }
  }

  /// Yazıcı test et
  Future<bool> testPrinter(String deviceId) async {
    try {
      final devices = await getAllDevices();
      final device = devices.firstWhere(
        (d) => d['id'] == deviceId,
        orElse: () => {},
      );

      if (device.isEmpty) {
        debugPrint('Test edilecek yazıcı bulunamadı: $deviceId');
        return false;
      }

      debugPrint('Yazıcı test ediliyor: ${device['name']}');

      // Sunmi dahili yazıcı için test
      if (deviceId == 'sunmi_internal') {
        return await _sunmiPrinter.printTest();
      }

      // Bluetooth yazıcılar için test (gelecekte eklenecek)
      debugPrint('⚠ Bluetooth yazıcı testi henüz desteklenmiyor');
      return false;
    } catch (e) {
      debugPrint('Yazıcı test hatası: $e');
      return false;
    }
  }

  /// Tüm aygıt durumlarını yenile
  Future<void> refreshAllDevices() async {
    try {
      debugPrint('Aygıt durumları yenileniyor...');

      // Sunmi yazıcı durumunu güncelle
      await _updateSunmiStatus();

      // Bluetooth aygıtları tarama (gelecekte eklenecek)

      debugPrint('✓ Aygıt durumları güncellendi');
    } catch (e) {
      debugPrint('Aygıt yenileme hatası: $e');
    }
  }

  /// Aygıt sil
  Future<void> removeDevice(String deviceId) async {
    try {
      // Dahili aygıtlar silinemez
      if (deviceId == 'sunmi_internal') {
        debugPrint('⚠ Dahili aygıtlar silinemez');
        return;
      }

      final devices = await getAllDevices();
      devices.removeWhere((d) => d['id'] == deviceId);

      final prefs = await SharedPreferences.getInstance();
      final devicesJson = devices.map((d) {
        return '${d['id']}|${d['name']}|${d['type']}|${d['connection']}|${d['status']}|${d['isDefault'] ?? false}';
      }).toList();

      await prefs.setStringList(_devicesKey, devicesJson);

      // Eğer varsayılan yazıcı silindiyse, ilk aygıtı varsayılan yap
      final defaultPrinter = await getDefaultPrinter();
      if (defaultPrinter == null || defaultPrinter['id'] == deviceId) {
        if (devices.isNotEmpty) {
          await setDefaultPrinter(devices.first['id']);
        }
      }

      debugPrint('Aygıt silindi: $deviceId');
    } catch (e) {
      debugPrint('Aygıt silme hatası: $e');
    }
  }
}
