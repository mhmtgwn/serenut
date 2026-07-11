// lib/domain/services/license_service.dart
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:pointycastle/export.dart';

class LicenseInfo {
  final String merchantId;
  /// V2: device-specific binding. V1 legacy tokens may contain null (treated as wildcard grace period).
  final String? deviceId;
  /// Legacy V1 field — kept for backward compat during wildcard grace period only.
  final List<String>? allowedDevices;
  final DateTime expiryDate;
  final LicenseTier tier;
  final List<String> features;
  final String signature;
  final int tokenVersion;
  final int deviceTokenVersion;

  LicenseInfo({
    required this.merchantId,
    this.deviceId,
    this.allowedDevices,
    required this.expiryDate,
    required this.tier,
    required this.features,
    required this.signature,
    this.tokenVersion = 1,
    this.deviceTokenVersion = 1,
  });

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    final tierStr = (json['tier'] as String? ?? 'BASIC').toUpperCase();
    final tier = LicenseTier.values.firstWhere(
      (t) => t.name.toUpperCase() == tierStr || t.name.toUpperCase().replaceAll('_', '') == tierStr,
      orElse: () => LicenseTier.basic,
    );

    final List<String> features = json['features'] != null
        ? List<String>.from(json['features'])
        : [];

    // V1 legacy: allowed_devices list
    List<String>? legacyDevices;
    if (json['allowed_devices'] != null) {
      legacyDevices = List<String>.from(json['allowed_devices']);
    }

    return LicenseInfo(
      merchantId: (json['merchant_id'] ?? json['merchantId']) as String? ?? '',
      deviceId: json['device_id'] as String?,
      allowedDevices: legacyDevices,
      expiryDate: DateTime.parse((json['expiry_date'] ?? json['expiryDate']) as String),
      tier: tier,
      features: features,
      signature: (json['signature'] as String? ?? ''),
      tokenVersion: (json['token_version'] as int?) ?? 1,
      deviceTokenVersion: (json['device_token_version'] as int?) ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'merchant_id': merchantId,
        if (deviceId != null) 'device_id': deviceId,
        if (allowedDevices != null) 'allowed_devices': allowedDevices,
        'expiry_date': expiryDate.toIso8601String(),
        'tier': tier.name,
        'features': features,
        'signature': signature,
        'token_version': tokenVersion,
        'device_token_version': deviceTokenVersion,
      };
}

class LicenseService {
  final SharedPreferences _prefs;
  static const String _licenseTokenKey = 'license_token';
  static const String _deviceUuidKey = 'device_uuid';
  static const String _lastSystemTimeKey = 'last_system_time';
  static const String _maxTimestampSeenKey = 'max_timestamp_seen';
  
  // RSA-2048 Public Key Modulus & Exponent
  static const String _rsaModulusHex = '24411462201226996438841939549021454888733195236274468065775741224235870828599975687442961469702706222823140813618470146034318791144081164140895510392862259766582087914988353091642332590862692172508245336721761478288563513793312713764686147506940136020087563505042690937627842320486248227124477581576031460706918080381582170251418495030474651546222624978118721452561800320320246965787168638531779352900516824205685716199734459208444432818729619600489270457687453750695905613821629449668637610680017348238336982462564377297468305133351943448287065558841371731196118193920355175788560618289960848258703300389635524278281';
  static const String _rsaExponentHex = '65537';

  LicenseService(this._prefs);

  SharedPreferences get prefs => _prefs;

  /// Ensure local device has a persistent unique hardware ID
  String getDeviceUuid() {
    String? deviceUuid = _prefs.getString(_deviceUuidKey);
    if (deviceUuid == null || deviceUuid.isEmpty) {
      deviceUuid = const Uuid().v4();
      _prefs.setString(_deviceUuidKey, deviceUuid);
    }
    return deviceUuid;
  }

