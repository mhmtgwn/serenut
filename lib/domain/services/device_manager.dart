// lib/domain/services/device_manager.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceManager {
  /// The only client-side identity used by licensing, sync, updates and
  /// telemetry. It is an installation identifier, not a hardware fingerprint.
  static const String deviceIdKey = 'serenut_device_id';
  static const String _legacyLicenseKey = 'device_uuid';
  static const String _legacyNutopianoKey = 'nutopiano_device_id';
  static const String _legacySyncV4Key = 'sync_v4_device_id';
  final SharedPreferences _prefs;

  DeviceManager(this._prefs);

  /// Retrieves or generates a persistent device ID.
  ///
  /// Existing installations keep their former license UUID. Replacing it
  /// would invalidate server-side device activation.
  String getDeviceId() {
    return resolveDeviceId(_prefs);
  }

  static String resolveDeviceId(SharedPreferences prefs) {
    final current = prefs.getString(deviceIdKey)?.trim();
    if (current != null && current.isNotEmpty) return current;

    // The license UUID was sent to the server, so it wins during migration.
    final migrated = prefs.getString(_legacyLicenseKey)?.trim() ??
        prefs.getString(_legacyNutopianoKey)?.trim() ??
        prefs.getString(_legacySyncV4Key)?.trim() ??
        const Uuid().v4();
    final deviceId = migrated.isEmpty ? const Uuid().v4() : migrated;

    prefs.setString(deviceIdKey, deviceId);
    prefs.remove(_legacyLicenseKey);
    prefs.remove(_legacyNutopianoKey);
    prefs.remove(_legacySyncV4Key);
    return deviceId;
  }
}
