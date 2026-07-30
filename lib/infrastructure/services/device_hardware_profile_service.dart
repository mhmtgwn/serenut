import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

/// Device-scoped cloud backup for non-secret hardware configuration.
/// Local configuration remains authoritative while offline.
class DeviceHardwareProfileService {
  const DeviceHardwareProfileService({
    required ApiClient apiClient,
    required LicenseService licenseService,
  })  : _apiClient = apiClient,
        _licenseService = licenseService;

  final ApiClient _apiClient;
  final LicenseService _licenseService;

  bool get canSync {
    final license = _licenseService.getLicenseInfo();
    return _apiClient.jwtToken?.isNotEmpty == true &&
        license?.activationId?.isNotEmpty == true &&
        license?.deviceId?.isNotEmpty == true;
  }

  Future<List<HardwareDevice>> restore() async {
    final identity = _identity();
    if (identity == null) return const [];
    final response = await _apiClient.post(
      '/api/v4/sync/device-hardware-profile/restore',
      identity,
    );
    final body = Map<String, dynamic>.from(response.json as Map);
    final profile = body['profile'];
    if (profile is! List) return const [];
    return profile
        .whereType<Map>()
        .map((item) => HardwareDevice.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }

  Future<void> backup(List<HardwareDevice> devices) async {
    final identity = _identity();
    if (identity == null) return;
    await _apiClient.put(
      '/api/v4/sync/device-hardware-profile',
      {
        ...identity,
        'profile': devices.map(_safeJson).toList(growable: false),
      },
    );
  }

  Map<String, dynamic>? _identity() {
    final license = _licenseService.getLicenseInfo();
    final activationId = license?.activationId;
    final deviceId = license?.deviceId;
    if (activationId == null ||
        activationId.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty ||
        _apiClient.jwtToken?.isNotEmpty != true) {
      return null;
    }
    return {
      'device_activation_id': activationId,
      'device_id': deviceId,
    };
  }

  static Map<String, Object?> _safeJson(HardwareDevice device) {
    const forbidden = <String>{
      'password',
      'secret',
      'apikey',
      'api_key',
      'pin',
      'token',
    };
    final json = device.toJson();
    final configuration =
        Map<String, Object?>.from(json['configuration'] as Map? ?? const {});
    configuration.removeWhere(
      (key, _) => forbidden.contains(key.toLowerCase()),
    );
    return {...json, 'configuration': configuration};
  }
}
