// lib/domain/services/auth_service.dart
// PHASE 0 - Auth Contract (Day 1 — Security Hardened: 24 Jun 2026)
// SQLite + SharedPreferences implementation with PBKDF2-HMAC-SHA256 hashing

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/services/device_fingerprint_service.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, listEquals, kDebugMode;
import 'package:serenutos/domain/services/telemetry_service.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static const String _userStorageKey = 'auth_user_json';

  final IUserRepository _userRepository;
  final IHashService _hashService;
  final ApiClient? _apiClient;
  final DeviceManager _deviceManager;
  final LicenseService? _licenseService;
  final DeviceFingerprintService? _deviceFingerprintService;
  final Future<void> Function(Map<String, dynamic> company)?
      _cacheCompanyProfile;
  late SharedPreferences _prefs;
  AuthUser? _currentUser;

  AuthService({
    required IUserRepository userRepository,
    required IHashService hashService,
    required DeviceManager deviceManager,
    LicenseService? licenseService,
    DeviceFingerprintService? deviceFingerprintService,
    Future<void> Function(Map<String, dynamic> company)? cacheCompanyProfile,
    ApiClient? apiClient,
  })  : _userRepository = userRepository,
        _hashService = hashService,
        _deviceManager = deviceManager,
        _licenseService = licenseService,
        _deviceFingerprintService = deviceFingerprintService,
        _cacheCompanyProfile = cacheCompanyProfile,
        _apiClient = apiClient;

  /// Initialize service (call once on app startup)
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadStoredUser();

    // Restore JWT token to ApiClient if exists
    final savedToken = _prefs.getString('auth_jwt_token');
    _apiClient?.setJwtToken(savedToken);

    if (_apiClient != null) {
      _apiClient!.onTokenExpired = () async {
        return await refreshToken();
      };
      _apiClient!.onSessionExpired = () {
        triggerSessionExpired();
      };
    }
  }

  /// Load user from local storage if exists
  Future<void> _loadStoredUser() async {
    final userJson = _prefs.getString(_userStorageKey);
    if (userJson != null) {
      try {
        final user = AuthUser.fromJson(userJson);
        final lastVerifiedStr =
            _prefs.getString('serenut_last_authz_verified_at_${user.id}');
        if (lastVerifiedStr != null) {
          final lastVerified = DateTime.tryParse(lastVerifiedStr);
          final leaseDays = _prefs.getInt('offline_auth_lease_days') ?? 7;
          if (lastVerified != null &&
              DateTime.now().toUtc().difference(lastVerified).inDays >
                  leaseDays) {
            // A locally stored bearer token is not proof of a valid session:
            // it may be expired, malformed, or revoked on the server. Once the
            // offline lease expires, access must be re-established online.
            debugPrint(
                '[AuthService] ⚠️ Offline auth lease expired for user ${user.id}');
            await _clearStoredSession();
            return;
          }
        }
        _currentUser = user;
      } catch (e) {
        // Corrupt or outdated session — clear it
        await _prefs.remove(_userStorageKey);
        _currentUser = null;
      }
    }
  }

  Future<void> _clearStoredSession() async {
    await _prefs.remove(_userStorageKey);
    await _prefs.remove('auth_jwt_token');
    await _prefs.remove('auth_refresh_token');
    _apiClient?.setJwtToken(null);
    _currentUser = null;
  }

  /// Login with username (email or name) and password.
  Future<AuthUser> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw AuthException('Kullanıcı adı ve şifre boş olamaz.');
    }

    // Allow local admin fallback in debug mode for development testing
    if (kDebugMode &&
        username.trim().toLowerCase() == 'admin' &&
        password == 'admin') {
      final debugAdmin = AuthUser(
        id: 'debug_admin_id',
        companyId: 'debug_company_id',
        name: 'Admin',
        email: 'admin@serenut.com',
        role: UserRole.admin,
        permissions:
            Permission.forRole(UserRole.admin).map((p) => p.value).toList(),
        createdAt: DateTime.now(),
      );
      _currentUser = debugAdmin;
      await _prefs.setString(_userStorageKey, debugAdmin.toJson());
      await _prefs.setString(
        'serenut_last_authz_verified_at_${debugAdmin.id}',
        DateTime.now().toUtc().toIso8601String(),
      );
      return debugAdmin;
    }

    // Try online login first if API client is available
    if (_apiClient != null) {
      try {
        final response = await _apiClient!.post('/auth/login', {
          'email': username.trim().toLowerCase(),
          'password': password,
        });
        if (response.isSuccess) {
          final data = response.json;
          final token = data['access_token'] as String;
          final refreshToken = data['refresh_token'] as String;
          final userMap = data['user'] as Map<String, dynamic>;
          final companyId = userMap['company_id'] as String?;
          if (companyId == null || companyId.trim().isEmpty) {
            throw AuthException(
                'Sunucu oturumunda şirket kimliği eksik. Giriş reddedildi.');
          }

          await _prefs.setString('auth_jwt_token', token);
          await _prefs.setString('auth_refresh_token', refreshToken);
          _apiClient!.setJwtToken(token);

          // Synchronize trial starting date from server (AC 1.2)
          final trialManager = TrialManager(_prefs);
          final subscription = data['subscription'] as Map<String, dynamic>?;
          if (subscription != null) {
            await trialManager.cacheSubscription(subscription);
          }

          final roles = userMap['roles'] as List<dynamic>? ?? [];
          final roleStr = roles.isNotEmpty
              ? roles.first.toString()
              : (userMap['role'] as String? ?? 'cashier');
          final role = UserRole.values.firstWhere(
            (r) => r.name == roleStr.toLowerCase(),
            orElse: () => UserRole.cashier,
          );

          final user = AuthUser(
            id: userMap['id'] as String,
            companyId: companyId,
            name: userMap['name'] as String,
            email: userMap['email'] as String? ?? '',
            role: role,
            permissions: (userMap['permissions'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                getPermissionsForRole(role),
            createdAt:
                DateTime.tryParse(userMap['created_at'] as String? ?? '') ??
                    DateTime.now(),
          );

          await _bootstrapAuthenticatedSession();

          // Cache credentials in local sqlite for offline login
          try {
            final hash = _hashService.hashPassword(password);
            await _userRepository.insertUser(user, hash);
          } catch (_) {
            try {
              final hash = _hashService.hashPassword(password);
              await _userRepository.updateUserFields(user,
                  isActive: true, passwordHash: hash);
            } catch (e, st) {
              TelemetryService().logError(e, st,
                  context: 'AuthService', level: LogLevel.warning);
            }
          }

          _currentUser = user;
          await _prefs.setString(_userStorageKey, user.toJson());
          await _prefs.setString('serenut_last_authz_verified_at_${user.id}',
              DateTime.now().toUtc().toIso8601String());
          return user;
        }
      } catch (e) {
        if (e is AuthException) rethrow;
        if (e is ApiException) {
          if (e.statusCode == 400 ||
              e.statusCode == 401 ||
              e.statusCode == 403) {
            final body = e.responseBody;
            String message = 'Giriş başarısız.';
            if (body != null) {
              try {
                final decoded = jsonDecode(body) as Map<String, dynamic>;
                final nestedError = decoded['error'];
                message = decoded['message'] as String? ??
                    (nestedError is Map<String, dynamic>
                        ? nestedError['message'] as String?
                        : null) ??
                    message;
              } catch (e, st) {
                TelemetryService().logError(e, st,
                    context: 'AuthService', level: LogLevel.warning);
              }
            }
            throw AuthException(message);
          }
        }
        // Network timeout / DNS resolution issues — fall back to offline DB check
      }
    }

    // Not: kIsWeb hardcode kullanıcı bloğu kaldırıldı (güvenlik açığı).
    // Web'de de backend API çağrısı yapılır (satır 99-174 yukarıda).
    // Backend erişilemiyorsa local SQLite'a düşülür (aşağıdaki blok).
    // kIsWeb + local SQLite sorgusu: web'de SQLite çalışmaz, hata fırlatır
    // → throw AuthException ile sonuçlanır, bu doğru davranış.

    try {
      final user = await _userRepository.findByUsername(username.trim());
      if (user != null) {
        final hash = await _userRepository.getPasswordHash(user.id);
        if (hash != null) {
          final isValid = _hashService.verifyPassword(password, hash);

          if (isValid) {
            final lastVerifiedStr =
                _prefs.getString('serenut_last_authz_verified_at_${user.id}');
            if (lastVerifiedStr != null) {
              final lastVerified = DateTime.parse(lastVerifiedStr);
              if (DateTime.now().toUtc().difference(lastVerified).inDays >= 7) {
                throw AuthException(
                    'Güvenlik nedeniyle (offline policy) 7 günde bir çevrimiçi giriş yapmalısınız.');
              }
            } else {
              throw AuthException(
                  'Çevrimdışı giriş için önceden senkronizasyon gereklidir.');
            }

            await _onLoginSuccess(user);

            // Rehash on first login if legacy format detected
            if (_hashService.isLegacyHash(hash)) {
              await _rehashPassword(user.id, password);
            }

            // Update last_login timestamp
            await _userRepository.updateLastLogin(user.id);

            return user;
          }
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
    }

    throw AuthException('Kullanıcı adı veya şifre hatalı.');
  }

  Future<void> _bootstrapAuthenticatedSession() async {
    if (_apiClient == null) return;
    final body = <String, dynamic>{};
    if (!kIsWeb) {
      final deviceId =
          _licenseService?.getDeviceUuid() ?? _deviceManager.getDeviceId();
      body['device_hash'] = deviceId;
      body['device_name'] = 'POS Cihazı - $deviceId';
      final fingerprint = await _deviceFingerprintService?.getFingerprint();
      if (fingerprint != null) body['fingerprint'] = fingerprint.toJson();
    }
    try {
      final response = await _apiClient!.post('/auth/session-bootstrap', body);
      if (!response.isSuccess) {
        final payload = response.json;
        final error = payload is Map<String, dynamic> ? payload['error'] : null;
        final message = error is Map<String, dynamic>
            ? error['message']?.toString()
            : payload is Map<String, dynamic>
                ? payload['message']?.toString()
                : null;
        throw AuthException(
          message ?? 'Cihaz aktivasyonu veya lisans doğrulaması reddedildi.',
        );
      }
      final payload = response.json as Map<String, dynamic>;
      final subscription = payload['subscription'] as Map<String, dynamic>?;
      if (subscription != null) {
        await TrialManager(_prefs).cacheSubscription(subscription);
      }
      final company = payload['company'] as Map<String, dynamic>?;
      if (company != null && _cacheCompanyProfile != null) {
        await _cacheCompanyProfile!(company);
      }
      await _cacheLicenseActivation(
        payload['activation'],
        licenseKey: payload['license_key'] as String?,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      if (e is ApiException && (e.statusCode == 403 || e.statusCode == 409)) {
        String message =
            'Cihaz aktivasyonu veya lisans doğrulaması reddedildi.';
        final body = e.responseBody;
        if (body != null) {
          try {
            final payload = jsonDecode(body) as Map<String, dynamic>;
            final error = payload['error'];
            message = error is Map<String, dynamic>
                ? error['message']?.toString() ?? message
                : payload['message']?.toString() ??
                    error?.toString() ??
                    message;
          } catch (e, st) {
            TelemetryService().logError(e, st,
                context: 'AuthService', level: LogLevel.warning);
          }
        }
        throw AuthException(message);
      }
      // Login remains usable offline, but bootstrap state is explicitly retried
      // by the next authenticated session/sync recovery attempt.
      debugPrint('Session bootstrap failed: $e');
    }
  }

  Future<void> _cacheLicenseActivation(dynamic responseJson,
      {String? licenseKey}) async {
    final licenseService = _licenseService;
    if (licenseService == null || responseJson is! Map<String, dynamic>) return;
    if (!licenseService.hasVerificationKey) {
      throw AuthException(
        'Bu uygulama sürümü lisans doğrulama anahtarı olmadan derlenmiş. '
        'Güvenli güncelleme paketi yüklenmelidir.',
      );
    }
    final licenseInfo = responseJson['license_info'] as Map<String, dynamic>?;
    final signature = responseJson['signature'] as String?;
    if (licenseInfo == null || signature == null || signature.isEmpty) return;

    final tokenMap = <String, dynamic>{
      'merchant_id': licenseInfo['merchant_id'],
      if (licenseInfo.containsKey('activation_id'))
        'activation_id': licenseInfo['activation_id'],
      'device_id': licenseInfo['device_id'],
      'device_token_version': licenseInfo['device_token_version'] ?? 1,
      'expiry_date': licenseInfo['expiry_date'],
      'tier': licenseInfo['tier'],
      'features': licenseInfo['features'] ?? const <String>[],
      'token_version': licenseInfo['token_version'] ?? 1,
      'signature': signature,
    };
    final token = base64.encode(utf8.encode(jsonEncode(tokenMap)));
    final saved = await licenseService.saveLicenseToken(token, licenseKey);
    if (!saved) {
      throw AuthException('Sunucunun lisans imzası doğrulanamadı.');
    }
    if (_apiClient != null) {
      licenseService.startHeartbeat(_apiClient!);
    }
  }

  /// Rehash a legacy password with PBKDF2 after successful login.
  Future<void> _rehashPassword(String userId, String password) async {
    try {
      final newHash = _hashService.hashPassword(password);
      await _userRepository.updatePasswordHash(userId, newHash);
    } catch (_) {
      // Non-fatal — user can still log in with legacy hash next time
    }
  }

  // ════════════════════════════════════════════════════════════
  // SESSION
  // ════════════════════════════════════════════════════════════

  /// Get current logged-in user
  Future<AuthUser?> getCurrentUser() async {
    if (_currentUser == null) {
      await _loadStoredUser();
    }
    return _currentUser;
  }

  /// Get the current JWT token
  String? getJwtToken() {
    return _prefs.getString('auth_jwt_token');
  }

  /// Get the current Refresh token
  String? getRefreshToken() {
    return _prefs.getString('auth_refresh_token');
  }

  /// Refresh the access token using the saved refresh token
  Future<bool> refreshToken() async {
    final rToken = getRefreshToken();
    if (rToken == null || _apiClient == null) return false;

    try {
      final response = await _apiClient!.post('/auth/refresh', {
        'refresh_token': rToken,
      });

      if (response.isSuccess) {
        final data = response.json;
        final token = data['access_token'] as String;
        final newRToken = data['refresh_token'] as String;

        await _prefs.setString('auth_jwt_token', token);
        await _prefs.setString('auth_refresh_token', newRToken);
        _apiClient!.setJwtToken(token);
        return true;
      }
    } on ApiException catch (e) {
      // 400/401/403 are permanent authentication failures (stale token, session revoked, replay attack)
      if (e.statusCode == 400 || e.statusCode == 401 || e.statusCode == 403) {
        return false;
      }
      rethrow;
    } catch (_) {
      rethrow;
    }
    return false;
  }

  /// Logout — clears session
  Future<void> logout() async {
    final refreshToken = _prefs.getString('auth_refresh_token');
    final api = _apiClient;
    // Revoke local authority synchronously before any network wait. Session
    // expiry/deactivation callers must not retain access while logout is in
    // flight or the network is unavailable.
    _currentUser = null;
    api?.setJwtToken(null);
    if (api != null && refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await api.post('/auth/logout', {'refresh_token': refreshToken});
      } catch (_) {
        // Local logout must always complete. Server sessions are short-lived
        // and can still be revoked by the account security controls.
      }
    }
    await _clearStoredSession();
  }

  void Function()? onSessionExpiredCallback;
  void Function(AuthUser user)? onUserUpdatedCallback;

  void triggerSessionExpired() {
    logout();
    if (onSessionExpiredCallback != null) {
      onSessionExpiredCallback!();
    }
  }

  Future<void> checkCurrentUserSessionOnline() async {
    if (_currentUser == null ||
        _apiClient == null ||
        _apiClient!.jwtToken == null) {
      return;
    }
    try {
      final response = await _apiClient!.get('/users/me');
      if (response.statusCode == 200) {
        await _prefs.setString(
            'serenut_last_authz_verified_at_${_currentUser!.id}',
            DateTime.now().toUtc().toIso8601String());
        final userMap = response.json as Map<String, dynamic>;

        final isActive = userMap['is_active'] as bool? ?? true;
        if (!isActive) {
          triggerSessionExpired();
          return;
        }

        final roles = userMap['roles'] as List<dynamic>? ?? [];
        final roleStr = roles.isNotEmpty
            ? roles.first.toString()
            : (userMap['role'] as String? ?? 'cashier');
        final role = UserRole.values.firstWhere(
          (r) => r.name == roleStr.toLowerCase(),
          orElse: () => UserRole.cashier,
        );

        final serverPermissions = (userMap['permissions'] as List<dynamic>?)
                ?.map((permission) => permission.toString())
                .toList() ??
            getPermissionsForRole(role);
        if (role != _currentUser!.role ||
            !listEquals(serverPermissions, _currentUser!.permissions)) {
          final updatedUser = _currentUser!
              .copyWith(role: role, permissions: serverPermissions);
          _currentUser = updatedUser;
          await _prefs.setString(_userStorageKey, updatedUser.toJson());
          await _userRepository.updateUserFields(updatedUser);
          if (onUserUpdatedCallback != null) {
            onUserUpdatedCallback!(updatedUser);
          }
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        triggerSessionExpired();
      }
    } catch (_) {
      // Offline fallback: keep cached credentials
    }
  }

  /// Offline login başarısında çağrılır.
  /// NOT: JWT token burada üretilmez — offline session JWT'siz çalışır.
  /// Gerçek JWT yalnızca backend login başarısında (satır 108-157) set edilir.
  Future<void> _onLoginSuccess(AuthUser user) async {
    _currentUser = user;
    await _prefs.setString(_userStorageKey, user.toJson());
    // Offline durumda API çağrılarına gerek yok;
    // token null kalır → sync geldiğinde yeniden login istenir
  }

  /// Directly set the current authenticated user — used after setup (Web)
  Future<void> setCurrentUser(AuthUser user) async {
    _currentUser = user;
    await _prefs.setString(_userStorageKey, user.toJson());
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    return user != null;
  }

  /// Phase 5: Entitlement Recovery
  /// Forces a token refresh to fetch the latest subscription status, updates TrialManager,
  /// and potentially triggers sync resumption.
  Future<bool> refreshEntitlement() async {
    if (_apiClient == null) return false;
    final refreshToken = _prefs.getString('auth_refresh_token');
    if (refreshToken == null) return false;

    try {
      final response = await _apiClient!.post('/auth/refresh', {
        'refresh_token': refreshToken,
      });

      if (response.isSuccess) {
        final data = response.json;
        final newAccessToken = data['access_token'] as String?;
        final newRefreshToken = data['refresh_token'] as String?;
        final subscription = data['subscription'] as Map<String, dynamic>?;

        if (newAccessToken != null) {
          await _prefs.setString('auth_jwt_token', newAccessToken);
          _apiClient!.setJwtToken(newAccessToken);
        }
        if (newRefreshToken != null) {
          await _prefs.setString('auth_refresh_token', newRefreshToken);
        }

        if (subscription != null) {
          final trialManager = TrialManager(_prefs);
          await trialManager.cacheSubscription(subscription);
        }

        // Refresh follows the same server-owned entitlement and device
        // activation contract as login.  The retired module bootstrap endpoint
        // could silently return no license and leave a stale activation cached.
        await _bootstrapAuthenticatedSession();

        return true;
      }
    } catch (e) {
      debugPrint('Entitlement refresh failed: $e');
    }
    return false;
  }

  bool _isLeaseExpired(AuthUser user) {
    final lastVerifiedStr =
        _prefs.getString('serenut_last_authz_verified_at_${user.id}');
    if (lastVerifiedStr != null) {
      final lastVerified = DateTime.tryParse(lastVerifiedStr);
      final leaseDays = _prefs.getInt('offline_auth_lease_days') ?? 7;
      if (lastVerified != null &&
          DateTime.now().toUtc().difference(lastVerified).inDays > leaseDays) {
        return true;
      }
    }
    return false;
  }

  Future<bool> hasPermission(String permission) async {
    final user = await getCurrentUser();
    if (user == null) return false;

    // Only allow cashier permissions if lease expired
    if (_isLeaseExpired(user) &&
        !_getCashierPermissions().contains(permission)) {
      return false;
    }

    return user.hasPermission(permission);
  }

  /// Check if current user has all permissions
  Future<bool> hasAllPermissions(List<String> permissions) async {
    final user = await getCurrentUser();
    if (user == null) return false;

    if (_isLeaseExpired(user)) {
      final cashierPerms = _getCashierPermissions();
      if (!permissions.every((p) => cashierPerms.contains(p))) {
        return false;
      }
    }

    return user.hasAllPermissions(permissions);
  }

  /// Get all permission names for current user
  Future<List<String>> getAllPermissions() async {
    final user = await getCurrentUser();
    return user?.getAllPermissions() ?? [];
  }

  // ════════════════════════════════════════════════════════════
  // SQLite User Management CRUD
  // ════════════════════════════════════════════════════════════

  Future<List<AuthUser>> getUsers() async {
    if (kIsWeb) {
      return [
        AuthUser(
          id: 'user-admin',
          name: 'Admin',
          email: 'admin@serenut.com',
          role: UserRole.admin,
          permissions: getPermissionsForRole(UserRole.admin),
          createdAt: DateTime.now(),
        ),
        AuthUser(
          id: 'user-manager',
          name: 'Yönetici',
          email: 'yonetici@serenut.com',
          role: UserRole.manager,
          permissions: getPermissionsForRole(UserRole.manager),
          createdAt: DateTime.now(),
        ),
        AuthUser(
          id: 'user-cashier',
          name: 'Kasiyer',
          email: 'kasiyer@serenut.com',
          role: UserRole.cashier,
          permissions: getPermissionsForRole(UserRole.cashier),
          createdAt: DateTime.now(),
        ),
      ];
    }

    try {
      return await _userRepository.findAll();
    } catch (_) {
      return [];
    }
  }

  Future<void> createUser(AuthUser user, String password, {String? pin}) async {
    if (password.isEmpty) {
      throw AuthException('Şifre boş olamaz.');
    }
    String? pinHash;
    if (pin != null && pin.isNotEmpty) {
      pinHash = _hashService.hashPassword(pin);
    }
    await _userRepository.insertUser(
      user,
      _hashService.hashPassword(password),
      username: user.username,
      businessCode: user.businessCode,
      pinHash: pinHash,
    );
  }

  Future<void> updateUser(
    AuthUser user, {
    String? password,
    String? pin,
    bool? isActive,
  }) async {
    String? passwordHash;
    if (password != null && password.isNotEmpty) {
      passwordHash = _hashService.hashPassword(password);
    }
    String? pinHash;
    if (pin != null && pin.isNotEmpty) {
      pinHash = _hashService.hashPassword(pin);
    }
    await _userRepository.updateUserFields(
      user,
      isActive: isActive,
      passwordHash: passwordHash,
      username: user.username,
      businessCode: user.businessCode,
      pinHash: pinHash,
    );
  }

  Future<void> deleteUser(String id) async {
    await _userRepository.delete(id);
  }

  /// Change password for a specific user.
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.isEmpty || newPassword.length < 8) {
      throw AuthException('Yeni şifre en az 8 karakter olmalıdır.');
    }

    if (_currentUser?.id == userId &&
        _apiClient != null &&
        _apiClient!.jwtToken != null) {
      await _apiClient!.post('/auth/change-password', {
        'old_password': currentPassword,
        'new_password': newPassword,
      });
    }
    final hash = await _userRepository.getPasswordHash(userId);
    if (hash == null) throw AuthException('Kullanıcı bulunamadı.');

    if (!_hashService.verifyPassword(currentPassword, hash)) {
      throw AuthException('Mevcut şifre hatalı.');
    }

    await _userRepository.updatePasswordHash(
        userId, _hashService.hashPassword(newPassword));
  }

  static List<String> getPermissionsForRole(UserRole role) => switch (role) {
        UserRole.owner => _getAllPermissions(),
        UserRole.admin => _getAllPermissions(),
        // Sysadmin (Platform role) should not have tenant POS permissions by default
        UserRole.sysadmin => [
            'admin.settings',
            'admin.users',
            'reports.view',
            'settings.view'
          ],
        UserRole.manager => _getManagerPermissions(),
        UserRole.cashier => _getCashierPermissions(),
        UserRole.staff => _getCashierPermissions(),
      };

  // ════════════════════════════════════════════════════════════
  // Permission definitions (27 total)
  // ════════════════════════════════════════════════════════════

  static List<String> _getAllPermissions() => [
        'sales:view',
        'sales:create',
        'sales:edit',
        'sales:delete',
        'sales:print',
        'orders:view',
        'orders:create',
        'orders:edit',
        'orders:deliver',
        'customers:view',
        'customers:create',
        'customers:edit',
        'customers:delete',
        'payments:view',
        'payments:record',
        'payments:reverse',
        'inventory:view',
        'inventory:adjust',
        'inventory:transfer',
        'reports:view',
        'reports:financial',
        'reports:inventory',
        'admin:settings',
        'admin:users',
      ];

  static List<String> _getManagerPermissions() => [
        'sales:view',
        'sales:create',
        'sales:print',
        'orders:view',
        'orders:create',
        'orders:edit',
        'orders:deliver',
        'customers:view',
        'customers:create',
        'customers:edit',
        'payments:view',
        'payments:record',
        'inventory:view',
        'inventory:adjust',
        'inventory:transfer',
        'reports:view',
        'reports:financial',
        'reports:inventory',
      ];

  static List<String> _getCashierPermissions() => [
        'sales:view',
        'sales:create',
        'sales:print',
        'payments:record',
        'customers:view',
      ];
}
