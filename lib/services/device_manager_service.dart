import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sunmi_printer_service.dart';

class DeviceManagerService {
  static final DeviceManagerService _instance =
      DeviceManagerService._internal();
  factory DeviceManagerService() => _instance;
  DeviceManagerService._internal();

  final SunmiPrinterService _sunmiPrinter = SunmiPrinterService();

  static const String _devicesKey = 'registered_devices';
  static const String _defaultPrinterKey = 'default_printer_id';

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
      debugPrint('Hata: $e');
      return [];
    }
  }

  Future<void> setupDefaultDevices() async {
    try {
      final devices = await getAllDevices();

      if (devices.isEmpty) {
        debugPrint('Varsayilan aygitlar kuruluyor...');

        final printerConnected = await _sunmiPrinter.isConnected();
        if (printerConnected) {
          final printerInfo = await _sunmiPrinter.getPrinterInfo();

          await _addDevice({
            'id': 'sunmi_printer',
            'name': 'Sunmi Dahili Yazici',
            'type': 'printer',
            'connection': 'internal',
            'status': 'connected',
          });

          await setDefaultPrinter('sunmi_printer');
          debugPrint('Sunmi yazici eklendi');
        }

        final scannerAvailable = await _checkSunmiScanner();
        if (scannerAvailable) {
          await _addDevice({
            'id': 'sunmi_scanner',
            'name': 'Sunmi Barkod Okuyucu',
            'type': 'scanner',
            'connection': 'internal',
            'status': 'connected',
          });
          debugPrint('Scanner eklendi');
        }
      }
    } catch (e) {
      debugPrint('Kurulum hatasi: $e');
    }
  }

  Future<bool> _checkSunmiScanner() async {
    try {
      const channel = MethodChannel('com.sunmi.scanner');
      final result = await channel.invokeMethod<bool>('hasScanner');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _addDevice(Map<String, dynamic> device) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devices = await getAllDevices();

      final existingIndex = devices.indexWhere((d) => d['id'] == device['id']);
      if (existingIndex != -1) {
        devices[existingIndex] = device;
      } else {
        devices.add(device);
      }

      final devicesJson = devices.map((d) {
        return '${d['id']}|${d['name']}|${d['type']}|${d['connection']}|${d['status']}|${d['isDefault'] ?? false}';
      }).toList();

      await prefs.setStringList(_devicesKey, devicesJson);
    } catch (e) {
      debugPrint('Ekleme hatasi: $e');
    }
  }

  Future<void> setDefaultPrinter(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_defaultPrinterKey, deviceId);

      final devices = await getAllDevices();
      for (var device in devices) {
        device['isDefault'] = device['id'] == deviceId;
      }

      final devicesJson = devices.map((d) {
        return '${d['id']}|${d['name']}|${d['type']}|${d['connection']}|${d['status']}|${d['isDefault']}';
      }).toList();

      await prefs.setStringList(_devicesKey, devicesJson);
    } catch (e) {
      debugPrint('Varsayilan ayarlama hatasi: $e');
    }
  }

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
      return null;
    }
  }

  Future<bool> testPrinter(String deviceId) async {
    try {
      if (deviceId == 'sunmi_printer') {
        return await _sunmiPrinter.printTest();
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> refreshAllDevices() async {
    try {
      debugPrint('Yenileniyor...');
    } catch (e) {
      debugPrint('Yenileme hatasi: $e');
    }
  }

  Future<void> removeDevice(String deviceId) async {
    try {
      if (deviceId.startsWith('sunmi_')) {
        return;
      }

      final devices = await getAllDevices();
      devices.removeWhere((d) => d['id'] == deviceId);

      final prefs = await SharedPreferences.getInstance();
      final devicesJson = devices.map((d) {
        return '${d['id']}|${d['name']}|${d['type']}|${d['connection']}|${d['status']}|${d['isDefault'] ?? false}';
      }).toList();

      await prefs.setStringList(_devicesKey, devicesJson);
    } catch (e) {
      debugPrint('Silme hatasi: $e');
    }
  }
}
