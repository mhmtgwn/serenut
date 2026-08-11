// lib/presentation/pages/data_transfer_page.dart
// Dedicated Data Import & Export Console (Sub-Page of Settings)
// Redesigned: 25 Jun 2026

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/providers/dataset_import_provider.dart';
import 'package:serenutos/infrastructure/services/file_saver_helper.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/pages/settings/backup_manage_page.dart';
import 'package:serenutos/infrastructure/services/data_reset_service.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/permission.dart' as app_permission;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:excel/excel.dart' hide Border;
import 'package:go_router/go_router.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart'
    show InMemoryDb;
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/config/theme.dart';
part 'data_transfer/import_progress_dialog.dart';
part 'data_transfer/export_progress_dialog.dart';
part 'data_transfer/contact_import_page.dart';

// ── Design Theme Sabitleri ───────────────────────────────────────────────────
const _kCardBg = POSColors.card;
const _kBorderColor = POSColors.border;
const _kTextPrimary = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kGreen = POSColors.green;
const _kBlue = POSColors.blue;
const _kOrange = POSColors.amber;
const _kPink = POSColors.red;
const _kTeal = POSColors.greenDark;
const _kTealLight = POSColors.greenMid;

enum DataManagementMode { transfer, backup, dangerous }

extension DataManagementModePresentation on DataManagementMode {
  String get title => switch (this) {
        DataManagementMode.transfer => 'Veri Aktarımı',
        DataManagementMode.backup => 'Yedekleme ve Geri Yükleme',
        DataManagementMode.dangerous => 'Tehlikeli İşlemler',
      };

  String get description => switch (this) {
        DataManagementMode.transfer =>
          'Ürün ve müşteri verilerini kontrollü biçimde içeri veya dışarı aktarın.',
        DataManagementMode.backup =>
          'İşletme verilerinizin yedeğini oluşturun ve gerektiğinde geri yükleyin.',
        DataManagementMode.dangerous =>
          'Geri alınamayan veri temizleme işlemlerini yalnızca zorunlu olduğunda kullanın.',
      };

  IconData get icon => switch (this) {
        DataManagementMode.transfer => Icons.swap_horizontal_circle_outlined,
        DataManagementMode.backup => Icons.backup_rounded,
        DataManagementMode.dangerous => Icons.warning_amber_rounded,
      };

  Color get color => switch (this) {
        DataManagementMode.transfer => _kTeal,
        DataManagementMode.backup => _kOrange,
        DataManagementMode.dangerous => _kPink,
      };
}

class DataTransferPage extends ConsumerStatefulWidget {
  final DataManagementMode mode;

  const DataTransferPage({
    super.key,
    this.mode = DataManagementMode.transfer,
  });

  @override
  ConsumerState<DataTransferPage> createState() => _DataTransferPageState();
}

