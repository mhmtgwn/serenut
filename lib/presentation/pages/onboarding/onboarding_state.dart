// lib/presentation/pages/onboarding/onboarding_state.dart (v2)
// Modüler OnboardingState — Her bölüm bağımsız model
// Compose pattern: OnboardingState bunları bir araya getirir

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const String _kOnboardingStateKey = 'serenut_onboarding_state_v2';
const String _kOnboardingStepKey = 'serenut_onboarding_step_v2';
const String _kOnboardingFlowKey = 'serenut_onboarding_flow_v2';

// ─────────────────────────────────────────────────────────────
// Alt modeller
// ─────────────────────────────────────────────────────────────

class BusinessInfo {
  final String businessName;
  final String ownerName;
  final String phone;
  final String email;
  final String taxNumber; // Vergi no — fişe yazılır (zorunlu)
  final String city;
  final String district;
  final String currency;
  final bool taxIncluded;
  final String businessType;
  final String? logoPath; // null = Serenut varsayılan logosu kullanılır

  const BusinessInfo({
    this.businessName = '',
    this.ownerName = '',
    this.phone = '',
    this.email = '',
    this.taxNumber = '',
    this.city = '',
    this.district = '',
    this.currency = '₺',
    this.taxIncluded = true,
    this.businessType = '',
    this.logoPath,
  });

  BusinessInfo copyWith({
    String? businessName,
    String? ownerName,
    String? phone,
    String? email,
    String? taxNumber,
    String? city,
    String? district,
    String? currency,
    bool? taxIncluded,
    String? businessType,
    String? logoPath,
    bool clearLogo = false,
  }) =>
      BusinessInfo(
        businessName: businessName ?? this.businessName,
        ownerName: ownerName ?? this.ownerName,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        taxNumber: taxNumber ?? this.taxNumber,
        city: city ?? this.city,
        district: district ?? this.district,
        currency: currency ?? this.currency,
        taxIncluded: taxIncluded ?? this.taxIncluded,
        businessType: businessType ?? this.businessType,
        logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
      );

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'ownerName': ownerName,
        'phone': phone,
        'email': email,
        'taxNumber': taxNumber,
        'city': city,
        'district': district,
        'currency': currency,
        'taxIncluded': taxIncluded,
        'businessType': businessType,
        'logoPath': logoPath,
      };

  factory BusinessInfo.fromJson(Map<String, dynamic> j) => BusinessInfo(
        businessName: j['businessName'] ?? '',
        ownerName: j['ownerName'] ?? '',
        phone: j['phone'] ?? '',
        email: j['email'] ?? '',
        taxNumber: j['taxNumber'] ?? '',
        city: j['city'] ?? '',
        district: j['district'] ?? '',
        currency: j['currency'] ?? '₺',
        taxIncluded: j['taxIncluded'] ?? true,
        businessType: j['businessType'] ?? '',
        logoPath: j['logoPath'] as String?,
      );

  /// Fişe yazılan tüm zorunlu alanlar dolu mu?
  bool get isValid =>
      businessName.trim().isNotEmpty &&
      ownerName.trim().isNotEmpty &&
      phone.trim().isNotEmpty &&
      taxNumber.trim().isNotEmpty &&
      city.isNotEmpty;

  /// logoPath null ise Serenut varsayılan logosu kullanılacak (app asset)
  bool get usesDefaultLogo => logoPath == null || logoPath!.isEmpty;
}

// ─────────────────────────────────────────────────────────────

class AdminInfo {
  final String adminFullName;
  final String username;
  // PIN ve şifre hafızada tutulur ama diske yazılmaz (güvenlik)
  final String pin;
  final String pinConfirm;
  final String password;
  final bool biometricEnabled; // UI-only placeholder

  const AdminInfo({
    this.adminFullName = '',
    this.username = '',
    this.pin = '',
    this.pinConfirm = '',
    this.password = '',
    this.biometricEnabled = false,
  });

  AdminInfo copyWith({
    String? adminFullName,
    String? username,
    String? pin,
    String? pinConfirm,
    String? password,
    bool? biometricEnabled,
  }) =>
      AdminInfo(
        adminFullName: adminFullName ?? this.adminFullName,
        username: username ?? this.username,
        pin: pin ?? this.pin,
        pinConfirm: pinConfirm ?? this.pinConfirm,
        password: password ?? this.password,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      );

  /// Diske sadece hassas olmayan alanları kaydet
  Map<String, dynamic> toJson() => {
        'adminFullName': adminFullName,
        'username': username,
        // pin, pinConfirm, password → YAZILMAZ
      };

  factory AdminInfo.fromJson(Map<String, dynamic> j) => AdminInfo(
        adminFullName: j['adminFullName'] ?? '',
        username: j['username'] ?? '',
      );

  bool get isValid {
    if (adminFullName.trim().isEmpty || username.trim().isEmpty) return false;
    if (pin.length != 4 && pin.length != 6) return false;
    if (pin != pinConfirm) return false;
    return true;
  }

  String? get pinError {
    if (pin.isEmpty) return 'PIN gerekli';
    if (pin.length != 4 && pin.length != 6) return 'PIN 4 veya 6 haneli olmalı';
    if (pin != pinConfirm) return 'PIN\'ler eşleşmiyor';
    return null;
  }
}

// ─────────────────────────────────────────────────────────────

class InitialSettings {
  final double defaultVat;
  final String defaultPrinter;
  final bool autoBackup;
  final bool smsNotifications;
  final bool stockTracking;
  final bool preventNegativeStock;
  final bool decimalSales;

  const InitialSettings({
    this.defaultVat = 20.0,
    this.defaultPrinter = '',
    this.autoBackup = true,
    this.smsNotifications = false,
    this.stockTracking = true,
    this.preventNegativeStock = false,
    this.decimalSales = false,
  });

