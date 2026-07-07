// lib/domain/services/device_manager.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceManager {
  static const String _deviceIdKey = 'nutopiano_device_id';
  final SharedPreferences _prefs;

  DeviceManager(this._prefs);

  /// Retrieves or generates a persistent device ID.
  /// Uses a stored UUID in SharedPreferences to remain stable across installs.
  String getDeviceId() {
    String? deviceId = _prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      _prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }
}
