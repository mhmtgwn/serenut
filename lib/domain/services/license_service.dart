// lib/domain/services/license_service.dart
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite/sqflite.dart';
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
      (t) =>
          t.name.toUpperCase() == tierStr ||
          t.name.toUpperCase().replaceAll('_', '') == tierStr,
      orElse: () => LicenseTier.basic,
    );

    final List<String> features =
        json['features'] != null ? List<String>.from(json['features']) : [];

    List<String>? legacyDevices;
    if (json['allowed_devices'] != null) {
      legacyDevices = List<String>.from(json['allowed_devices']);
    }

    return LicenseInfo(
      merchantId: (json['merchant_id'] ?? json['merchantId']) as String? ?? '',
      deviceId: json['device_id'] as String?,
      allowedDevices: legacyDevices,
      expiryDate:
          DateTime.parse((json['expiry_date'] ?? json['expiryDate']) as String),
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
  static const String _rsaModulusHex =
      '24411462201226996438841939549021454888733195236274468065775741224235870828599975687442961469702706222823140813618470146034318791144081164140895510392862259766582087914988353091642332590862692172508245336721761478288563513793312713764686147506940136020087563505042690937627842320486248227124477581576031460706918080381582170251418495030474651546222624978118721452561800320320246965787168638531779352900516824205685716199734459208444432818729619600489270457687453750695905613821629449668637610680017348238336982462564377297468305133351943448287065558841371731196118193920355175788560618289960848258703300389635524278281';
  static const String _rsaExponentHex = '65537';

  String? _cachedLicenseToken;
  String? _cachedLastSystemTime;
  String? _cachedMaxTimestampSeen;
  bool _isTampered = false;
  final Stopwatch _stopwatch = Stopwatch()..start();
  final DateTime _startTime = DateTime.now();

  LicenseService(this._prefs);

  SharedPreferences get prefs => _prefs;

  Future<Database> _getDb() => DatabaseManager().getDatabase();

  Future<String?> _getSettingsValue(String column) async {
    try {
      final db = await _getDb();
      final rows = await db.query('settings', columns: [column], limit: 1);
      if (rows.isNotEmpty) {
        return rows.first[column] as String?;
      }
    } catch (e) {
      debugPrint('Failed to read settings column $column: $e');
    }
    return null;
  }

  Future<void> _setSettingsValue(String column, String? value) async {
    try {
      final db = await _getDb();
      final rows = await db.query('settings', columns: ['id'], limit: 1);
      if (rows.isNotEmpty) {
        final id = rows.first['id'] as int;
        await db.update('settings', {column: value},
            where: 'id = ?', whereArgs: [id]);
      } else {
        await db.insert('settings', {
          column: value,
          'business_name': '',
          'business_phone': '',
          'business_address': '',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Failed to update settings column $column: $e');
    }
  }

  /// Load values from database to memory cache and check clock integrity
  Future<void> initialize() async {
    try {
      final db = await _getDb();
      final rows = await db.query('settings',
          columns: ['license_token', 'last_system_time', 'max_timestamp_seen'],
          limit: 1);
      if (rows.isNotEmpty) {
        final row = rows.first;
        _cachedLicenseToken = row['license_token'] as String?;
        _cachedLastSystemTime = row['last_system_time'] as String?;
        _cachedMaxTimestampSeen = row['max_timestamp_seen'] as String?;
      }
    } catch (e) {
      debugPrint('LicenseService: database query during initialize failed: $e');
    }

    _isTampered = !await verifyClockIntegrityAsync();
  }

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
  bool verifyLicenseToken(String tokenStr) {
    try {
      final decodedJson = utf8.decode(base64.decode(tokenStr.trim()));
      final jsonMap = json.decode(decodedJson) as Map<String, dynamic>;
      final info = LicenseInfo.fromJson(jsonMap);

      final localUuid = getDeviceUuid();

      // 1. Device binding check
      if (info.tokenVersion >= 2) {
        if (info.deviceId == null || info.deviceId != localUuid) {
          return false;
        }
      } else {
        final devices = info.allowedDevices ?? [];
        if (!devices.contains('*') && !devices.contains(localUuid)) {
          return false;
        }
      }

      // 2. Verify signature integrity using RSA-2048 Public Key in Canonical JSON format
      final signatureBytes = base64.decode(info.signature);

      final Map<String, dynamic> payloadMap;
      if (info.tokenVersion >= 2) {
        payloadMap = {
          'device_id': info.deviceId,
          'device_token_version': info.deviceTokenVersion,
          'expiry_date': info.expiryDate.toIso8601String(),
          'features': info.features,
          'merchant_id': info.merchantId,
          'tier': info.tier == LicenseTier.proPlus
              ? 'pro_plus'
              : info.tier.name.toLowerCase(),
          'token_version': info.tokenVersion,
        };
      } else {
        payloadMap = {
          'allowed_devices': info.allowedDevices ?? ['*'],
          'expiry_date': info.expiryDate.toIso8601String(),
          'features': info.features,
          'merchant_id': info.merchantId,
          'tier': info.tier == LicenseTier.proPlus
              ? 'pro_plus'
              : info.tier.name.toLowerCase(),
        };
      }

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

  /// Saves the license token
  Future<bool> saveLicenseToken(String tokenStr, [String? licenseKey]) async {
    if (verifyLicenseToken(tokenStr)) {
      if (licenseKey != null) {
        await _prefs.setString('activated_license_key', licenseKey);
      }
      _cachedLicenseToken = tokenStr.trim();
      await _prefs.setString(_licenseTokenKey, tokenStr.trim());
      await _setSettingsValue('license_token', tokenStr.trim());
      return true;
    }
    return false;
  }

  /// Get decoded LicenseInfo if a valid license exists
  LicenseInfo? getLicenseInfo() {
    final tokenStr = getLicenseToken();
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
    return _cachedLicenseToken ?? _prefs.getString(_licenseTokenKey);
  }

  /// Helper to parse timestamps in either legacy local time format (no timezone suffix)
  /// or new UTC format (with 'Z' suffix).
  DateTime _parseLegacyOrUtc(String timeStr) {
    if (timeStr.endsWith('Z')) {
      return DateTime.parse(timeStr); // Parsed directly as UTC
    } else {
      // Legacy format (local time). Parse as local and convert to UTC
      return DateTime.parse(timeStr).toUtc();
    }
  }

  /// Updates the max observed timestamp seen from any source (sales, backups, clocks)
  void updateMaxTimestampSeen(DateTime time) {
    final utcTime = time.toUtc();
    final maxTimeStr =
        _cachedMaxTimestampSeen ?? _prefs.getString(_maxTimestampSeenKey);
    if (maxTimeStr != null) {
      try {
        final currentMax = _parseLegacyOrUtc(maxTimeStr);
        if (utcTime.isAfter(currentMax)) {
          final utcStr = utcTime.toIso8601String();
          _cachedMaxTimestampSeen = utcStr;
          _prefs.setString(_maxTimestampSeenKey, utcStr);
          _setSettingsValue('max_timestamp_seen', utcStr);
        }
      } catch (_) {}
    } else {
      final utcStr = utcTime.toIso8601String();
      _cachedMaxTimestampSeen = utcStr;
      _prefs.setString(_maxTimestampSeenKey, utcStr);
      _setSettingsValue('max_timestamp_seen', utcStr);
    }
  }

  /// Records the authoritative server time from HTTP response header
  void updateTrustedServerTime(String httpDateHeader) {
    try {
      final parsedDate = HttpDate.parse(httpDateHeader);
      updateMaxTimestampSeen(parsedDate);
    } catch (_) {
      try {
        final parsedDate = DateTime.parse(httpDateHeader);
        updateMaxTimestampSeen(parsedDate);
      } catch (_) {}
    }
  }

  Future<DateTime?> getMaxOperationalTimestamp() async {
    try {
      final db = await _getDb();
      final results = await db.rawQuery('''
        SELECT MAX(max_date) as max_date FROM (
          SELECT MAX(created_at) as max_date FROM sales UNION ALL
          SELECT MAX(created_at) as max_date FROM orders UNION ALL
          SELECT MAX(created_at) as max_date FROM financial_transactions
        )
      ''');
      if (results.isNotEmpty && results.first['max_date'] != null) {
        final dateStr = results.first['max_date'] as String;
        return DateTime.tryParse(dateStr);
      }
    } catch (e) {
      debugPrint('Failed to query max operational timestamp: $e');
    }
    return null;
  }

  Future<bool> verifyClockIntegrityAsync() async {
    if (_isTampered) return false;

    final now = DateTime.now().toUtc();

    // 1. Check last recorded system time
    final lastTimeStr =
        _cachedLastSystemTime ?? _prefs.getString(_lastSystemTimeKey);
    if (lastTimeStr != null) {
      try {
        final lastTime = _parseLegacyOrUtc(lastTimeStr);
        final isLegacy = !lastTimeStr.endsWith('Z');
        // Legacy local times get a wider 2-hour grace margin to absorb timezone/DST shifts on first-run migration.
        // New UTC times get a precise 5-minute margin.
        final grace =
            isLegacy ? const Duration(hours: 2) : const Duration(minutes: 5);
        if (now.add(grace).isBefore(lastTime)) {
          _isTampered = true;
          return false;
        }
      } catch (_) {
        _isTampered = true;
        return false;
      }
    }

    // 2. Check max observed timestamp seen
    final maxTimeStr =
        _cachedMaxTimestampSeen ?? _prefs.getString(_maxTimestampSeenKey);
    if (maxTimeStr != null) {
      try {
        final maxTime = _parseLegacyOrUtc(maxTimeStr);
        final isLegacy = !maxTimeStr.endsWith('Z');
        final grace =
            isLegacy ? const Duration(hours: 2) : const Duration(minutes: 5);
        if (now.add(grace).isBefore(maxTime)) {
          _isTampered = true;
          return false;
        }
      } catch (_) {
        _isTampered = true;
        return false;
      }
    }

    // 3. Check SQLite operational database max timestamp
    final maxOpTime = await getMaxOperationalTimestamp();
    if (maxOpTime != null) {
      // DB stores local times. Convert it to UTC and apply a 2-hour timezone/DST safety buffer
      final maxOpTimeUtc = maxOpTime.toUtc();
      if (now.add(const Duration(hours: 2)).isBefore(maxOpTimeUtc)) {
        _isTampered = true;
        return false;
      }
      // Auto-update max seen timestamp if operational data has a newer one
      updateMaxTimestampSeen(maxOpTimeUtc);
    }

    // Update both trackers in UTC format (with 'Z' suffix)
    final nowStr = now.toIso8601String();
    _cachedLastSystemTime = nowStr;
    _prefs.setString(_lastSystemTimeKey, nowStr);
    await _setSettingsValue('last_system_time', nowStr);

    updateMaxTimestampSeen(now);
    return true;
  }

  bool _checkClockIntegritySync() {
    final now = DateTime.now().toUtc();

    // 1. Check last recorded system time
    final lastTimeStr =
        _cachedLastSystemTime ?? _prefs.getString(_lastSystemTimeKey);
    if (lastTimeStr != null) {
      try {
        final lastTime = _parseLegacyOrUtc(lastTimeStr);
        final isLegacy = !lastTimeStr.endsWith('Z');
        final grace =
            isLegacy ? const Duration(hours: 2) : const Duration(minutes: 5);
        if (now.add(grace).isBefore(lastTime)) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }

    // 2. Check max observed timestamp seen
    final maxTimeStr =
        _cachedMaxTimestampSeen ?? _prefs.getString(_maxTimestampSeenKey);
    if (maxTimeStr != null) {
      try {
        final maxTime = _parseLegacyOrUtc(maxTimeStr);
        final isLegacy = !maxTimeStr.endsWith('Z');
        final grace =
            isLegacy ? const Duration(hours: 2) : const Duration(minutes: 5);
        if (now.add(grace).isBefore(maxTime)) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }

    // Update both trackers in UTC format
    final nowStr = now.toIso8601String();
    _cachedLastSystemTime = nowStr;
    _prefs.setString(_lastSystemTimeKey, nowStr);
    _setSettingsValue('last_system_time', nowStr);

    updateMaxTimestampSeen(now);
    return true;
  }

  /// Strong clock integrity check
  bool checkClockIntegrity() {
    if (_isTampered) return false;

    // 0. Monotonic clock drift check
    final elapsed = _stopwatch.elapsed;
    final expectedTime = _startTime.add(elapsed);
    final actualTime = DateTime.now();
    final driftSeconds = actualTime.difference(expectedTime).inSeconds.abs();
    if (driftSeconds > 15) {
      _isTampered = true;
      return false;
    }

    final now = DateTime.now().toUtc();

    final lastTimeStr =
        _cachedLastSystemTime ?? _prefs.getString(_lastSystemTimeKey);
    if (lastTimeStr != null) {
      try {
        final lastTime = _parseLegacyOrUtc(lastTimeStr);
        final isLegacy = !lastTimeStr.endsWith('Z');
        final grace =
            isLegacy ? const Duration(hours: 2) : const Duration(minutes: 5);
        if (now.add(grace).isBefore(lastTime)) {
          _isTampered = true;
          return false;
        }
      } catch (_) {
        _isTampered = true;
        return false;
      }
    }

    final maxTimeStr =
        _cachedMaxTimestampSeen ?? _prefs.getString(_maxTimestampSeenKey);
    if (maxTimeStr != null) {
      try {
        final maxTime = _parseLegacyOrUtc(maxTimeStr);
        final isLegacy = !maxTimeStr.endsWith('Z');
        final grace =
            isLegacy ? const Duration(hours: 2) : const Duration(minutes: 5);
        if (now.add(grace).isBefore(maxTime)) {
          _isTampered = true;
          return false;
        }
      } catch (_) {
        _isTampered = true;
        return false;
      }
    }

    final nowStr = now.toIso8601String();
    _cachedLastSystemTime = nowStr;
    _prefs.setString(_lastSystemTimeKey, nowStr);
    _setSettingsValue('last_system_time', nowStr);

    updateMaxTimestampSeen(now);
    return true;
  }

  /// Clear stored license
  Future<void> clearLicense() async {
    _cachedLicenseToken = null;
    await _prefs.remove(_licenseTokenKey);
    await _setSettingsValue('license_token', null);
  }

  /// Get status of license
  String checkLicenseStatus() {
    if (!checkClockIntegrity()) {
      return 'tampered';
    }

    final info = getLicenseInfo();
    if (info == null) {
      return 'unlicensed';
    }

    final tokenStr = getLicenseToken()!;
    if (!verifyLicenseToken(tokenStr)) {
      return 'unlicensed';
    }

    final now = DateTime.now();
    if (now.isAfter(info.expiryDate)) {
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
    Future.delayed(
        const Duration(seconds: 5), () => performHeartbeatCheck(apiClient));
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
            'merchant_id':
                licenseInfo['merchant_id'] ?? licenseInfo['merchantId'],
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

          final tokenStr =
              base64.encode(utf8.encode(json.encode(localTokenMap)));
          return await saveLicenseToken(tokenStr);
        }
      } else if (response.statusCode == 403 || response.statusCode == 404) {
        await clearLicense();
        return false;
      }
    } catch (_) {}
    return false;
  }

  /// Sync license from server bootstrap and perform heartbeat validation
  Future<bool> syncLicenseFromServer(ApiClient apiClient) async {
    try {
      final response =
          await apiClient.send('GET', '/api/v1/sync/bootstrap/license-config');
      debugPrint(
          '[LicenseSync] GET /sync/bootstrap/license-config → ${response.statusCode}');
      if (response.isSuccess) {
        final payload = response.json;
        final data = payload['data'] as Map<String, dynamic>?;
        if (data != null && data.containsKey('license_key')) {
          final licenseKey = data['license_key'] as String?;
          if (licenseKey != null && licenseKey.isNotEmpty) {
            debugPrint(
                '[LicenseSync] license_key alındı: ${licenseKey.substring(0, licenseKey.length > 8 ? 8 : licenseKey.length)}...');
            await _prefs.setString('activated_license_key', licenseKey);
            final result = await performHeartbeatCheck(apiClient);
            debugPrint('[LicenseSync] Heartbeat sonucu: $result');
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('Sync license from server failed: $e');
    }
    return false;
  }
}
