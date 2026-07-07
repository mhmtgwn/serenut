// lib/domain/services/license_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:pointycastle/export.dart';

class LicenseInfo {
  final String merchantId;
  final List<String> allowedDevices;
  final DateTime expiryDate;
  final LicenseTier tier;
  final List<String> features;
  final String signature;

  LicenseInfo({
    required this.merchantId,
    required this.allowedDevices,
    required this.expiryDate,
    required this.tier,
    required this.features,
    required this.signature,
  });

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    final List<String> devices = json['allowedDevices'] != null 
        ? List<String>.from(json['allowedDevices'])
        : (json['deviceUuid'] != null ? [json['deviceUuid'] as String] : []);

    final tierStr = json['tier'] as String? ?? 'BASIC';
    final tier = LicenseTier.values.firstWhere(
      (t) => t.name == tierStr,
      orElse: () => LicenseTier.basic,
    );

    final List<String> features = json['features'] != null
        ? List<String>.from(json['features'])
        : [];

    return LicenseInfo(
      merchantId: json['merchantId'] as String,
      allowedDevices: devices,
      expiryDate: DateTime.parse(json['expiryDate'] as String),
      tier: tier,
      features: features,
      signature: json['signature'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'merchantId': merchantId,
        'allowedDevices': allowedDevices,
        'expiryDate': expiryDate.toIso8601String(),
        'tier': tier.name,
        'features': features,
        'signature': signature,
      };
}

class LicenseService {
  static const String _licenseTokenKey = 'license_token';
  static const String _deviceUuidKey = 'device_uuid';
  static const String _lastSystemTimeKey = 'last_system_time';
  static const String _maxTimestampSeenKey = 'max_timestamp_seen';
  
  // RSA-2048 Public Key Modulus & Exponent
  static const String _rsaModulusHex = '24411462201226996438841939549021454888733195236274468065775741224235870828599975687442961469702706222823140813618470146034318791144081164140895510392862259766582087914988353091642332590862692172508245336721761478288563513793312713764686147506940136020087563505042690937627842320486248227124477581576031460706918080381582170251418495030474651546222624978118721452561800320320246965787168638531779352900516824205685716199734459208444432818729619600489270457687453750695905613821629449668637610680017348238336982462564377297468305133351943448287065558841371731196118193920355175788560618289960848258703300389635524278281';
  static const String _rsaExponentHex = '65537';

  final SharedPreferences _prefs;

  LicenseService(this._prefs);

  SharedPreferences get prefs => _prefs;

  /// Get the physical/logical device UUID. Generates and stores one if it doesn't exist.
  String getDeviceUuid() {
    String? deviceUuid = _prefs.getString(_deviceUuidKey);
    if (deviceUuid == null || deviceUuid.isEmpty) {
      deviceUuid = const Uuid().v4();
      _prefs.setString(_deviceUuidKey, deviceUuid);
    }
    return deviceUuid;
  }

  /// Validates a license token string cryptographically and verifies if local device matches allowed list
  bool verifyLicenseToken(String tokenStr) {
    try {
      final decodedJson = utf8.decode(base64.decode(tokenStr.trim()));
      final jsonMap = json.decode(decodedJson) as Map<String, dynamic>;
      final info = LicenseInfo.fromJson(jsonMap);

      // 1. Verify device UUID matches allowed devices list or wildcard
      final localUuid = getDeviceUuid();
      if (!info.allowedDevices.contains('*') && !info.allowedDevices.contains(localUuid)) {
        return false;
      }

      // 2. Verify signature integrity using RSA-2048 Public Key
      final signatureBytes = base64.decode(info.signature);
      final payload = "${info.merchantId}|${info.allowedDevices.join(',')}|${info.expiryDate.toIso8601String()}|${info.tier.name}|${info.features.join(',')}";
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
  Future<bool> saveLicenseToken(String tokenStr) async {
    if (verifyLicenseToken(tokenStr)) {
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
}