class _DataTransferPageState extends ConsumerState<DataTransferPage> {
  @override
  Widget build(BuildContext context) {
    return FullScreenSettingsPage(
      title: widget.mode.title,
      useScrollView: false,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // Giriş Banner'ı
          _buildIntroBanner(),
          const SizedBox(height: 20),

          if (widget.mode == DataManagementMode.transfer) ...[
            // GRUP 1: İÇE AKTARMA SEÇENEKLERİ
            _buildSectionHeader('İÇE AKTARMA SEÇENEKLERİ'),
            _buildRoundedCard([
              _buildTransferRow(
                title: 'Ürün Kataloğu İçe Aktar (.zip / .xlsx)',
                subtitle:
                    'Excel tablosu veya ZIP arşivi üzerinden ürünleri yükler.',
                icon: Icons.upload_file_rounded,
                color: _kGreen,
                onTap: () => _handleImportZipCatalog(context),
              ),
              const _Divider(),
              _buildTransferRow(
                title: 'Rehberden Müşteri Aktar',
                subtitle: 'Cihazdaki kişileri müşteri olarak içeri yükler.',
                icon: Icons.contact_phone_rounded,
                color: _kBlue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (context) => const ContactImportPage(),
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 20),

            // GRUP 2: DIŞARI AKTARMA & YEDEKLEME SEÇENEKLERİ
            _buildSectionHeader('DIŞARI AKTARMA & YEDEKLEME'),
            _buildRoundedCard([
              _buildTransferRow(
                title: 'Ürün Kataloğu Dışarı Aktar (.zip)',
                subtitle:
                    'Mevcut kataloğu Excel tablosu ve görsellerle yedekler.',
                icon: Icons.download_rounded,
                color: _kTealLight,
                onTap: () => _handleExportZipCatalog(context),
              ),
            ]),
          ],
          if (widget.mode == DataManagementMode.backup) ...[
            _buildSectionHeader('YEDEKLEME VE GERİ YÜKLEME'),
            _buildRoundedCard([
              _buildTransferRow(
                title: 'Yedekleme ve Geri Yükleme',
                subtitle: 'Uygulama veritabanını yedekler veya geri yükler.',
                icon: Icons.backup_rounded,
                color: _kOrange,
                onTap: () => _showBackupRestoreSheet(),
              ),
            ]),
            const SizedBox(height: 20),
          ],

          if (widget.mode == DataManagementMode.dangerous) ...[
            _buildSectionHeader('GERİ ALINAMAYAN İŞLEMLER'),
            _buildRoundedCard([
              _buildTransferRow(
                title: 'Tüm Ürün Kataloğunu Temizle',
                subtitle:
                    'Kayıtlı olan tüm örnek veya yüklü ürün verilerini siler.',
                icon: Icons.delete_sweep_rounded,
                color: _kPink,
                onTap: () => _clearAllProducts(),
              ),
              const _Divider(),
              _buildTransferRow(
                title: 'Tüm Verileri Sıfırla (Fabrika Ayarları)',
                subtitle:
                    'Veritabanını temizler, ayarları ve tüm verileri sıfırlar.',
                icon: Icons.phonelink_erase_rounded,
                color: _kPink,
                onTap: () => _resetAllUserData(),
              ),
            ]),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildIntroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        children: [
          Icon(widget.mode.icon, color: widget.mode.color, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mode.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _kTextPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.mode.description,
                  style: const TextStyle(
                      fontSize: 12, color: _kTextSecondary, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _kTextSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildRoundedCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildTransferRow({
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _kTextPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(color: _kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: _kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── 1. ÜRÜN KATALOĞU İÇE AKTAR ──────────────────────────────────────────────
  void _handleImportZipCatalog(BuildContext context) {
    context.push(AppRoutes.catalogImportWizard);
  }

  Future<void> _resetAllUserData() async {
    // Show reset type selector dialog
    final resetType = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Veri Sıfırlama',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Hangi tür sıfırlama yapmak istiyorsunuz?',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 16),
            // Option 1: Standard Reset
            InkWell(
              onTap: () => Navigator.pop(ctx, 'standard'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cleaning_services_rounded,
                        color: Color(0xFFF59E0B), size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Standart Sıfırlama',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          SizedBox(height: 2),
                          Text(
                            'Tüm cihazlardaki satışlar, siparişler, müşteriler ve ürünler silinir. Ayarlar ve yedekler korunur. İnternet bağlantısı gerekir.',
                            style: TextStyle(
                                color: Color(0xFF64748B), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Option 2: Full Wipe
            InkWell(
              onTap: () => Navigator.pop(ctx, 'full'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.red.shade50,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.delete_forever_rounded,
                        color: Color(0xFFDC2626), size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tam Temizlik',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFFDC2626))),
                          SizedBox(height: 2),
                          Text(
                            'Tüm veriler, ayarlar, PIN kodu ve yedekler silinir. Cihaz fabrika ayarlarına döner.',
                            style: TextStyle(
                                color: Color(0xFF991B1B), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('İptal', style: TextStyle(color: Color(0xFF64748B))),
          ),
        ],
      ),
    );

    if (resetType == null || !mounted) return;

    // Second confirmation dialog
    final title = resetType == 'standard'
        ? 'Standart Sıfırlama Onayı'
        : 'Tam Temizlik Onayı';
    final desc = resetType == 'standard'
        ? 'Bu firmaya ait satışlar, siparişler, müşteriler ve ürünler sunucudan ve tüm cihazlardan kalıcı olarak silinecek. Ayarlarınız ve yedekleriniz korunacak. İnternet bağlantısı zorunludur.\n\nBu işlem geri alınamaz!'
        : 'Tüm veriler, ayarlar, PIN kodu, kullanıcılar ve yedekler silinecek. Cihaz ilk kurulum ekranına dönecek.\n\nBu işlem KESİNLİKLE geri alınamaz!';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(desc,
            style: const TextStyle(fontSize: 14, color: Color(0xFF475569))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: resetType == 'full'
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
                resetType == 'standard' ? 'Standart Sıfırla' : 'Her Şeyi Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    requirePermissionAccess(context,
        permission: app_permission.Permission.settingsDatabase,
        title: 'Sıfırlama Yetkisi',
        onGranted: (approvedByUserId, approvedByUserName) async {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_kPink),
          ),
        ),
      );

      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logSystemAction(
          'database_reset',
          'Sıfırlama Tipi: $resetType',
          approvedByUserId: approvedByUserId,
          approvedByUserName: approvedByUserName,
        );
        if (resetType == 'standard') {
          // Sunucu reset bariyerini oluşturur; yerel SQLite temizliği aynı
          // revizyona atomik olarak taşınır. Eski çevrimdışı mutation'lar bu
          // bariyerin ardından verileri yeniden oluşturamaz.
          await ref.read(syncProvider.notifier).resetOperationalData();
          if (kIsWeb) {
            // Web: Sadece operasyonel tabloları sıfırla
            InMemoryDb.products.clear();
            InMemoryDb.sales.clear();
            InMemoryDb.transactions.clear();
            InMemoryDb.orders.clear();
            final defaultCust =
                InMemoryDb.customers.where((c) => c.id.isEmpty).toList();
            InMemoryDb.customers.clear();
            InMemoryDb.customers.addAll(defaultCust);
          }

          // Riverpod cache'lerini temizle — TÜM temizlenen tablolar ve türetilmiş controller'lar kapsanıyor
          // Repository provider'ları (SQLite gateway cache'ini sıfırlar)
          ref.invalidate(productRepositoryProvider);
          ref.invalidate(saleRepositoryProvider);
          ref.invalidate(financialTransactionRepositoryProvider);
          ref.invalidate(orderRepositoryProvider);
          ref.invalidate(customerRepositoryProvider);
          // UI controller provider'ları (Riverpod AsyncNotifier state'leri sıfırlar)
          ref.invalidate(productsControllerProvider);
          ref.invalidate(salesControllerProvider);
          ref.invalidate(ordersControllerProvider);
          ref.invalidate(customersControllerProvider);
          // Dashboard ve derived provider'lar (satış/sipariş toplamlarını gösterir)
          ref.invalidate(dashboardProvider);
          ref.read(productCategoriesStateProvider.notifier).state = [];

          if (mounted) Navigator.pop(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Operasyonel veriler başarıyla sıfırlandı. Ayarlar korundu.'),
                backgroundColor: Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          // ── Tam Temizlik: Her şey silinir ──
          await ref.read(syncProvider.notifier).prepareForFactoryReset();
          // Sunucu oturumunu yenileme belirteci hâlâ mevcutken kapat. Aksi
          // halde SharedPreferences temizliği sunucu oturumunu açık bırakır.
          await ref.read(authNotifierProvider.notifier).logout();
          ref.invalidate(syncProvider);
          if (!kIsWeb) {
            final dbManager = DatabaseManager();
            await dbManager.resetDatabase();
            final backupService = ref.read(backupServiceProvider);
            await backupService.clearAllBackups();
            await DataResetService.clearProductImages();
          } else {
            InMemoryDb.reset();
          }

          // Clear ALL SharedPreferences (including settings, PIN)
          final prefs = ref.read(sharedPreferencesProvider);
          final keys = List<String>.from(prefs.getKeys());
          for (final key in keys) {
            await prefs.remove(key);
          }

          // Cache sıfırlama
          ref.invalidate(currentUserProvider);
          ref.invalidate(settingsProvider);
          ref.invalidate(productRepositoryProvider);
          ref.invalidate(productsControllerProvider);
          ref.read(productCategoriesStateProvider.notifier).state = [];

          if (mounted) Navigator.pop(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Tüm veriler silindi. Sistem ilk kuruluma hazırlanıyor...'),
                backgroundColor: Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          await Future.delayed(const Duration(seconds: 1));
          if (mounted) context.go(AppRoutes.activation);
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sıfırlama hatası: $e'),
              backgroundColor: _kPink,
            ),
          );
        }
      }
    });
  }

  Future<void> _clearAllProducts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kataloğu Temizle'),
        content: const Text(
            'Katalogdaki tüm ürünler silinecektir. Bu işlem geri alınamaz. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final productRepo = await ref.read(productRepositoryProvider.future);
        final all = await productRepo.findAll();
        for (final p in all) {
          await productRepo.delete(p.id);
        }
        ref.invalidate(productRepositoryProvider);
        ref.invalidate(productsControllerProvider);
        ref.read(productCategoriesStateProvider.notifier).state = [];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Katalogdaki tüm ürünler başarıyla temizlendi.'),
              backgroundColor: _kPink,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Temizleme hatası: $e'),
              backgroundColor: _kPink,
            ),
          );
        }
      }
    }
  }

  // ── 2. ÜRÜN KATALOĞU DIŞARI AKTAR ───────────────────────────────────────────
  Future<void> _handleExportZipCatalog(BuildContext context) async {
    _startExportProgressDialog(context);
  }

  void _startExportProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const ExportProgressDialog(),
    );
  }

  // ── 3. REHBERDEN MÜŞTERİ AKTAR ─────────────────────────────────────────────
  // Refactored to external ContactImportPage widget below for better state and permission lifecycle.

  // ── 4. YEDEKLEME VE GERİ YÜKLEME ───────────────────────────────────────────
  void _showBackupRestoreSheet() {
    requireAdminAccess(
      context,
      title: 'Yedekleme Yönetimi',
      onGranted: (approvedByUserId, approvedByUserName) {
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => const BackupManagePage(),
          ),
        );
      },
    );
  }
}

// ── İçiçe Bölücü Çizgisi ──
class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 54),
      height: 0.5,
      color: _kBorderColor,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── ASENKRON İŞLEM DİYALOGLARI (UI DONDURMAYAN VE ÇAKIŞMAYAN YAPILAR) ─────────
// ══════════════════════════════════════════════════════════════════════════════
