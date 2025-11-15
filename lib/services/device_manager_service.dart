import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
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
      debugPrint('getAllDevices hata: $e');
      return [];
    }
  }

  Future<void> setupDefaultDevices() async {
    try {
      debugPrint('=== SUNMI DONANIM TESPITI BASLADI ===');
      final devices = await getAllDevices();
      debugPrint('Mevcut kayitli aygit sayisi: ${devices.length}');

      if (devices.isEmpty) {
        debugPrint('Sunmi donanimlari tespit ediliyor...');

        // 1. SUNMI YAZICI
        try {
          debugPrint('1. Yazici kontrol ediliyor...');
          await SunmiPrinter.bindingPrinter();
          await Future.delayed(const Duration(milliseconds: 500));

          await _addDevice({
            'id': 'sunmi_printer',
            'name': 'Sunmi Dahili Yazici',
            'type': 'printer',
            'connection': 'internal',
            'status': 'connected',
          });
          await setDefaultPrinter('sunmi_printer');
          debugPrint('   ✓ Yazici eklendi');
        } catch (e) {
          debugPrint('   ✗ Yazici hatasi: $e');
        }

        // 2. SUNMI SCANNER
        try {
          debugPrint('2. Scanner kontrol ediliyor...');
          await _addDevice({
            'id': 'sunmi_scanner',
            'name': 'Sunmi Barkod Okuyucu',
            'type': 'scanner',
            'connection': 'internal',
            'status': 'connected',
          });
          debugPrint('   ✓ Scanner eklendi');
        } catch (e) {
          debugPrint('   ✗ Scanner hatasi: $e');
        }

        // 3. SUNMI LCD
        try {
          debugPrint('3. LCD kontrol ediliyor...');
          await SunmiLcd.configLCD(SunmiLCDStatus.INIT);
          await Future.delayed(const Duration(milliseconds: 300));

          await _addDevice({
            'id': 'sunmi_lcd',
            'name': 'Musteri Ekrani',
            'type': 'lcd',
            'connection': 'internal',
            'status': 'connected',
          });
          debugPrint('   ✓ LCD eklendi');
        } catch (e) {
          debugPrint('   ✗ LCD hatasi: $e');
        }

        // 4. SUNMI DRAWER
        try {
          debugPrint('4. Drawer kontrol ediliyor...');
          final drawerOpen = await SunmiDrawer.i.isDrawerOpen();
          debugPrint('   Drawer durumu: $drawerOpen');

          await _addDevice({
            'id': 'sunmi_drawer',
            'name': 'Kasa Cekmecesi',
            'type': 'drawer',
            'connection': 'internal',
            'status': 'connected',
          });
          debugPrint('   ✓ Drawer eklendi');
        } catch (e) {
          debugPrint('   ✗ Drawer hatasi: $e');
        }

        final finalDevices = await getAllDevices();
        debugPrint(
            '=== TESPIT TAMAMLANDI - Toplam: ${finalDevices.length} aygit ===');
      } else {
        debugPrint('Aygitlar zaten kayitli (${devices.length} adet)');
      }
    } catch (e) {
      debugPrint('!!! TESPIT HATASI: $e');
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
      debugPrint('      SharedPreferences kaydedildi: ${device['name']}');
    } catch (e) {
      debugPrint('_addDevice hata: $e');
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
      debugPrint('setDefaultPrinter hata: $e');
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
      debugPrint('refreshAllDevices hata: $e');
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
      debugPrint('removeDevice hata: $e');
    }
  }
}
