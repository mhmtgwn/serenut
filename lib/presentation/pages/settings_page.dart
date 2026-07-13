// lib/presentation/pages/settings_page.dart
// Phase 2.5 �€” Premium iOS-Style Settings & Configurations Screen
// Completely redesigned: 24 Jun 2026

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';
import 'dart:io';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/pages/settings/widgets/sms_settings_sheet.dart';
import 'package:serenutos/presentation/pages/settings/backup_manage_page.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/presentation/pages/data_transfer_page.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/presentation/pages/settings/sms_history_page.dart';
import 'package:serenutos/presentation/pages/settings/db_health_page.dart';
import 'package:serenutos/presentation/pages/settings/hardware_test_page.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/pages/admin/admin_page.dart';
import 'package:serenutos/presentation/pages/settings/print_queue_page.dart';
import 'package:serenutos/presentation/pages/license_page.dart' show LicenseManagementPage;
import 'package:serenutos/presentation/pages/admin/audit_center_page.dart';
import 'package:serenutos/presentation/pages/admin/recovery_center_page.dart';

part 'settings/widgets/printer_settings_sheet.dart';
part 'settings/widgets/backup_settings_card.dart';
part 'settings/widgets/user_management_dialog.dart';
part 'settings/widgets/system_config_section.dart';