  InitialSettings copyWith({
    double? defaultVat,
    String? defaultPrinter,
    bool? autoBackup,
    bool? smsNotifications,
    bool? stockTracking,
    bool? preventNegativeStock,
    bool? decimalSales,
  }) =>
      InitialSettings(
        defaultVat: defaultVat ?? this.defaultVat,
        defaultPrinter: defaultPrinter ?? this.defaultPrinter,
        autoBackup: autoBackup ?? this.autoBackup,
        smsNotifications: smsNotifications ?? this.smsNotifications,
        stockTracking: stockTracking ?? this.stockTracking,
        preventNegativeStock: preventNegativeStock ?? this.preventNegativeStock,
        decimalSales: decimalSales ?? this.decimalSales,
      );

  Map<String, dynamic> toJson() => {
        'defaultVat': defaultVat,
        'defaultPrinter': defaultPrinter,
        'autoBackup': autoBackup,
        'smsNotifications': smsNotifications,
        'stockTracking': stockTracking,
        'preventNegativeStock': preventNegativeStock,
        'decimalSales': decimalSales,
      };

  factory InitialSettings.fromJson(Map<String, dynamic> j) => InitialSettings(
        defaultVat: (j['defaultVat'] as num?)?.toDouble() ?? 20.0,
        defaultPrinter: j['defaultPrinter'] ?? '',
        autoBackup: j['autoBackup'] ?? true,
        smsNotifications: j['smsNotifications'] ?? false,
        stockTracking: j['stockTracking'] ?? true,
        preventNegativeStock: j['preventNegativeStock'] ?? false,
        decimalSales: j['decimalSales'] ?? false,
      );
}

// ─────────────────────────────────────────────────────────────

class LicenseInfo {
  final String licenseKey;
  final String? licenseType; // Professional, Kurumsal, Enterprise
  final DateTime? expiryDate;
  final DateTime? supportUntil;

  const LicenseInfo({
    this.licenseKey = '',
    this.licenseType,
    this.expiryDate,
    this.supportUntil,
  });

  LicenseInfo copyWith({
    String? licenseKey,
    String? licenseType,
    DateTime? expiryDate,
    DateTime? supportUntil,
  }) =>
      LicenseInfo(
        licenseKey: licenseKey ?? this.licenseKey,
        licenseType: licenseType ?? this.licenseType,
        expiryDate: expiryDate ?? this.expiryDate,
        supportUntil: supportUntil ?? this.supportUntil,
      );

  Map<String, dynamic> toJson() => {
        'licenseKey': licenseKey,
        'licenseType': licenseType,
      };

  factory LicenseInfo.fromJson(Map<String, dynamic> j) => LicenseInfo(
        licenseKey: j['licenseKey'] ?? '',
        licenseType: j['licenseType'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────
// Compose edilen ana model
// ─────────────────────────────────────────────────────────────

class OnboardingState {
  final BusinessInfo business;
  final AdminInfo admin;
  final InitialSettings settings;
  final LicenseInfo license;

  const OnboardingState({
    this.business = const BusinessInfo(),
    this.admin = const AdminInfo(),
    this.settings = const InitialSettings(),
    this.license = const LicenseInfo(),
  });

  OnboardingState copyWith({
    BusinessInfo? business,
    AdminInfo? admin,
    InitialSettings? settings,
    LicenseInfo? license,
  }) =>
      OnboardingState(
        business: business ?? this.business,
        admin: admin ?? this.admin,
        settings: settings ?? this.settings,
        license: license ?? this.license,
      );

  Map<String, dynamic> toJson() => {
        'business': business.toJson(),
        'admin': admin.toJson(),
        'settings': settings.toJson(),
        'license': license.toJson(),
      };

  factory OnboardingState.fromJson(Map<String, dynamic> j) => OnboardingState(
        business:
            BusinessInfo.fromJson(j['business'] as Map<String, dynamic>? ?? {}),
        admin: AdminInfo.fromJson(j['admin'] as Map<String, dynamic>? ?? {}),
        settings: InitialSettings.fromJson(
            j['settings'] as Map<String, dynamic>? ?? {}),
        license:
            LicenseInfo.fromJson(j['license'] as Map<String, dynamic>? ?? {}),
      );
}

// ─────────────────────────────────────────────────────────────
// Persistence
// ─────────────────────────────────────────────────────────────

class OnboardingPersistence {
  final SharedPreferences _prefs;
  OnboardingPersistence(this._prefs);

  int getSavedStep() => _prefs.getInt(_kOnboardingStepKey) ?? 0;
  String? getSavedFlow() => _prefs.getString(_kOnboardingFlowKey);

  Future<void> saveStep(int step) => _prefs.setInt(_kOnboardingStepKey, step);

  Future<void> saveFlow(String flow) =>
      _prefs.setString(_kOnboardingFlowKey, flow);

  Future<void> saveState(OnboardingState state) =>
      _prefs.setString(_kOnboardingStateKey, jsonEncode(state.toJson()));

  OnboardingState loadState() {
    final raw = _prefs.getString(_kOnboardingStateKey);
    if (raw == null) return const OnboardingState();
    try {
      return OnboardingState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const OnboardingState();
    }
  }

  bool isCompleted() =>
      _prefs.getBool('serenut_onboarding_completed_v2') ?? false;

  Future<void> markCompleted() =>
      _prefs.setBool('serenut_onboarding_completed_v2', true);

  Future<void> reset() async {
    await _prefs.remove(_kOnboardingStateKey);
    await _prefs.remove(_kOnboardingStepKey);
    await _prefs.remove(_kOnboardingFlowKey);
    await _prefs.remove('serenut_onboarding_completed_v2');
  }
}
