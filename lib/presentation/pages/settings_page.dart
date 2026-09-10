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
import 'package:serenutos/presentation/pages/settings/hardware_test_page.dart';
import 'package:serenutos/presentation/pages/settings/about_page.dart';
import 'package:serenutos/presentation/pages/settings/account_page.dart';
import 'package:serenutos/presentation/pages/settings/catalog_settings_page.dart';
import 'package:serenutos/presentation/pages/settings/support_page.dart';
import 'package:serenutos/presentation/pages/admin/admin_page.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/providers/printing_providers.dart';

part 'settings/widgets/backup_settings_card.dart';
part 'settings/widgets/user_management_dialog.dart';
part 'settings/widgets/user_form_dialogs.dart';
part 'settings/widgets/system_config_section.dart';

// ─── Design Theme Sabitleri ───────────────────────────────────────────────────
part 'settings/widgets/settings_ui_helpers.dart';
part 'settings/widgets/settings_dialogs.dart';

const _kBgColor = POSColors.surface;
const _kCardBg = POSColors.card;
const _kBorderColor = POSColors.border;
const _kTextPrimary = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kGreen = POSColors.green;
const _kBlue = POSColors.blue; // Grafik ve bilgi vurgusu
const _kOrange = POSColors.amber;
const _kPink = POSColors.red;
const _kGray = POSColors.textDisabled;
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

  void _runGuardedAction(
    Permission permission,
    VoidCallback action, {
    String title = 'İşlem Doğrulaması',
    List<UserRole>? allowedRoles,
  }) {
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text(
              'Yetki Hatası',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Bu işlem için gerekli yetkiye sahip değilsiniz.\n(İşlem: $title)',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Kapat',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
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
      return Scaffold(
        backgroundColor: _kBgColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text('Ayarlar',
              style: TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 48, color: _kTextSecondary),
              const SizedBox(height: 16),
              const Text('Ayarları görüntülemek için lütfen giriş yapın.',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kTextPrimary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go(AppRoutes.login),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Giriş Yap'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
                const Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ayarlar yüklenemedi: $err',
                  style: const TextStyle(
                    fontSize: 16,
                    color: _kTextSecondary,
                  ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            children: [
              // �”€�”€ 1. Arama �‡ubu�Ÿu (Search Bar) �”€�”€
              _buildSearchBar(),
              const SizedBox(height: 16),

              // �”€�”€ 2. Kullanıcı Profil Kartı �”€�”€
              if (currentUser != null &&
                  _matchesQuery(
                    'Profil',
                    'Hesap',
                    'Yetki',
                    currentUser.name,
                  ))
                _buildRoundedCard([
                  _buildCategoryRow(
                    title: 'Hesabım',
                    subtitle: '${currentUser.name} · Oturum ve yetkiler',
                    icon: Icons.account_circle_rounded,
                    color: _kGreen,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountPage(),
                      ),
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
      title: 'Aygıt Yöneticisi',
      subtitle: 'Cihazları ekleyin, bağlantıları yönetin ve test edin',
      icon: Icons.settings_input_component_rounded,
      color: _kGreen,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const HardwareTestPage())),
    );
  }

  // �”€�”€ Arama �‡ubu�Ÿu �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  Widget _buildSearchBar() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: _kBorderColor),
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
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _kTextSecondary,
            size: 18,
          ),
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
                  child: const Icon(
                    Icons.cancel_rounded,
                    color: _kTextSecondary,
                    size: 18,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // ── Gruplanmış Ayarlar Menüsü ────────────────────────────────────────────────
  List<Widget> _buildGroupedSettings(Settings settings, AuthUser? currentUser) {
    final List<Widget> groups = [];

    // ── GRUP 1: İŞLETME & PERSONEL ──────────────────────────────────────────
    final groupBusiness = <Widget>[];
    if (_hasPermission(currentUser, Permission.settingsReceipt) ||
        _hasPermission(currentUser, Permission.settingsPrinter)) {
      if (_matchesQuery(
        'işletme',
        'bilgiler',
        'firma',
        settings.businessName,
      )) {
        groupBusiness.add(
          _buildCategoryRow(
            title: 'İşletme Bilgileri',
            subtitle: settings.businessName.isNotEmpty
                ? settings.businessName
                : 'Ayarlanmadı',
            icon: Icons.storefront_rounded,
            color: _kGreen,
            onTap: () => _runGuardedAction(
              Permission.settingsReceipt,
              () => _showBusinessInfoSheet(settings),
              title: 'İşletme Bilgileri',
            ),
          ),
        );
      }
    }
    if (_hasPermission(currentUser, Permission.inventoryAdjust) &&
        _matchesQuery('ürün', 'katalog', 'kategori', 'kdv', 'birim', 'marka')) {
      if (groupBusiness.isNotEmpty) groupBusiness.add(const _IOSDivider());
      groupBusiness.add(
        _buildCategoryRow(
          title: 'Ürün Kataloğu',
          subtitle: 'Kategori, varsayılan KDV ve birimleri düzenleyin',
          icon: Icons.category_rounded,
          color: _kGreen,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CatalogSettingsPage()),
          ),
        ),
      );
    }
    if (_hasPermission(currentUser, Permission.settingsUsers) &&
        _matchesQuery('kullanıcı', 'yetki', 'çalışan', 'personel', 'user')) {
      if (groupBusiness.isNotEmpty) groupBusiness.add(const _IOSDivider());
      groupBusiness.add(
        _buildCategoryRow(
          title: 'Kullanıcı Yönetimi',
          subtitle: 'Çalışanlar ve Yetkilendirme',
          icon: Icons.people_alt_rounded,
          color: _kOrange,
          onTap: () => _runGuardedAction(
            Permission.settingsUsers,
            () => _showUserManagementPage(),
            title: 'Kullanıcı Yönetimi',
          ),
        ),
      );
    }
    if (groupBusiness.isNotEmpty) {
      groups.add(_buildSectionHeader('İŞLETME & PERSONEL'));
      groups.add(_buildRoundedCard(groupBusiness));
      groups.add(const SizedBox(height: 16));
    }

    // ── GRUP 2: CİHAZLAR & BİLDİRİMLER ──────────────────────────────────────
    final groupDevices = <Widget>[];
    if (_hasPermission(currentUser, Permission.settingsPrinter) &&
        _matchesQuery(
          'donanım',
          'terazi',
          'pos',
          'yazıcı',
          'hardware',
          'test',
          'diagnostics',
          'barkod',
        )) {
      groupDevices.add(_buildHardwareCenterCard(settings));
    }
    if (_hasPermission(currentUser, Permission.settingsPrinter) &&
        _matchesQuery('fiş', 'tasarım', 'yazıcı', 'logo', 'çekmece')) {
      if (groupDevices.isNotEmpty) groupDevices.add(const _IOSDivider());
      groupDevices.add(
        _buildCategoryRow(
          title: 'Fiş Tasarımı',
          subtitle: 'Kağıt, logo, QR kod ve kasa çekmecesi ayarları',
          icon: Icons.receipt_long_rounded,
          color: _kBlue,
          onTap: () => _runGuardedAction(
            Permission.settingsPrinter,
            () => _showReceiptSettings(settings),
            title: 'Fiş Tasarımı',
          ),
        ),
      );
    }
    if (_hasPermission(currentUser, Permission.settingsFinance) &&
        _matchesQuery('sms', 'bildirim', settings.smsProvider ?? '')) {
      if (groupDevices.isNotEmpty) groupDevices.add(const _IOSDivider());
      groupDevices.add(
        _buildCategoryRow(
          title: 'Bildirim Ayarları',
          subtitle: 'SMS ve WhatsApp kanalları, otomatik mesaj şablonları',
          icon: Icons.tune_rounded,
          color: _kOrange,
          onTap: () => _showSmsSettingsSheet(settings),
        ),
      );
    }
    if (currentUser != null &&
        _matchesQuery('ses', 'bildirim', 'sound', 'sesli')) {
      if (groupDevices.isNotEmpty) groupDevices.add(const _IOSDivider());
      groupDevices.add(
        _buildSwitchRow(
          title: 'Satışta Sesli Bildirim',
          subtitle: 'Satış başarıyla tamamlandığında sesli uyarı verir',
          icon: Icons.volume_up_rounded,
          color: _kBlue,
          value: settings.soundNotificationEnabled,
          onChanged: (val) async {
            await ref.read(settingsNotifierProvider.notifier).updateSettings(
                  settings.copyWith(soundNotificationEnabled: val),
                );
          },
        ),
      );
    }
    if (groupDevices.isNotEmpty) {
      groups.add(_buildSectionHeader('CİHAZLAR & BİLDİRİMLER'));
      groups.add(_buildRoundedCard(groupDevices));
      groups.add(const SizedBox(height: 16));
    }

    // ── GRUP 3: VERİ VE YEDEKLEME ───────────────────────────────────────────
    final groupData = <Widget>[];
    if (_hasPermission(currentUser, Permission.settingsDatabase) &&
        (_matchesQuery('içeri', 'dışarı', 'aktar', 'katalog', 'yedek', 'müşteri', 'rehber'))) {
      groupData.add(
        _buildCategoryRow(
          title: 'Veri Aktarımı',
          subtitle: 'Ürün ve müşteri verilerini Excel ile içeri veya dışarı aktarın',
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
        ),
      );
      groupData.add(const _IOSDivider());
      groupData.add(
        _buildCategoryRow(
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
        ),
      );
    }
    if (groupData.isNotEmpty) {
      groups.add(_buildSectionHeader('VERİ & YEDEKLEME'));
      groups.add(_buildRoundedCard(groupData));
      groups.add(const SizedBox(height: 16));
    }

    // ── GRUP 4: UYGULAMA VE DESTEK ──────────────────────────────────────────
    final groupApp = <Widget>[];
    if (_matchesQuery('destek', 'yardım', 'iletişim', 'talep')) {
      groupApp.add(
        _buildCategoryRow(
          title: 'Destek Talebi Gönder',
          subtitle: 'Sorularınız veya talepleriniz için destek ekibine ulaşın',
          icon: Icons.support_agent_rounded,
          color: _kBlue,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SupportPage()),
          ),
        ),
      );
    }
    if (_matchesQuery(
      'uygulama',
      'hakkında',
      'güncelleme',
      'sürüm',
      'versiyon',
      'lisans',
    )) {
      if (groupApp.isNotEmpty) groupApp.add(const _IOSDivider());
      groupApp.add(
        _buildCategoryRow(
          title: 'Uygulama Hakkında',
          subtitle: 'Sürüm bilgisi ve güncelleme denetimi',
          icon: Icons.info_outline_rounded,
          color: _kGreen,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AboutPage()),
          ),
        ),
      );
    }
    // Geliştirici / Sistem Yöneticisi Paneli (Yalnızca sysadmin rolü görür)
    if (currentUser?.role == UserRole.sysadmin &&
        _matchesQuery('yönetici', 'admin', 'panel', 'kontrol', 'gözlem', 'sistem')) {
      if (groupApp.isNotEmpty) groupApp.add(const _IOSDivider());
      groupApp.add(
        _buildCategoryRow(
          title: 'Geliştirici / Sistem Paneli',
          subtitle: 'Sistem logları, tanı ve bakım araçları',
          icon: Icons.admin_panel_settings_rounded,
          color: _kGray,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AdminPage(),
            ),
          ),
        ),
      );
    }
    if (groupApp.isNotEmpty) {
      groups.add(_buildSectionHeader('UYGULAMA VE DESTEK'));
      groups.add(_buildRoundedCard(groupApp));
      groups.add(const SizedBox(height: 16));
    }

    return groups;
  }

  // ignore: unused_element
}
