// lib/presentation/pages/settings_page.dart
// Phase 2.5 - Premium iOS-Style Settings & Configurations Screen
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

// ─── Design Theme Sabitleri ───────────────────────────────────────────────────
part 'settings/widgets/settings_ui_helpers.dart';
part 'settings/widgets/settings_dialogs.dart';
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

}
