import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/hardware/hardware_device_repository.dart';

class SharedPreferencesHardwareDeviceRepository
    implements HardwareDeviceRepository {
  static const storageKey = 'hardware_device_registry_v1';
  final SharedPreferences preferences;

  const SharedPreferencesHardwareDeviceRepository(this.preferences);

  @override
  Future<List<HardwareDevice>> getAll() async {
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((value) =>
            HardwareDevice.fromJson(Map<String, Object?>.from(value as Map)))
        .toList(growable: false);
  }

  @override
  Future<void> save(HardwareDevice device) async {
    final devices = (await getAll()).toList();
    final index = devices.indexWhere((item) => item.id == device.id);
    index == -1 ? devices.add(device) : devices[index] = device;
    await _write(devices);
  }

  @override
  Future<void> delete(String id) async {
    await _write(
      (await getAll()).where((device) => device.id != id).toList(),
    );
  }

  Future<void> _write(List<HardwareDevice> devices) {
    return preferences.setString(
      storageKey,
      jsonEncode(devices.map((device) => device.toJson()).toList()),
    );
  }
}
