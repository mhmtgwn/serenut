// lib/infrastructure/services/device_fingerprint_service.dart
// Serenut OS — Device Fingerprint Service (Sprint 1)

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/device_fingerprint.dart';
import '../../domain/services/device_manager.dart';

class DeviceFingerprintService {
  static const _installationIdKey = 'serenut_installation_id';
  static const _installDateKey = 'serenut_install_date';
  static const _legacyInstallationIdKey = 'nutopiano_installation_id';
  static const _legacyInstallDateKey = 'nutopiano_install_date';
  final SharedPreferences _prefs;
  final DeviceManager _deviceManager;

  DeviceFingerprintService(this._prefs, this._deviceManager);

  /// Get or create installation date
  String getInstallDate() {
    String? date = _prefs.getString(_installDateKey);
    if (date == null || date.isEmpty) {
      date = _prefs.getString(_legacyInstallDateKey);
    }
    if (date == null || date.isEmpty) {
      date = DateTime.now().toIso8601String();
    }
    _prefs.setString(_installDateKey, date);
    _prefs.remove(_legacyInstallDateKey);
    return date;
  }

  /// Get or create installation ID
  String getInstallationId() {
    String? id = _prefs.getString(_installationIdKey);
    if (id == null || id.isEmpty) {
      id = _prefs.getString(_legacyInstallationIdKey);
    }
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
    }
    _prefs.setString(_installationIdKey, id);
    _prefs.remove(_legacyInstallationIdKey);
    return id;
  }

  /// Computes a stable machine hash based on system environment values
  String getMachineHash() {
    final buffer = StringBuffer();
    buffer.write(Platform.operatingSystem);
    buffer.write(Platform.operatingSystemVersion);
    buffer.write(Platform.numberOfProcessors);

    // Add stable environment parameters
    if (Platform.isWindows) {
      buffer.write(Platform.environment['COMPUTERNAME'] ?? '');
      buffer.write(Platform.environment['PROCESSOR_IDENTIFIER'] ?? '');
    } else {
      buffer.write(Platform.environment['HOST'] ?? '');
    }

    final bytes = utf8.encode(buffer.toString());
    return sha256.convert(bytes).toString();
  }

  /// Computes a hardware hash that is slightly more robust (e.g. CPU + OS arch).
  /// NOTE: Platform.version (Dart SDK) intentionally excluded — it changes on
  /// every app update and would trigger false-positive hardware-change events.
  String getHardwareHash() {
    final buffer = StringBuffer();
    buffer.write(Platform.numberOfProcessors);
    buffer
        .write(Platform.operatingSystemVersion); // OS version — SDK-independent
    buffer
        .write(Platform.localHostname); // Machine name — stable across updates
    if (Platform.isWindows) {
      buffer.write(Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '');
    }
    final bytes = utf8.encode(buffer.toString());
    return sha256.convert(bytes).toString();
  }

  /// Collect all details to build the current DeviceFingerprint payload
  Future<DeviceFingerprint> getFingerprint() async {
    final cpuArch = Platform.isWindows
        ? (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'x64')
        : 'arm64';

    return DeviceFingerprint(
      installationId: getInstallationId(),
      deviceUuid: _deviceManager.getDeviceId(),
      machineHash: getMachineHash(),
      hardwareHash: getHardwareHash(),
      cpuArchitecture: cpuArch,
      osVersion: Platform.operatingSystemVersion,
      appVersion: '1.0.0', // Application version
      deviceName: Platform.localHostname,
      platform: Platform.operatingSystem,
      installDate: getInstallDate(),
      lastSeen: DateTime.now().toIso8601String(),
    );
  }
}
