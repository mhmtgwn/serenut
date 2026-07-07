// lib/domain/models/device_registry.dart
class DeviceRegistry {
  final String deviceId;
  final String model;
  final String appVersion;
  final String? licenseId;
  final String status; // 'active', 'pending', 'blocked'

  DeviceRegistry({
    required this.deviceId,
    required this.model,
    required this.appVersion,
    this.licenseId,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'model': model,
        'appVersion': appVersion,
        'licenseId': licenseId,
        'status': status,
      };

  factory DeviceRegistry.fromMap(Map<String, dynamic> map) => DeviceRegistry(
        deviceId: map['deviceId'] as String,
        model: map['model'] as String,
        appVersion: map['appVersion'] as String,
        licenseId: map['licenseId'] as String?,
        status: map['status'] as String,
      );
}
