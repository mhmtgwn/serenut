// lib/presentation/pages/settings_page.dart
// Phase 2.5 - Premium iOS-Style Settings & Configurations Screen
// Completely redesigned: 24 Jun 2026

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'dart:io';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/pages/settings/widgets/sms_settings_sheet.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/pages/data_transfer_page.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/presentation/pages/operations_center_page.dart';
import 'package:serenutos/presentation/pages/settings/hardware_test_page.dart';
import 'package:serenutos/presentation/pages/settings/about_page.dart';
import 'package:serenutos/presentation/pages/settings/account_page.dart';
import 'package:serenutos/presentation/pages/license_page.dart'
    show LicenseManagementPage;

part 'settings/widgets/backup_settings_card.dart';
part 'settings/widgets/user_management_dialog.dart';
part 'settings/widgets/system_config_section.dart';

// ─── Design Theme Sabitleri ───────────────────────────────────────────────────
part 'settings/widgets/settings_ui_helpers.dart';
part 'settings/widgets/settings_dialogs.dart';

const _kBgColor = Color(0xFFF8FAFC);
const _kCardBg = Colors.white;
const _kBorderColor = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen = Color(0xFF16A34A);
const _kBlue = Color(0xFF3B82F6); // Modern Blue
const _kOrange = Color(0xFFF59E0B); // Modern Amber
const _kPurple = Color(0xFF8B5CF6); // Modern Violet
const _kPink = Color(0xFFEF4444); // Modern Rose/Red
const _kGray = Color(0xFF94A3B8); // Cool Slate Grey
const _kTeal = Color(0xFF0D9488); // Deep Teal

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isUnlocked = false;

  List<String> _cities = [];
  Map<String, List<String>> _cityMap = {};
  bool _citiesLoaded = false;

  void _runGuardedAction(Permission permission, VoidCallback action,
      {String title = 'İşlem Doğrulaması', List<UserRole>? allowedRoles}) {
    final currentUser = ref.read(currentUserProvider);
    final isAllowedRole = allowedRoles == null ||
        (currentUser != null && allowedRoles.contains(currentUser.role));

    if (!isAllowedRole) {
      _showAccessDeniedDialog(title);
      return;
    }

    if (_isUnlocked) {
      final hasAccess = currentUser != null &&
          (currentUser.role == UserRole.sysadmin ||
              currentUser.role == UserRole.owner ||
              currentUser.hasPermission(permission.value));
      if (hasAccess) {
        action();
      } else {
        _showAccessDeniedDialog(title);
      }
    } else {
      requirePermissionAccess(
        context,
        permission: permission,
        title: title,
        onGranted: (_, __) {
          if (mounted) {
            setState(() {
              _isUnlocked = true;
            });
            action();
          }
        },
      );
    }
  }

  void _showAccessDeniedDialog(String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Yetki Hatası', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bu işlem için gerekli yetkiye sahip değilsiniz.\n(İşlem: $title)',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void updateState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettingsAndPin();
  }

  Future<void> _loadCities() async {
    try {
      final raw = await rootBundle.loadString('assets/data/cities.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final countries = json['countries'] as List<dynamic>;
      final tr = countries.firstWhere(
        (c) => (c as Map<String, dynamic>)['code'] == 'TR',
        orElse: () => null,
      );
      if (tr != null) {
        final cityList =
            (tr as Map<String, dynamic>)['cities'] as List<dynamic>;
        final Map<String, List<String>> map = {};
        for (final c in cityList) {
          final name = (c as Map<String, dynamic>)['name'] as String;
          final districts = (c['districts'] as List<dynamic>).cast<String>();
          map[name] = districts;
        }
        if (mounted) {
          setState(() {
            _cityMap = map;
            _cities = map.keys.toList()..sort();
            _citiesLoaded = true;
          });
        }
      }
    } catch (e) {
      // Ignored in tests to prevent debugPrint from crashing the test runner if it finishes early
    }
  }

  Future<void> _loadSettingsAndPin() async {
    // Settings are now stored in SQLite — settingsNotifierProvider loads them.
    // No SharedPreferences read needed; values are available from settings object in build.
  }

  Future<void> _loadAdminPin() async {
    await _loadSettingsAndPin();
  }

  // ignore: unused_element
  Future<void> _handleLogout() async {
    await ref.read(authNotifierProvider.notifier).logout();
    if (mounted) {
      context.go(AppRoutes.login);
    }
  }

  bool _hasPermission(AuthUser? user, Permission permission) {
    if (user == null) return false;
    if (user.role == UserRole.sysadmin || user.role == UserRole.owner) {
      return true;
    }
    return user.hasPermission(permission.value);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsyncValue = ref.watch(settingsNotifierProvider);
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Ayarlar',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: false,
      ),
      body: settingsAsyncValue.when(
        data: (settings) => _buildBody(settings, currentUser),
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
          ),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  'Ayarlar yüklenemedi: $err',
                  style: const TextStyle(fontSize: 16, color: _kTextSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Settings settings, AuthUser? currentUser) {
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SizedBox(
          width: constraints.maxWidth > 760 ? 760 : constraints.maxWidth,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // �”€�”€ 1. Arama �‡ubu�Ÿu (Search Bar) �”€�”€
              _buildSearchBar(),
              const SizedBox(height: 16),

              // �”€�”€ 2. Kullanıcı Profil Kartı �”€�”€
              if (currentUser != null &&
                  _matchesQuery('Profil', 'Hesap', 'Yetki', currentUser.name))
                _buildRoundedCard([
                  _buildCategoryRow(
                    title: 'Hesabım',
                    subtitle: '${currentUser.name} · Oturum ve yetkiler',
                    icon: Icons.account_circle_rounded,
                    color: _kGreen,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountPage()),
                    ),
                  ),
                ]),

              // ”€”€ 3. GruplanmıŸ Menüler ”€”€
              const SizedBox(height: 16),
              ..._buildGroupedSettings(settings, currentUser),

              // ── 4. Sürüm ve Çıkış Yap Grubu ──
              const SizedBox(height: 16),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHardwareCenterCard(Settings settings) {
    return _buildCategoryRow(
      title: 'Cihazlar ve Donanım',
      subtitle: 'Cihazları ekleyin, bağlantıları yönetin ve test edin',
      icon: Icons.settings_input_component_rounded,
      color: _kGreen,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HardwareTestPage()),
      ),
    );
  }

  // �”€�”€ Arama �‡ubu�Ÿu �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  Widget _buildSearchBar() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          setState(() {
            _searchQuery = val.toLowerCase().trim();
          });
        },
        style: const TextStyle(fontSize: 14, color: _kTextPrimary),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded,
              color: _kTextSecondary, size: 18),
          hintText: 'Ayarlarda ara...',
          hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const Icon(Icons.cancel_rounded,
                      color: _kTextSecondary, size: 18),
                )
              : null,
        ),
      ),
    );
  }

  // ── License Subtitle Helper ───────────────────────────────────────────────
  String _buildLicenseSubtitleFromRef() {
    try {
      final licenseService = ref.read(licenseServiceProvider);
      final status = licenseService.checkLicenseStatus();
      final info = licenseService.getLicenseInfo();
      final days = licenseService.getRemainingDays();
      if (status == 'valid' && info != null) {
        return '${info.tier.name} — $days gün kaldı';
      } else if (status == 'expired') {
        return '❌ Süresi Doldu';
      } else if (status == 'tampered') {
        return '🚨 Saat manipülasyonu';
      }
      return '⚠️ Lisans bulunamadı';
    } catch (_) {
      return 'Lisans durumu bilinmiyor';
    }
  }

  // ── Gruplanmış Ayarlar Menüsü ────────────────────────────────────────────────
  List<Widget> _buildGroupedSettings(Settings settings, AuthUser? currentUser) {
    final List<Widget> groups = [];

    // Grup 1: İşletme Ayarları
    final group1 = <Widget>[];
    final groupData = <Widget>[];
    if (_hasPermission(currentUser, Permission.settingsReceipt) &&
        _matchesQuery('işletme', 'bilgiler', settings.businessName)) {
      group1.add(_buildCategoryRow(
        title: 'İşletme Bilgileri',
        subtitle: settings.businessName.isNotEmpty
            ? settings.businessName
            : 'Ayarlanmadı',
        icon: Icons.storefront_rounded,
        color: _kGreen,
        onTap: () => _runGuardedAction(
            Permission.settingsReceipt, () => _showBusinessInfoSheet(settings),
            title: 'İşletme Bilgileri'),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsDatabase) &&
        (_matchesQuery('içeri', 'dışarı', 'aktar', 'katalog', 'yedek') ||
            _matchesQuery('müşteri', 'rehber'))) {
      groupData.add(_buildCategoryRow(
        title: 'Veri Aktarımı',
        subtitle: 'Ürün ve müşteri verilerini içeri veya dışarı aktarın',
        icon: Icons.import_export_rounded,
        color: _kTeal,
        onTap: () => _runGuardedAction(Permission.settingsDatabase, () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const DataTransferPage(
                mode: DataManagementMode.transfer,
              ),
            ),
          );
        }, title: 'Veri Aktarımı'),
      ));
      groupData.add(const _IOSDivider());
      groupData.add(_buildCategoryRow(
        title: 'Yedekleme ve Geri Yükleme',
        subtitle: 'İşletme verilerinin güvenli yedeklerini yönetin',
        icon: Icons.backup_rounded,
        color: _kOrange,
        onTap: () => _runGuardedAction(Permission.settingsDatabase, () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const DataTransferPage(
                mode: DataManagementMode.backup,
              ),
            ),
          );
        }, title: 'Yedekleme ve Geri Yükleme'),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsUsers) &&
        _matchesQuery('kullanıcı', 'yetki', 'çalışan', 'personel', 'user')) {
      if (group1.isNotEmpty) group1.add(const _IOSDivider());
      group1.add(_buildCategoryRow(
        title: 'Kullanıcı Yönetimi',
        subtitle: 'Çalışanlar ve Yetkilendirme',
        icon: Icons.people_alt_rounded,
        color: _kOrange,
        onTap: () => _runGuardedAction(
            Permission.settingsUsers, () => _showUserManagementPage(),
            title: 'Kullanıcı Yönetimi'),
      ));
    }
    if (group1.isNotEmpty) {
      groups.add(_buildSectionHeader('İŞLETME'));
      groups.add(_buildRoundedCard(group1));
      groups.add(const SizedBox(height: 16));
    }
    if (groupData.isNotEmpty) {
      groups.add(_buildSectionHeader('VERİ YÖNETİMİ'));
      groups.add(_buildRoundedCard(groupData));
      groups.add(const SizedBox(height: 16));
    }

    // Grup 2: Donanım ve Bağlantılar
    final group2 = <Widget>[];
    if (_hasPermission(currentUser, Permission.settingsPrinter) &&
        _matchesQuery('donanım', 'terazi', 'pos', 'yazıcı', 'hardware', 'test',
            'diagnostics', 'barkod')) {
      group2.add(_buildHardwareCenterCard(settings));
    }
    if (_hasPermission(currentUser, Permission.settingsFinance) &&
        _matchesQuery('sms', 'bildirim', settings.smsProvider ?? '')) {
      if (group2.isNotEmpty) group2.add(const _IOSDivider());
      group2.add(_buildCategoryRow(
        title: 'SMS ve Bildirimler',
        subtitle: settings.smsEnabled ? 'Yerel SIM etkin' : 'Pasif',
        icon: Icons.sms_rounded,
        color: _kOrange,
        onTap: () => _showSmsSettingsSheet(settings),
      ));
    }
    if (group2.isNotEmpty) {
      groups.add(_buildSectionHeader('CİHAZLAR VE İLETİŞİM'));
      groups.add(_buildRoundedCard(group2));
      groups.add(const SizedBox(height: 16));
    }

    // Grup 4: Sistem
    final group4 = <Widget>[];
    final groupDeveloper = <Widget>[];
    if (currentUser?.role == UserRole.sysadmin &&
        _matchesQuery('hata ayıklama', 'debug', 'sistem')) {
      groupDeveloper.add(_buildSwitchRow(
        title: 'Hata Ayıklama Modu (Debug)',
        subtitle: 'Sistem loglarını ve detayları aktif eder',
        icon: Icons.bug_report_rounded,
        color: _kGray,
        value: settings.debugMode,
        onChanged: (val) =>
            _updateSettingField(settings.copyWith(debugMode: val)),
      ));
    }

    if (currentUser != null &&
        _matchesQuery('ses', 'bildirim', 'sound', 'sesli')) {
      if (group4.isNotEmpty) group4.add(const _IOSDivider());
      group4.add(_buildSwitchRow(
        title: 'Satışta Sesli Bildirim',
        subtitle: 'Satış başarıyla tamamlandığında sesli uyarı verir',
        icon: Icons.volume_up_rounded,
        color: _kBlue,
        value: settings.soundNotificationEnabled,
        onChanged: (val) async {
          await ref
              .read(settingsNotifierProvider.notifier)
              .updateSettings(settings.copyWith(soundNotificationEnabled: val));
        },
      ));
    }

    if (group4.isNotEmpty) {
      groups.add(_buildSectionHeader('UYGULAMA TERCİHLERİ'));
      groups.add(_buildRoundedCard(group4));
      groups.add(const SizedBox(height: 16));
    }
    if (groupDeveloper.isNotEmpty) {
      groups.add(_buildSectionHeader('GELİŞTİRİCİ VE DESTEK'));
      groups.add(_buildRoundedCard(groupDeveloper));
      groups.add(const SizedBox(height: 16));
    }

    // Grup 5: Ürün & Operasyon Merkezi (Phase 4-6)
    final group5 = <Widget>[];

    if (currentUser != null &&
        (currentUser.role == UserRole.owner ||
            currentUser.role == UserRole.admin ||
            currentUser.role == UserRole.sysadmin) &&
        _matchesQuery('admin', 'yönetim', 'denetim', 'kurtarma', 'telemetri')) {
      group5.add(_buildCategoryRow(
        title: 'Admin Kontrol Merkezi',
        subtitle: 'Sistem sağlığı, denetim ve veri kurtarma',
        icon: Icons.admin_panel_settings_rounded,
        color: _kPurple,
        onTap: () => context.push(AppRoutes.admin),
      ));
    }

    if (_hasPermission(currentUser, Permission.settingsLicense) &&
        _matchesQuery(
            'lisans', 'license', 'abonelik', 'tier', 'plan', 'cihaz')) {
      if (group5.isNotEmpty) group5.add(const _IOSDivider());
      group5.add(_buildCategoryRow(
        title: 'Lisans Yönetimi',
        subtitle: _buildLicenseSubtitleFromRef(),
        icon: Icons.verified_rounded,
        color: _kGreen,
        onTap: () => _runGuardedAction(Permission.settingsLicense, () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LicenseManagementPage()),
          );
        }, title: 'Lisans Yönetimi'),
      ));
    }

    if (_hasPermission(currentUser, Permission.settingsRecovery) &&
        (currentUser?.role == UserRole.owner ||
            currentUser?.role == UserRole.sysadmin) &&
        _matchesQuery('tehlikeli', 'sıfırla', 'temizle', 'fabrika')) {
      if (group5.isNotEmpty) group5.add(const _IOSDivider());
      group5.add(_buildCategoryRow(
        title: 'Tehlikeli İşlemler',
        subtitle: 'Veri temizleme ve fabrika ayarları',
        icon: Icons.warning_amber_rounded,
        color: _kPink,
        onTap: () => _runGuardedAction(Permission.settingsRecovery, () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const DataTransferPage(
                mode: DataManagementMode.dangerous,
              ),
            ),
          );
        },
            title: 'Tehlikeli İşlemler',
            allowedRoles: [UserRole.owner, UserRole.sysadmin]),
      ));
    }

    if ((_hasPermission(currentUser, Permission.settingsPrinter) ||
            _hasPermission(currentUser, Permission.settingsFinance)) &&
        _matchesQuery(
            'operasyon', 'yazıcı', 'kuyruk', 'sms', 'geçmiş', 'başarısız')) {
      if (group5.isNotEmpty) group5.add(const _IOSDivider());
      group5.add(_buildCategoryRow(
        title: 'Operasyon Merkezi',
        subtitle: 'Yazıcı kuyruğu ve SMS gönderim durumları',
        icon: Icons.monitor_heart_outlined,
        color: _kTeal,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OperationsCenterPage()),
          );
        },
      ));
    }

    if (group5.isNotEmpty) {
      groups.add(_buildSectionHeader('YÖNETİM & İLETİŞİM'));
      groups.add(_buildRoundedCard(group5));
      groups.add(const SizedBox(height: 16));
    }

    if (_matchesQuery(
        'uygulama', 'hakkında', 'güncelleme', 'sürüm', 'versiyon')) {
      groups.add(_buildSectionHeader('UYGULAMA'));
      groups.add(_buildRoundedCard([
        _buildCategoryRow(
          title: 'Uygulama Hakkında',
          subtitle: 'Sürüm bilgisi ve güncelleme denetimi',
          icon: Icons.info_outline_rounded,
          color: _kBlue,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AboutPage()),
          ),
        ),
      ]));
      groups.add(const SizedBox(height: 16));
    }

    return groups;
  }

  // ignore: unused_element
}