// �”€�”€ Design Theme Sabitleri �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
const _kBgColor = Color(0xFFFAFAFC); // Sophisticated off-white / light slate grey
const _kCardBg = Colors.white;
const _kBorderColor = Color(0xFFF0F0F3); // Faint, subtle border
const _kTextPrimary = Color(0xFF1E293B); // Slate-900: softer and cleaner than raw black
const _kTextSecondary = Color(0xFF64748B); // Slate-500: elegant subtitle color
const _kGreen = Color(0xFF10B981); // Emerald Green
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
  String? _adminPinCode;
  bool _isUnlocked = false;
  bool _soundNotificationEnabled = false;

  List<String> _cities = [];
  Map<String, List<String>> _cityMap = {};
  bool _citiesLoaded = false;

  void _runGuardedAction(Permission permission, VoidCallback action, {String title = 'İşlem Doğrulaması', List<UserRole>? allowedRoles}) {
    final currentUser = ref.read(currentUserProvider);
    final isAllowedRole = allowedRoles == null || (currentUser != null && allowedRoles.contains(currentUser.role));

    if (!isAllowedRole) {
      _showAccessDeniedDialog(title);
      return;
    }

    if (_isUnlocked) {
      final hasAccess = currentUser != null && (
        currentUser.role == UserRole.sysadmin ||
        currentUser.role == UserRole.owner ||
        currentUser.hasPermission(permission.value)
      );
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
            child: const Text('Kapat', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
    _loadCities();
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
        final cityList = (tr as Map<String, dynamic>)['cities'] as List<dynamic>;
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
      debugPrint('Hata loading cities settings: $e');
    }
  }

  Future<void> _loadSettingsAndPin() async {
    // Settings are now stored in SQLite — settingsNotifierProvider loads them.
    // No SharedPreferences read needed; values are available from settings object in build.
  }

  Future<void> _loadAdminPin() async {
    await _loadSettingsAndPin();
  }

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
                const Icon(Icons.error_outline_rounded, size: 64, color: Colors.redAccent),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // �”€�”€ 1. Arama �‡ubu�Ÿu (Search Bar) �”€�”€
        _buildSearchBar(),
        const SizedBox(height: 16),

        // �”€�”€ 2. Kullanıcı Profil Kartı �”€�”€
        if (currentUser != null && _matchesQuery('Profil', 'Hesap', 'Yetki', currentUser.name))
          _buildProfileCard(currentUser),
        
        // ”€”€ 3. GruplanmıŸ Menüler ”€”€
        const SizedBox(height: 16),
        ..._buildGroupedSettings(settings, currentUser),

        // ── 4. Sürüm ve Çıkış Yap Grubu ──
        const SizedBox(height: 16),

        _buildSignOutGroup(),
        const SizedBox(height: 32),
      ],
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
            color: Colors.black.withOpacity(0.015),
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
          prefixIcon: const Icon(Icons.search_rounded, color: _kTextSecondary, size: 18),
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
                  child: const Icon(Icons.cancel_rounded, color: _kTextSecondary, size: 18),
                )
              : null,
        ),
      ),
    );
  }



  // �”€�”€ Profil Kartı �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  Widget _buildProfileCard(AuthUser user) {
    final initials = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U';
    final roleLabel = switch (user.role) {
      UserRole.owner => 'Kurucu/Sahip',
      UserRole.admin => 'Yönetici',
      UserRole.sysadmin => 'Sistem Yöneticisi',
      UserRole.manager => 'Müdür',
      UserRole.cashier => 'Kasiyer',
      UserRole.staff => 'Personel',
    };

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => _showProfileDetails(user),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [_kGreen, _kGreen.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ),
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextPrimary),
        ),
        subtitle: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                roleLabel,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _kGreen),
              ),
            ),
          ],
        ),
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Yetkilerim', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
            SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: _kTextSecondary, size: 20),
          ],
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
    if (_hasPermission(currentUser, Permission.settingsReceipt) && _matchesQuery('işletme', 'bilgiler', settings.businessName)) {
      group1.add(_buildCategoryRow(
        title: 'İşletme Bilgileri',
        subtitle: settings.businessName.isNotEmpty ? settings.businessName : 'Ayarlanmadı',
        icon: Icons.storefront_rounded,
        color: _kGreen,
        onTap: () => _runGuardedAction(Permission.settingsReceipt, () => _showBusinessInfoSheet(settings), title: 'İşletme Bilgileri'),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsDatabase) && (_matchesQuery('içeri', 'dışarı', 'aktar', 'katalog', 'yedek') || _matchesQuery('müşteri', 'rehber'))) {
      if (group1.isNotEmpty) group1.add(const _IOSDivider());
      group1.add(_buildCategoryRow(
        title: 'Veri İçeri / Dışarı Aktar',
        subtitle: 'Katalog, Yedek & Müşteriler',
        icon: Icons.import_export_rounded,
        color: _kTeal,
        onTap: () => _runGuardedAction(Permission.settingsDatabase, () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const DataTransferPage(),
            ),
          );
        }, title: 'Veri İçeri / Dışarı Aktar'),
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
        onTap: () => _runGuardedAction(Permission.settingsUsers, () => _showUserManagementPage(), title: 'Kullanıcı Yönetimi'),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsFinance) &&
        (_matchesQuery('bütünlük', 'audit', 'drift', 'ledger') || _matchesQuery('replay', 'cari', 'bakiye'))) {
      if (group1.isNotEmpty) group1.add(const _IOSDivider());
      group1.add(_buildCategoryRow(
        title: 'Cari Hesap Bütünlüğü & Replay',
        subtitle: 'Bakiye Sapmalarını Denetle ve Onar',
        icon: Icons.account_balance_rounded,
        color: _kPurple,
        onTap: () => _runGuardedAction(Permission.settingsFinance, () => _showLedgerReplayDialog(), title: 'Cari Hesap Bütünlüğü & Replay'),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsDatabase) &&
        (_matchesQuery('sağlık', 'health', 'veritabanı', 'db', 'check'))) {
      if (group1.isNotEmpty) group1.add(const _IOSDivider());
      group1.add(_buildCategoryRow(
        title: 'Veritabanı Sağlık Kontrolü',
        subtitle: 'Yetim Kayıtlar & Negatif Stok Denetimi',
        icon: Icons.health_and_safety_rounded,
        color: _kTeal,
        onTap: () => _runGuardedAction(Permission.settingsDatabase, () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const DbHealthPage(),
            ),
          );
        }, title: 'Veritabanı Sağlık Kontrolü'),
      ));
    }

    if (group1.isNotEmpty) {
      groups.add(_buildSectionHeader('İŞLETME AYARLARI'));
      groups.add(_buildRoundedCard(group1));
      groups.add(const SizedBox(height: 16));
    }

    // Grup 2: Donanım ve Bağlantılar
    final group2 = <Widget>[];
    if (_hasPermission(currentUser, Permission.settingsPrinter) && _matchesQuery('yazıcı', 'bağlantı', 'ip', settings.printerIp ?? '')) {
      group2.add(_buildCategoryRow(
        title: 'Fiş Yazıcı Ayarları',
        subtitle: settings.printerIp ?? 'Tanımlı Değil',
        icon: Icons.print_rounded,
        color: _kBlue,
        onTap: () => _showReceiptPrinterSheet(settings),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsPrinter) && _matchesQuery('etiket yazıcı', 'barkod yazıcı', 'ip')) {
      if (group2.isNotEmpty) group2.add(const _IOSDivider());
      group2.add(_buildCategoryRow(
        title: 'Etiket Yazıcı Ayarları',
        subtitle: 'İkinci Yazıcı',
        icon: Icons.label_rounded,
        color: _kTeal,
        onTap: () => _showLabelPrinterSheet(settings),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsFinance) && _matchesQuery('sms', 'bildirim', settings.smsProvider ?? '')) {
      if (group2.isNotEmpty) group2.add(const _IOSDivider());
      group2.add(_buildCategoryRow(
        title: 'SMS Servis Ayarları',
        subtitle: settings.smsEnabled ? (settings.smsProvider ?? 'Aktif') : 'Pasif',
        icon: Icons.sms_rounded,
        color: _kOrange,
        onTap: () => _showSmsSettingsSheet(settings),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsPrinter) && _matchesQuery('test', 'diagnostics', 'donanım', 'yazıcı', 'barkod', 'hardware')) {
      if (group2.isNotEmpty) group2.add(const _IOSDivider());
      group2.add(_buildCategoryRow(
        title: 'Donanım Diagnostics Testleri',
        subtitle: 'Yazıcı & Barkod Canlı Test Laboratuvarı',
        icon: Icons.settings_input_hdmi_rounded,
        color: _kGreen,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const HardwareTestPage(),
            ),
          );
        },
      ));
    }

    if (group2.isNotEmpty) {
      groups.add(_buildSectionHeader('DONANIM VE BAĞLANTILAR'));
      groups.add(_buildRoundedCard(group2));
      groups.add(const SizedBox(height: 16));
    }

    // Grup 4: Sistem
    final group4 = <Widget>[];
    if (currentUser != null && _matchesQuery('hata ayıklama', 'debug', 'sistem')) {
      group4.add(_buildSwitchRow(
        title: 'Hata Ayıklama Modu (Debug)',
        subtitle: 'Sistem loglarını ve detayları aktif eder',
        icon: Icons.bug_report_rounded,
        color: _kGray,
        value: settings.debugMode,
        onChanged: (val) => _updateSettingField(settings.copyWith(debugMode: val)),
      ));
    }

    if (currentUser != null && _matchesQuery('ses', 'bildirim', 'sound', 'sesli')) {
      if (group4.isNotEmpty) group4.add(const _IOSDivider());
      group4.add(_buildSwitchRow(
        title: 'Satışta Sesli Bildirim',
        subtitle: 'Satış başarıyla tamamlandığında sesli uyarı verir',
        icon: Icons.volume_up_rounded,
        color: _kBlue,
        value: settings.soundNotificationEnabled,
        onChanged: (val) async {
          await ref.read(settingsNotifierProvider.notifier)
              .updateSettings(settings.copyWith(soundNotificationEnabled: val));
        },
      ));
    }

    if (group4.isNotEmpty) {
      groups.add(_buildSectionHeader('SİSTEM VE GÜVENLİK'));
      groups.add(_buildRoundedCard(group4));
      groups.add(const SizedBox(height: 16));
    }

    // Grup 5: Ürün & Operasyon Merkezi (Phase 4-6)
    final group5 = <Widget>[];

    if (_hasPermission(currentUser, Permission.settingsLicense) && _matchesQuery('lisans', 'license', 'abonelik', 'tier', 'plan', 'cihaz')) {
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

    if (_hasPermission(currentUser, Permission.settingsPrinter) && _matchesQuery('yazıcı', 'kuyruk', 'fiş', 'print', 'queue', 'baskı')) {
      if (group5.isNotEmpty) group5.add(const _IOSDivider());
      group5.add(_buildCategoryRow(
        title: 'Yazıcı Kuyruğu',
        subtitle: 'Bekleyen fiş işleri ve yeniden deneme',
        icon: Icons.print_rounded,
        color: _kTeal,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PrintQueuePage()),
          );
        },
      ));
    }

    if (_hasPermission(currentUser, Permission.settingsAudit) && _matchesQuery('sms', 'mesaj', 'geçmiş', 'history', 'bildirim')) {
      if (group5.isNotEmpty) group5.add(const _IOSDivider());
      group5.add(_buildCategoryRow(
        title: 'SMS Geçmişi',
        subtitle: 'Gönderim durumu ve başarısız SMS kayıtları',
        icon: Icons.sms_rounded,
        color: _kOrange,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SmsHistoryPage()),
          );
        },
      ));
    }

    if (currentUser?.role == UserRole.sysadmin &&
        _matchesQuery('admin', 'kontrol', 'merkezi', 'observability', 'sistem', 'operasyon')) {
      if (group5.isNotEmpty) group5.add(const _IOSDivider());
      group5.add(_buildCategoryRow(
        title: 'Admin Kontrol Merkezi',
        subtitle: 'Sistem izleme, sync, incident ve daha fazlası',
        icon: Icons.admin_panel_settings_rounded,
        color: _kPurple,
        onTap: () => _runGuardedAction(Permission.settingsView, () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminPage()),
          );
        }, title: 'Admin Kontrol Merkezi', allowedRoles: [UserRole.sysadmin]),
      ));
    }

    if (group5.isNotEmpty) {
      groups.add(_buildSectionHeader('ÜRÜN & OPERASYON'));
      groups.add(_buildRoundedCard(group5));
      groups.add(const SizedBox(height: 16));
    }

    // Grup 6: Gelişmiş Yönetim (PIN Korumalı)
    final group6 = <Widget>[];
    if (_hasPermission(currentUser, Permission.settingsFinance) && _matchesQuery('finans', 'hub', 'cari', 'raporlar', 'excel', 'kdv')) {
      group6.add(_buildCategoryRow(
        title: 'Finans Hub & Raporlar',
        subtitle: 'Ciro raporu, KDV analizleri ve Excel çıktısı',
        icon: Icons.account_balance_wallet_rounded,
        color: _kGreen,
        onTap: () => _runGuardedAction(Permission.settingsFinance, () => context.push(AppRoutes.finance), title: 'Finans Hub & Raporlar'),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsAudit) && _matchesQuery('denetim', 'merkezi', 'audit', 'fiyat', 'log')) {
      if (group6.isNotEmpty) group6.add(const _IOSDivider());
      group6.add(_buildCategoryRow(
        title: 'Denetim Merkezi (Audit Center)',
        subtitle: 'Fiyat değişimleri, silmeler ve sistem logları',
        icon: Icons.assignment_turned_in_rounded,
        color: _kBlue,
        onTap: () => _runGuardedAction(Permission.settingsAudit, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditCenterPage()));
        }, title: 'Denetim Merkezi'),
      ));
    }
    if (_hasPermission(currentUser, Permission.settingsRecovery) && _matchesQuery('kurtarma', 'recovery', 'çöp', 'silinen')) {
      if (group6.isNotEmpty) group6.add(const _IOSDivider());
      group6.add(_buildCategoryRow(
        title: 'Veri Kurtarma Merkezi',
        subtitle: 'Silinen ürünleri, müşterileri ve satışları kurtarın',
        icon: Icons.restore_from_trash_rounded,
        color: _kPink,
        onTap: () => _runGuardedAction(Permission.settingsRecovery, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const RecoveryCenterPage()));
        }, title: 'Veri Kurtarma Merkezi'),
      ));
    }

    if (group6.isNotEmpty) {
      groups.add(_buildSectionHeader('GELİŞMİŞ YÖNETİM VE FİNANS'));
      groups.add(_buildRoundedCard(group6));
    }

    return groups;
  }

  // �”€�”€ Sürüm ve �‡ıkı�Ÿ Yap Grubu �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  // ”€”€ Sürüm ve ‡ıkıŸ Yap Grubu ”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€
  Widget _buildSignOutGroup() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.015),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleLogout,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.power_settings_new_rounded, color: _kPink, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Oturumu Kapat',
                      style: TextStyle(
                        color: _kPink,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Serenut POS v1.2.0 �€� Phase 2.5',
            style: TextStyle(color: _kTextSecondary, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3),
          ),
        ),
      ],
    );
  }

  // �”€�”€ Helper UI Metotları �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  bool _matchesQuery(String f1, [String f2 = '', String f3 = '', String f4 = '', String f5 = '', String f6 = '', String f7 = '', String f8 = '']) {
    if (_searchQuery.isEmpty) return true;
    return f1.toLowerCase().contains(_searchQuery) ||
        f2.toLowerCase().contains(_searchQuery) ||
        f3.toLowerCase().contains(_searchQuery) ||
        f4.toLowerCase().contains(_searchQuery) ||
        f5.toLowerCase().contains(_searchQuery) ||
        f6.toLowerCase().contains(_searchQuery) ||
        f7.toLowerCase().contains(_searchQuery) ||
        f8.toLowerCase().contains(_searchQuery);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _kTextSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildRoundedCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildCategoryRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _iOSIconBadge(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _kTextPrimary),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: _kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _iOSIconBadge(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _kTextPrimary),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _kGreen,
          ),
        ],
      ),
    );
  }

  Widget _iOSIconBadge({required IconData icon, required Color color}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Neutral light grey
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: _kTextSecondary, size: 18),
    );
  }

  // �”€�”€ Database State Güncelleme Metodu �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  Future<void> _updateSettingField(Settings updated) async {
    try {
      await ref.read(settingsNotifierProvider.notifier).updateSettings(updated);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ayarlar güncellenirken hata oluŸtu: $e'),
          backgroundColor: _kPink,
        ),
      );
    }
  }

  // ”€”€ Yetki / Profil Detay Modalı ”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€
  void _showProfileDetails(AuthUser user) {
    final roleLabel = switch (user.role) {
      UserRole.owner => 'Kurucu/Sahip',
      UserRole.admin => 'Yönetici',
      UserRole.sysadmin => 'Sistem Yöneticisi',
      UserRole.manager => 'Müdür',
      UserRole.cashier => 'Kasiyer',
      UserRole.staff => 'Personel',
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => FullScreenSettingsPage(
          title: 'Cari Hesap Bilgilerim',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Kullanıcı Adı', user.name),
              _buildInfoRow('Sistem Rolü', roleLabel.toUpperCase()),
              _buildInfoRow('Hesap OluŸturulma Tarihi', user.createdAt.toLocal().toString().substring(0, 16)),
              const SizedBox(height: 16),
              const Text(
                'Sahip OlduŸum Yetkiler',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kTextPrimary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (user.permissions as List<dynamic>).map((p) {
                  return Chip(
                    label: Text(p.toString(), style: const TextStyle(fontSize: 12)),
                    backgroundColor: _kGreen.withOpacity(0.1),
                    side: BorderSide.none,
                    labelStyle: const TextStyle(color: _kGreen, fontWeight: FontWeight.w600),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 14)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kTextPrimary)),
        ],
      ),
    );
  }

  // ── İşletme Bilgileri Düzenleme Ekranı ──
  void _showBusinessInfoSheet(Settings settings) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: settings.businessName);
    final phoneCtrl = TextEditingController(text: settings.businessPhone);
    final ownerCtrl = TextEditingController(text: settings.ownerName);
    final emailCtrl = TextEditingController(text: settings.businessEmail ?? '');
    final taxIdCtrl = TextEditingController(text: settings.businessTaxId ?? '');
    final addressCtrl = TextEditingController(text: settings.businessAddress);
    String? selectedLogoPath = settings.businessLogo;

    // Local dropdown values
    String? localCity = settings.businessCity.isEmpty ? null : settings.businessCity;
    String? localDistrict = settings.businessDistrict.isEmpty ? null : settings.businessDistrict;
    String? localType = settings.businessType.isEmpty ? null : settings.businessType;

    const businessTypes = [
      'Market', 'Kafe', 'Restoran', 'Kuruyemişçi', 'Pastane',
      'Büfe', 'Kasap', 'Manav', 'Eczane', 'Diğer',
    ];

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            final List<String> localDistricts = (localCity != null) ? (_cityMap[localCity] ?? []) : [];

            return FullScreenSettingsPage(
              title: 'İşletme Bilgileri',
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () async {
                          try {
                            final picker = ImagePicker();
                            final pickedFile = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 512,
                              maxHeight: 512,
                            );
                            if (pickedFile != null) {
                              setModalState(() {
                                selectedLogoPath = pickedFile.path;
                              });
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Logo seçilirken hata: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                        child: Center(
                          child: Stack(
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _kBorderColor, width: 2),
                                ),
                                child: selectedLogoPath != null &&
                                        selectedLogoPath!.isNotEmpty &&
                                        (kIsWeb || File(selectedLogoPath!).existsSync())
                                    ? ClipOval(
                                        child: kIsWeb
                                            ? Image.network(
                                                selectedLogoPath!,
                                                width: 86,
                                                height: 86,
                                                fit: BoxFit.cover,
                                              )
                                            : Image.file(
                                                File(selectedLogoPath!),
                                                width: 86,
                                                height: 86,
                                                fit: BoxFit.cover,
                                              ),
                                      )
                                    : const Icon(
                                        Icons.add_photo_alternate_rounded,
                                        color: _kGreen,
                                        size: 36,
                                      ),
                              ),
                              if (selectedLogoPath != null &&
                                  selectedLogoPath!.isNotEmpty &&
                                  (kIsWeb || File(selectedLogoPath!).existsSync()))
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setModalState(() {
                                        selectedLogoPath = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.delete_forever_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          selectedLogoPath != null ? 'Logo Seçildi (Değiştirmek için tıklayın)' : 'İşletme Logosu Seçin',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildFormTextField(
                        controller: nameCtrl,
                        label: 'İşletme Adı *',
                        icon: Icons.store_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: ownerCtrl,
                        label: 'Yetkili Adı Soyadı *',
                        icon: Icons.person_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: phoneCtrl,
                        label: 'Telefon Numarası *',
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: emailCtrl,
                        label: 'E-posta (İsteğe bağlı)',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: taxIdCtrl,
                        label: 'Vergi Dairesi / No *',
                        icon: Icons.badge_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan (fişe yazılır)' : null,
                      ),
                      const SizedBox(height: 12),
                      if (_citiesLoaded)
                        _buildFormDropdown<String>(
                          label: 'Şehir *',
                          icon: Icons.location_city_rounded,
                          value: localCity,
                          items: _cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (v) => setModalState(() {
                            localCity = v;
                            localDistrict = null;
                          }),
                          validator: (v) => v == null ? 'Gerekli alan' : null,
                        )
                      else
                        const Text('Şehir listesi yükleniyor...', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
                      const SizedBox(height: 12),
                      if (localDistricts.isNotEmpty) ...[
                        _buildFormDropdown<String>(
                          label: 'İlçe *',
                          icon: Icons.map_outlined,
                          value: localDistrict,
                          items: localDistricts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (v) => setModalState(() {
                            localDistrict = v;
                          }),
                          validator: (v) => v == null ? 'Gerekli alan' : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildFormDropdown<String>(
                        label: 'İşletme Türü',
                        icon: Icons.category_rounded,
                        value: localType,
                        items: businessTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) => setModalState(() {
                          localType = v;
                        }),
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: addressCtrl,
                        label: 'Detaylı İşletme Adresi',
                        icon: Icons.location_on_rounded,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 24),
                      _buildModalSaveButton(onTap: () async {
                        if (formKey.currentState!.validate()) {
                          final updated = settings.copyWith(
                            businessName: nameCtrl.text.trim(),
                            businessPhone: phoneCtrl.text.trim(),
                            businessAddress: addressCtrl.text.trim(),
                            businessTaxId: taxIdCtrl.text.trim().isEmpty ? null : taxIdCtrl.text.trim(),
                            businessLogo: selectedLogoPath,
                            ownerName: ownerCtrl.text.trim(),
                            businessEmail: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                            businessCity: localCity ?? '',
                            businessDistrict: localDistrict ?? '',
                            businessType: localType ?? '',
                          );
                          await _updateSettingField(updated);
                          if (context.mounted) Navigator.pop(context);
                        }
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // �”€�”€ Para Birimi & Muhasebe Düzenleme Ekranı �”€�”€
  void _showCurrencyVatSheet(Settings settings) {
    final formKey = GlobalKey<FormState>();
    final currencyCtrl = TextEditingController(text: settings.currency);
    
    // Parse vatCategories from JSON
    List<Map<String, dynamic>> vatList = [];
    try {
      if (settings.vatCategories.isNotEmpty) {
        final decoded = jsonDecode(settings.vatCategories);
        if (decoded is List) {
          vatList = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {
      // If it is stored as flat comma-separated values from the old bug,
      // convert them to structured format
      final oldVals = settings.vatCategories.split(',');
      for (final v in oldVals) {
        final rate = int.tryParse(v.trim());
        if (rate != null) {
          vatList.add({'name': 'Oran %$rate', 'rate': rate});
        }
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Consumer(
          builder: (routeCtx, ref, child) => StatefulBuilder(
            builder: (ctx, setModalState) {
              // Get category pool
              final poolCategories = ref.read(categoryPoolProvider);
            
            // Build the complete list of display categories by merging pool categories
            // with the local vatList keys
            final displayCategories = <String>{
              ...poolCategories,
              ...vatList.map((e) => e['name']?.toString() ?? ''),
            }.where((c) => c.isNotEmpty).toList()..sort();

            return FullScreenSettingsPage(
              title: 'Para Birimi & KDV',
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFormTextField(
                      controller: currencyCtrl,
                      label: 'Para Birimi *',
                      icon: Icons.monetization_on_rounded,
                      validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Kategoriye Göre KDV Oranları',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextPrimary),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: _kGreen),
                          label: const Text('Yeni Kategori Ekle', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () => _showAddVatCategoryDialog(context, displayCategories, (newVat) {
                            setModalState(() {
                              vatList.add(newVat);
                            });
                          }),
                        ),
                      ],
                    ),
                    const Divider(color: _kBorderColor),
                    const SizedBox(height: 8),
                    if (displayCategories.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Kategori bulunamadı.',
                            style: TextStyle(color: _kTextSecondary, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorderColor),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayCategories.length,
                          separatorBuilder: (c, i) => const Divider(height: 1, color: _kBorderColor),
                          itemBuilder: (c, idx) {
                            final catName = displayCategories[idx];
                            final mapped = vatList.firstWhere(
                              (e) => e['name']?.toString() == catName,
                              orElse: () => {},
                            );
                            final hasRate = mapped.isNotEmpty;
                            final rate = hasRate ? (mapped['rate'] as int) : 0;

                            return ListTile(
                              onTap: () {
                                _showEditVatDialog(context, catName, hasRate ? rate : null, (newRate) {
                                  setModalState(() {
                                    vatList.removeWhere((e) => e['name']?.toString() == catName);
                                    vatList.add({'name': catName, 'rate': newRate});
                                  });
                                });
                              },
                              leading: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: hasRate ? _kGreen.withOpacity(0.12) : _kGray.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.percent_rounded, 
                                  color: hasRate ? _kGreen : _kGray, 
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                catName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _kTextPrimary),
                              ),
                              subtitle: Text(
                                hasRate ? 'KDV Oranı: %$rate' : 'KDV Oranı: Tanımlanmamı�Ÿ (%0)',
                                style: TextStyle(
                                  color: hasRate ? _kGreen : _kTextSecondary, 
                                  fontSize: 13,
                                  fontWeight: hasRate ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasRate)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: _kPink),
                                      onPressed: () {
                                        setModalState(() {
                                          vatList.removeWhere((e) => e['name']?.toString() == catName);
                                        });
                                      },
                                    )
                                  else
                                    const Icon(
                                      Icons.chevron_right_rounded, 
                                      color: _kTextSecondary,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 32),
                    _buildModalSaveButton(onTap: () async {
                      if (formKey.currentState!.validate()) {
                        final updated = settings.copyWith(
                          currency: currencyCtrl.text.trim(),
                          vatCategories: jsonEncode(vatList),
                        );
                        await _updateSettingField(updated);
                        if (context.mounted) Navigator.pop(context);
                      }
                    }),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

  void _showAddVatCategoryDialog(
    BuildContext context,
    List<String> displayCategories,
    ValueChanged<Map<String, dynamic>> onAdd,
  ) {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Yeni Kategori Ekle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Kategori Adı',
                  hintText: 'örn: Gıda, Kozmetik',
                  prefixIcon: const Icon(Icons.category_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Kategori adı gerekli';
                  final name = v.trim().toLowerCase();
                  if (displayCategories.any((cat) => cat.toLowerCase() == name)) {
                    return 'Bu kategori zaten mevcut';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'KDV Oranı (%)',
                  hintText: 'örn: 1, 8, 18, 20',
                  prefixIcon: const Icon(Icons.percent_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) {
                  if (v!.trim().isEmpty) return 'KDV oranı gerekli';
                  final rate = int.tryParse(v);
                  if (rate == null || rate < 0 || rate > 100) return 'Geçersiz oran';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                onAdd({
                  'name': nameCtrl.text.trim(),
                  'rate': int.parse(rateCtrl.text.trim()),
                });
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ekle', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditVatDialog(
    BuildContext context,
    String categoryName,
    int? currentRate,
    ValueChanged<int> onSave,
  ) {
    final rateCtrl = TextEditingController(text: currentRate != null ? currentRate.toString() : '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$categoryName KDV Oranı', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: rateCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'KDV Oranı (%)',
              hintText: 'örn: 1, 8, 18, 20',
              prefixIcon: const Icon(Icons.percent_rounded, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            validator: (v) {
              if (v!.trim().isEmpty) return 'KDV oranı gerekli';
              final rate = int.tryParse(v);
              if (rate == null || rate < 0 || rate > 100) return 'Geçersiz oran';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                onSave(int.parse(rateCtrl.text.trim()));
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }



  // �”€�”€ Form Input Widget Yardımcıları �”€�”€
  Widget _buildFormTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      validator: validator,
      style: TextStyle(color: enabled ? _kTextPrimary : _kTextSecondary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20, color: _kTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGreen, width: 1.5),
        ),
        filled: true,
        fillColor: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFEFEFEF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildFormDropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? hintText,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      dropdownColor: Colors.white,
      style: const TextStyle(color: _kTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20, color: _kTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGreen, width: 1.5),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildModalSaveButton({required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text('Kaydet'),
      ),
    );
  }

  void _showLedgerReplayDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        bool isRunning = false;
        Map<String, double>? driftResults;
        final Map<String, String> customerNames = {};
        final Map<String, double> oldBalances = {};

        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.account_balance_rounded, color: _kPurple),
                  SizedBox(width: 8),
                  Text('Cari Hesap Bütünlüğü (Replay)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isRunning && driftResults == null) ...[
                        const Text(
                          'Bu işlem, sistemdeki tüm satışları, tahsilatları ve cari hareketleri (Ledger) baştan sona tarayarak '
                          'müşteri bakiyelerini yeniden hesaplar. Senkronizasyon veya beklenmedik elektrik kesintileri '
                          'kaynaklı olası bakiye sapmalarını tespit eder ve otomatik olarak onarır.',
                          style: TextStyle(fontSize: 13, color: _kTextSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: const Text('Denetim ve Onarımı Başlat'),
                          onPressed: () async {
                            setModalState(() {
                              isRunning = true;
                            });

                            try {
                              // Fetch customers before check to capture their names & old balances
                              final customerRepo = await ref.read(customerRepositoryProvider.future);
                              final allCustomers = await customerRepo.findAll();
                              for (final c in allCustomers) {
                                customerNames[c.id] = c.name;
                                oldBalances[c.id] = c.balance;
                              }

                              final dataIntegrity = await ref.read(dataIntegrityServiceProvider.future);
                              final results = await dataIntegrity.runGlobalDriftCheck();
                              
                              // Invalidate customers controller so the POS UI updates
                              ref.invalidate(customersControllerProvider);

                              setModalState(() {
                                isRunning = false;
                                driftResults = results;
                              });
                            } catch (e) {
                              setModalState(() {
                                isRunning = false;
                                driftResults = {};
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: _kPink),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ] else if (isRunning) ...[
                        const Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_kPurple)),
                              SizedBox(height: 16),
                              Text(
                                'İşlem hareketleri taranıyor, bakiyeler yeniden hesaplanıyor...',
                                style: TextStyle(fontSize: 13, color: _kTextSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ] else if (driftResults != null) ...[
                        if (driftResults!.isEmpty) ...[
                          const Center(
                            child: Column(
                              children: [
                                Icon(Icons.check_circle_rounded, color: _kGreen, size: 48),
                                SizedBox(height: 12),
                                Text(
                                  'Harika! Herhangi bir bakiye sapması veya veri tutarsızlığı bulunamadı. Tüm bakiyeleriniz güncel.',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const Center(
                            child: Icon(Icons.info_outline_rounded, color: _kOrange, size: 40),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Toplam ${driftResults!.length} müşterinin bakiyesinde sapma tespit edildi ve veritabanı otomatik olarak eşitlendi:',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              border: Border.all(color: _kBorderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final entry in driftResults!.entries)
                                  ListTile(
                                    title: Text(customerNames[entry.key] ?? 'Bilinmeyen Müşteri', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      'Eski: ${oldBalances[entry.key]?.toStringAsFixed(2)} ₺ | Yeni: ${entry.value.toStringAsFixed(2)} ₺',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: Text(
                                      'Fark: ${(entry.value - (oldBalances[entry.key] ?? 0.0)).toStringAsFixed(2)} ₺',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: (entry.value - (oldBalances[entry.key] ?? 0.0)) >= 0 ? _kGreen : _kPink,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kTextPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Kapat'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// �”€�”€ iOS Bölücü �‡izgisi �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
class _IOSDivider extends StatelessWidget {
  const _IOSDivider();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 56),
      height: 0.5,
      color: _kBorderColor,
    );
  }
}

// �”€�”€ iOS Modal Sheet Wrapper �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
class _iOSModalWrapper extends StatelessWidget {
  final String title;
  final Widget child;

  const _iOSModalWrapper({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final modalHeight = screenHeight - statusBarHeight - 16; // Takes full screen except status bar padding

    return Container(
      height: modalHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          // Title Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _kTextPrimary),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE5E5EA),
                    ),
                    child: const Icon(Icons.close_rounded, size: 16, color: _kTextSecondary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderColor),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

