// lib/domain/models/device_fingerprint.dart
// Serenut OS — Device Fingerprint Model (Sprint 1)

class DeviceFingerprint {
  final String installationId;
  final String deviceUuid;
  final String machineHash;
  final String hardwareHash;
  final String cpuArchitecture;
  final String osVersion;
  final String appVersion;
  final String deviceName;
  final String platform;
  final String installDate;
  final String lastSeen;

  DeviceFingerprint({
    required this.installationId,
    required this.deviceUuid,
    required this.machineHash,
    required this.hardwareHash,
    required this.cpuArchitecture,
    required this.osVersion,
    required this.appVersion,
    required this.deviceName,
    required this.platform,
    required this.installDate,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'installation_id': installationId,
        'device_uuid': deviceUuid,
        'machine_hash': machineHash,
        'hardware_hash': hardwareHash,
        'cpu_architecture': cpuArchitecture,
        'os_version': osVersion,
        'app_version': appVersion,
        'device_name': deviceName,
        'platform': platform,
        'install_date': installDate,
        'last_seen': lastSeen,
      };

  factory DeviceFingerprint.fromJson(Map<String, dynamic> json) => DeviceFingerprint(
        installationId: json['installation_id'] as String? ?? '',
        deviceUuid: json['device_uuid'] as String? ?? '',
        machineHash: json['machine_hash'] as String? ?? '',
        hardwareHash: json['hardware_hash'] as String? ?? '',
        cpuArchitecture: json['cpu_architecture'] as String? ?? '',
        osVersion: json['os_version'] as String? ?? '',
        appVersion: json['app_version'] as String? ?? '',
        deviceName: json['device_name'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        installDate: json['install_date'] as String? ?? '',
        lastSeen: json['last_seen'] as String? ?? '',
      );
}