  /// Validates a license token string cryptographically and verifies if local device matches.
  /// V2 tokens: device_id must match local UUID.
  /// V1 legacy tokens: allowed_devices wildcard '[*]' accepted during grace period.
  bool verifyLicenseToken(String tokenStr) {
    try {
      final decodedJson = utf8.decode(base64.decode(tokenStr.trim()));
      final jsonMap = json.decode(decodedJson) as Map<String, dynamic>;
      final info = LicenseInfo.fromJson(jsonMap);

      final localUuid = getDeviceUuid();

      // 1. Device binding check
      if (info.tokenVersion >= 2) {
        // V2: must match exact device_id
        if (info.deviceId == null || info.deviceId != localUuid) {
          return false;
        }
      } else {
        // V1 legacy: wildcard grace period
        final devices = info.allowedDevices ?? [];
        if (!devices.contains('*') && !devices.contains(localUuid)) {
          return false;
        }
      }

      // 2. Verify signature integrity using RSA-2048 Public Key in Canonical JSON format
      final signatureBytes = base64.decode(info.signature);

      // Construct the same canonical payload as the backend (alphabetical key order)
      final Map<String, dynamic> payloadMap;
      if (info.tokenVersion >= 2) {
        payloadMap = {
          'device_id': info.deviceId,
          'device_token_version': info.deviceTokenVersion,
          'expiry_date': info.expiryDate.toIso8601String(),
          'features': info.features,
          'merchant_id': info.merchantId,
          'tier': info.tier == LicenseTier.proPlus ? 'pro_plus' : info.tier.name.toLowerCase(),
          'token_version': info.tokenVersion,
        };
      } else {
        // V1 canonical payload
        payloadMap = {
          'allowed_devices': info.allowedDevices ?? ['*'],
          'expiry_date': info.expiryDate.toIso8601String(),
          'features': info.features,
          'merchant_id': info.merchantId,
          'tier': info.tier == LicenseTier.proPlus ? 'pro_plus' : info.tier.name.toLowerCase(),
        };
      }

      // Sort keys alphabetically to match backend canonical ordering
      final sortedKeys = payloadMap.keys.toList()..sort();
      final sortedMap = {for (final k in sortedKeys) k: payloadMap[k]};
      final payload = json.encode(sortedMap);
      final payloadBytes = utf8.encode(payload);

      final modulus = BigInt.parse(_rsaModulusHex);
      final publicExponent = BigInt.parse(_rsaExponentHex);

      final publicKey = RSAPublicKey(modulus, publicExponent);
      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
      verifier.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

      final rsaSignature = RSASignature(signatureBytes);
      return verifier.verifySignature(payloadBytes, rsaSignature);
    } catch (_) {
      return false;
    }
  }

  /// Saves the license token to preferences
  Future<bool> saveLicenseToken(String tokenStr, [String? licenseKey]) async {
    if (verifyLicenseToken(tokenStr)) {
      if (licenseKey != null) {
        await _prefs.setString('activated_license_key', licenseKey);
      }
      return await _prefs.setString(_licenseTokenKey, tokenStr.trim());
    }
    return false;
  }

  /// Get decoded LicenseInfo if a valid license exists
  LicenseInfo? getLicenseInfo() {
    final tokenStr = _prefs.getString(_licenseTokenKey);
    if (tokenStr == null || tokenStr.isEmpty) return null;
    
    try {
      final decodedJson = utf8.decode(base64.decode(tokenStr.trim()));
      final jsonMap = json.decode(decodedJson) as Map<String, dynamic>;
      return LicenseInfo.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  /// Get the raw license token string
  String? getLicenseToken() {
    return _prefs.getString(_licenseTokenKey);
  }

  /// Updates the max observed timestamp seen from any source (sales, backups, clocks)
  void updateMaxTimestampSeen(DateTime time) {
    final maxTimeStr = _prefs.getString(_maxTimestampSeenKey);
    if (maxTimeStr != null) {
      try {
        final currentMax = DateTime.parse(maxTimeStr);
        if (time.isAfter(currentMax)) {
          _prefs.setString(_maxTimestampSeenKey, time.toIso8601String());
        }
      } catch (_) {}
    } else {
      _prefs.setString(_maxTimestampSeenKey, time.toIso8601String());
    }
  }

  /// Strong clock integrity check (checks last system time AND max timestamp seen across all events)
  bool checkClockIntegrity() {
    final now = DateTime.now();
    
    // 1. Check last recorded system time
    final lastTimeStr = _prefs.getString(_lastSystemTimeKey);
    if (lastTimeStr != null) {
      try {
        final lastTime = DateTime.parse(lastTimeStr);
        // Allow a small 5 minute grace margin for minor NTP drift
        if (now.add(const Duration(minutes: 5)).isBefore(lastTime)) {
          return false; // Time travel / clock tempering!
        }
      } catch (_) {
        return false;
      }
    }

    // 2. Check max observed timestamp seen from sales/backups
    final maxTimeStr = _prefs.getString(_maxTimestampSeenKey);
    if (maxTimeStr != null) {
      try {
        final maxTime = DateTime.parse(maxTimeStr);
        if (now.add(const Duration(minutes: 5)).isBefore(maxTime)) {
          return false; // Time travel / clock tempering!
        }
      } catch (_) {
        return false;
      }
    }

    // Update both trackers with current time
    _prefs.setString(_lastSystemTimeKey, now.toIso8601String());
    updateMaxTimestampSeen(now);
    return true;
  }

  /// Clear stored license (for license renewal or resetting)
  Future<void> clearLicense() async {
    await _prefs.remove(_licenseTokenKey);
  }

  /// Get status of license. Returns:
  /// - 'valid': License is cryptographically signed, matches UUID, and in future.
  /// - 'expired': License is valid but date has passed.
  /// - 'unlicensed': No license installed or invalid signature.
  /// - 'tampered': Clock manipulation detected.
  String checkLicenseStatus() {
    if (!checkClockIntegrity()) {
      return 'tampered';
    }

    final info = getLicenseInfo();
    if (info == null) {
      return 'unlicensed';
    }

    // Verify key holds true integrity checks
    final tokenStr = _prefs.getString(_licenseTokenKey)!;
    if (!verifyLicenseToken(tokenStr)) {
      return 'unlicensed';
    }

    final now = DateTime.now();
    if (now.isAfter(info.expiryDate)) {
      // Emergency Offline Grace Mode: Allow a 7-day grace period for offline POS cash registers
      // if licensing server heartbeats fail or are temporarily unreachable.
      final graceEnd = info.expiryDate.add(const Duration(days: 7));
      if (now.isAfter(graceEnd)) {
        return 'expired';
      }
    }

    return 'valid';
  }

  /// Returns remaining days on active license
  int getRemainingDays() {
    final info = getLicenseInfo();
    if (info == null) return 0;
    final diff = info.expiryDate.difference(DateTime.now());
    return diff.inDays;
  }

  Timer? _heartbeatTimer;

  /// Starts periodic heartbeat checks.
  void startHeartbeat(ApiClient apiClient) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(hours: 12), (_) async {
      await performHeartbeatCheck(apiClient);
    });
    // Trigger initial run in background after a brief startup delay
    Future.delayed(const Duration(seconds: 5), () => performHeartbeatCheck(apiClient));
  }

  /// Cancels periodic heartbeat checks.
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Perform remote heartbeat validation check
  Future<bool> performHeartbeatCheck(ApiClient apiClient) async {
    final licenseKey = _prefs.getString('activated_license_key') ?? '';
    if (licenseKey.isEmpty) return false;

    try {
      final response = await apiClient.send(
        'POST',
        '/api/v1/licenses/heartbeat',
        body: {
          'license_key': licenseKey,
          'device_hash': getDeviceUuid(),
        },
      );

      if (response.isSuccess) {
        final resJson = response.json;
        final licenseInfo = resJson['license_info'] as Map<String, dynamic>?;
        final signature = resJson['signature'] as String?;

        if (licenseInfo != null && signature != null) {
          final Map<String, dynamic> localTokenMap = {
            'merchant_id': licenseInfo['merchant_id'] ?? licenseInfo['merchantId'],
            if (licenseInfo.containsKey('device_id'))
              'device_id': licenseInfo['device_id']
            else
              'allowed_devices': licenseInfo['allowed_devices'],
            'expiry_date': licenseInfo['expiry_date'],
            'tier': licenseInfo['tier'],
            'features': licenseInfo['features'],
            'signature': signature,
            'token_version': licenseInfo['token_version'] ?? 1,
            if (licenseInfo.containsKey('device_token_version'))
              'device_token_version': licenseInfo['device_token_version'],
          };

          final tokenStr = base64.encode(utf8.encode(json.encode(localTokenMap)));
          return await saveLicenseToken(tokenStr);
        }
      } else if (response.statusCode == 403 || response.statusCode == 404) {
        // Blocked, revoked or expired — clear license token locally to force paywall/deactivation!
        await clearLicense();
        return false;
      }
    } catch (_) {
      // In case of network errors or server downtime, allow offline grace checks (7-day grace period)
    }
    return false;
  }
}
