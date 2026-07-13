// lib/presentation/pages/data_transfer_page.dart
// Dedicated Data Import & Export Console (Sub-Page of Settings)
// Redesigned: 25 Jun 2026

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/providers/dataset_import_provider.dart';
import 'package:serenutos/infrastructure/services/file_saver_helper.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/pages/settings/backup_manage_page.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
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
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';

// ── Design Theme Sabitleri ───────────────────────────────────────────────────
const _kBgColor = Color(0xFFF2F2F7);
const _kCardBg = Colors.white;
const _kBorderColor = Color(0xFFE5E5EA);
const _kTextPrimary = Color(0xFF000000);
const _kTextSecondary = Color(0xFF8E8E93);
const _kGreen = Color(0xFF34C759);
const _kBlue = Color(0xFF007AFF);
const _kOrange = Color(0xFFFF9500);
const _kPurple = Color(0xFFAF52DE);
const _kPink = Color(0xFFFF2D55);
const _kTeal = Color(0xFF5856D6);
const _kTealLight = Color(0xFF00C7BE);

class DataTransferPage extends ConsumerStatefulWidget {
  const DataTransferPage({super.key});

  @override
  ConsumerState<DataTransferPage> createState() => _DataTransferPageState();
}

class _DataTransferPageState extends ConsumerState<DataTransferPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Veri İçeri / Dışarı Aktar',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kGreen),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          children: [
            // Giriş Banner'ı
            _buildIntroBanner(),
            const SizedBox(height: 20),

            // GRUP 1: İÇE AKTARMA SEÇENEKLERİ
            _buildSectionHeader('İÇE AKTARMA SEÇENEKLERİ'),
            _buildRoundedCard([
              _buildTransferRow(
                title: 'Ürün Kataloğu İçe Aktar (.zip / .xlsx)',
                subtitle: 'Excel tablosu veya ZIP arşivi üzerinden ürünleri yükler.',
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
                subtitle: 'Mevcut kataloğu Excel tablosu ve görsellerle yedekler.',
                icon: Icons.download_rounded,
                color: _kTealLight,
                onTap: () => _handleExportZipCatalog(context),
              ),
              const _Divider(),
              _buildTransferRow(
                title: 'Yedekleme ve Geri Yükleme',
                subtitle: 'Uygulama veritabanını yedekler veya geri yükler.',
                icon: Icons.backup_rounded,
                color: _kOrange,
                onTap: () => _showBackupRestoreSheet(),
              ),
            ]),
            const SizedBox(height: 20),

            // GRUP 3: TEMİZLİK VE SIFIRLAMA
            _buildSectionHeader('TEMİZLİK VE SIFIRLAMA'),
            _buildRoundedCard([
              _buildTransferRow(
                title: 'Tüm Ürün Kataloğunu Temizle',
                subtitle: 'Kayıtlı olan tüm örnek veya yüklü ürün verilerini siler.',
                icon: Icons.delete_sweep_rounded,
                color: _kPink,
                onTap: () => _clearAllProducts(),
              ),
              const _Divider(),
              _buildTransferRow(
                title: 'Tüm Verileri Sıfırla (Fabrika Ayarları)',
                subtitle: 'Veritabanını temizler, ayarları ve tüm verileri sıfırlar.',
                icon: Icons.phonelink_erase_rounded,
                color: _kPink,
                onTap: () => _resetAllUserData(),
              ),
            ]),
            const SizedBox(height: 32),
          ],
        ),
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
      child: const Row(
        children: [
          Icon(Icons.swap_horizontal_circle_outlined, color: _kTeal, size: 40),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Veri Yönetim Paneli',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kTextPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Bu panelden katalog verinizi yedekleyebilir, yeni kataloglar yükleyebilir veya müşteri listelerinizi aktarabilirsiniz.',
                  style: TextStyle(fontSize: 12, color: _kTextSecondary, height: 1.3),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kTextPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _kTextSecondary, size: 20),
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
                    Icon(Icons.cleaning_services_rounded, color: Color(0xFFF59E0B), size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Standart Sıfırlama', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          SizedBox(height: 2),
                          Text(
                            'Satışlar, siparişler, müşteriler ve ürünler silinir. Ayarlar ve yedekler korunur.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
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
                    Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626), size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tam Temizlik', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFDC2626))),
                          SizedBox(height: 2),
                          Text(
                            'Tüm veriler, ayarlar, PIN kodu ve yedekler silinir. Cihaz fabrika ayarlarına döner.',
                            style: TextStyle(color: Color(0xFF991B1B), fontSize: 12),
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
            child: const Text('İptal', style: TextStyle(color: Color(0xFF64748B))),
          ),
        ],
      ),
    );

    if (resetType == null || !mounted) return;

    // Second confirmation dialog
    final title = resetType == 'standard' ? 'Standart Sıfırlama Onayı' : 'Tam Temizlik Onayı';
    final desc = resetType == 'standard'
        ? 'Tüm satışlar, siparişler, müşteriler ve ürünler kalıcı olarak silinecek. Ayarlarınız ve yedekleriniz korunacak.\n\nBu işlem geri alınamaz!'
        : 'Tüm veriler, ayarlar, PIN kodu, kullanıcılar ve yedekler silinecek. Cihaz ilk kurulum ekranına dönecek.\n\nBu işlem KESİNLİKLE geri alınamaz!';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(desc, style: const TextStyle(fontSize: 14, color: Color(0xFF475569))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: resetType == 'full' ? const Color(0xFFDC2626) : const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(resetType == 'standard' ? 'Standart Sıfırla' : 'Her Şeyi Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    requireAdminAccess(
      context,
      title: 'Sıfırlama Yetkisi',
      requirePin: true,
      requireConfirm: true,
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
          // ── Standart Sıfırlama: Sadece operasyonel veri ──
          // KRİTİK C DÜZELTMESİ: Tüm silme işlemleri tek bir SQLite transaction
          // içinde yapılır. Herhangi bir adım hata verirse işlemin tamamı geri alınır.
          if (!kIsWeb) {
            final db = await DatabaseManager().getDatabase();
            await db.transaction((txn) async {
              try {
                // Enable ledger bypass flag to allow deletion of financial_transactions
                await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');
                // 1. Satış kalemleri (sales'den önce — FK kısıtlaması)
                await txn.rawDelete('DELETE FROM sale_items');
                // 2. Satışlar
                await txn.rawDelete('DELETE FROM sales');
                // 3. Siparişler
                await txn.rawDelete('DELETE FROM orders');
                // 5. Ürünler
                await txn.rawDelete('DELETE FROM products');
                // 4. Finansal işlemler (borç/tahsilat)
                await txn.rawDelete('DELETE FROM financial_transactions');
                // 6. Müşteriler — peşin müşteri (id='' veya id='default') korunur
                await txn.rawDelete("DELETE FROM customers WHERE id != '' AND id != 'default'");
              } finally {
                // Disable ledger bypass flag to restore immutability
                await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
              }
            });
          } else {
            // Web: Sadece operasyonel tabloları sıfırla
            InMemoryDb.products.clear();
            InMemoryDb.sales.clear();
            InMemoryDb.transactions.clear();
            InMemoryDb.orders.clear();
            final defaultCust = InMemoryDb.customers.where((c) => c.id.isEmpty).toList();
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
                content: Text('Operasyonel veriler başarıyla sıfırlandı. Ayarlar korundu.'),
                backgroundColor: Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          // ── Tam Temizlik: Her şey silinir ──
          if (!kIsWeb) {
            final dbManager = DatabaseManager();
            await dbManager.resetDatabase();
            final backupService = ref.read(backupServiceProvider);
            await backupService.clearAllBackups();
          } else {
            InMemoryDb.reset();
          }

          // Clear ALL SharedPreferences (including settings, PIN)
          final prefs = ref.read(sharedPreferencesProvider);
          final keys = List<String>.from(prefs.getKeys());
          for (final key in keys) {
            await prefs.remove(key);
          }

          // Logout + cache sıfırlama
          await ref.read(authNotifierProvider.notifier).logout();
          ref.invalidate(currentUserProvider);
          ref.invalidate(settingsProvider);
          ref.invalidate(productRepositoryProvider);
          ref.invalidate(productsControllerProvider);
          ref.read(productCategoriesStateProvider.notifier).state = [];

          if (mounted) Navigator.pop(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tüm veriler silindi. Sistem ilk kuruluma hazırlanıyor...'),
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
        content: const Text('Katalogdaki tüm ürünler silinecektir. Bu işlem geri alınamaz. Emin misiniz?'),
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
      requirePin: true,
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

class ImportProgressDialog extends ConsumerStatefulWidget {
  final Uint8List? zipBytes;
  final String? filePath;
  const ImportProgressDialog({this.zipBytes, this.filePath, super.key});

  @override
  ConsumerState<ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends ConsumerState<ImportProgressDialog> {
  double progress = 0.0;
  String statusText = 'Dosya çözümleniyor...';
  bool isDone = false;
  String? errorMessage;
  Map<String, int>? resultSummary;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Tarayıcının diyalog kutusunu çizmesi için 150ms süre tanıyoruz.
    // Bu sayede donma hissi oluşmaz ve diyalog ilk andan itibaren görünür.
    Future.delayed(const Duration(milliseconds: 150), _startImport);
  }

  Future<void> _startImport() async {
    if (_started || !mounted) return;
    _started = true;

    try {
      Uint8List? bytes = widget.zipBytes;
      
      if (bytes == null && widget.filePath != null) {
        setState(() {
          statusText = 'Dosya okunuyor...';
        });
        final ioFile = File(widget.filePath!);
        bytes = await ioFile.readAsBytes();
      }

      if (bytes == null) {
        throw Exception('Dosya içeriği okunamadı.');
      }

      final importer = await ref.read(datasetImportServiceProvider.future);
      final result = await importer.importFromZip(bytes, (p, msg) {
        if (mounted) {
          setState(() {
            progress = p;
            statusText = msg;
          });
        }
      });

      if (mounted) {
        setState(() {
          isDone = true;
          progress = 1.0;
          statusText = 'Başarıyla Tamamlandı!';
          resultSummary = result;
        });
      }
      ref.invalidate(productRepositoryProvider);
    } catch (e, stackTrace) {
      debugPrint('❌ CATALOG IMPORT ERROR: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          statusText = 'Hata Oluştu';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        errorMessage != null ? 'İçe Aktarma Başarısız' : (isDone ? 'İçe Aktarma Tamamlandı' : 'İçe Aktarılıyor...'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage == null && !isDone) ...[
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
            ),
            const SizedBox(height: 16),
            Text(statusText, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              valueColor: const AlwaysStoppedAnimation<Color>(_kGreen),
              backgroundColor: _kBorderColor,
            ),
          ] else if (errorMessage != null) ...[
            const Icon(Icons.error_outline_rounded, color: _kPink, size: 48),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ] else ...[
            const Icon(Icons.check_circle_outline_rounded, color: _kGreen, size: 48),
            const SizedBox(height: 16),
            Text(
              'Katalog başarıyla içe aktarıldı!\n\nBaşarılı: ${resultSummary?['success'] ?? 0}\nHatalı: ${resultSummary?['error'] ?? 0}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ]
        ],
      ),
      actions: [
        if (isDone || errorMessage != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

class ExportProgressDialog extends ConsumerStatefulWidget {
  const ExportProgressDialog({super.key});

  @override
  ConsumerState<ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends ConsumerState<ExportProgressDialog> {
  double progress = 0.0;
  String statusText = 'Veritabanı okunuyor...';
  bool isDone = false;
  String? errorMessage;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Tarayıcının diyalog kutusunu çizmesi için 150ms süre tanıyoruz.
    Future.delayed(const Duration(milliseconds: 150), _startExport);
  }

  Future<void> _startExport() async {
    if (_started || !mounted) return;
    _started = true;

    try {
      final importer = await ref.read(datasetImportServiceProvider.future);
      final zipBytes = await importer.exportToZip((p) {
        if (mounted) {
          setState(() {
            progress = p;
            if (p < 0.15) {
              statusText = 'Katalog Excel dosyası oluşturuluyor...';
            } else if (p < 0.85) {
              statusText = 'Görseller arşivleniyor... (%${(p * 100).toStringAsFixed(0)})';
            } else if (p < 0.95) {
              statusText = 'Arşiv sıkıştırılıyor...';
            } else {
              statusText = 'Tamamlanıyor...';
            }
          });
        }
      });

      if (mounted) {
        setState(() {
          isDone = true;
          progress = 1.0;
          statusText = 'Arşiv başarıyla oluşturuldu!';
        });
      }

      if (mounted) {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        await FileSaverHelper.saveAndShareFile(
          bytes: zipBytes,
          filename: 'serenut_katalog_$timestamp.zip',
          context: context,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Katalog başarıyla dışarı aktarıldı.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          statusText = 'Hata Oluştu';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        errorMessage != null ? 'Dışarı Aktarma Başarısız' : (isDone ? 'İşlem Tamamlandı' : 'Dışarı Aktarılıyor...'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage == null && !isDone) ...[
            const CircularProgressIndicator(
               valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
            ),
            const SizedBox(height: 16),
            Text(statusText, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              valueColor: const AlwaysStoppedAnimation<Color>(_kGreen),
              backgroundColor: _kBorderColor,
            ),
          ] else if (errorMessage != null) ...[
            const Icon(Icons.error_outline_rounded, color: _kPink, size: 48),
            const SizedBox(height: 16),
            Text(errorMessage!, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
          ] else ...[
            const Icon(Icons.check_circle_outline_rounded, color: _kGreen, size: 48),
            const SizedBox(height: 16),
            Text(statusText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ]
        ],
      ),
      actions: [
        if (errorMessage != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── REHBERDEN MÜŞTERİ İÇE AKTARMA EKRANI (PLATFORM DESTEKLİ) ─────────────────
// ══════════════════════════════════════════════════════════════════════════════

class ContactImportPage extends ConsumerStatefulWidget {
  const ContactImportPage({super.key});

  @override
  ConsumerState<ContactImportPage> createState() => _ContactImportPageState();
}

class _ContactImportPageState extends ConsumerState<ContactImportPage> {
  List<Map<String, String>> _contacts = [];
  final List<int> _selectedIndices = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _hasPermission = false;
  String? _errorMessage;
  String? _loadedFileName;

  bool get _useFileImport => kIsWeb || (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_useFileImport) {
        // Desktop & Web: Bypassing native permission and start layout without simulated contacts.
        _contacts = [];
        _hasPermission = true;
      } else {
        // Native platforms (Mobile) permission handling
        var status = await Permission.contacts.status;
        if (!status.isGranted) {
          status = await Permission.contacts.request();
        }

        if (status.isGranted) {
          // Fetch real contacts
          final nativeContacts = await FlutterContacts.getContacts(
            withProperties: true,
            withPhoto: false,
          );
          
          final List<Map<String, String>> loaded = [];
          for (var c in nativeContacts) {
            final name = c.displayName.trim();
            
            // Find first valid phone number
            String phone = '';
            for (var p in c.phones) {
              // Extract digits/symbols only
              final cleaned = p.number.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.isNotEmpty) {
                phone = cleaned;
                break;
              }
            }

            // Find first valid email
            String email = '';
            for (var e in c.emails) {
              final cleanedEmail = e.address.trim();
              if (cleanedEmail.isNotEmpty) {
                email = cleanedEmail;
                break;
              }
            }

            if (phone.isNotEmpty) {
              loaded.add({
                'name': name.isEmpty ? 'İsimsiz' : name,
                'phone': phone,
                'email': email,
              });
            }
          }
          
          // Sort by name case-insensitive
          loaded.sort((a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));
          
          _contacts = loaded;
          _hasPermission = true;
        } else {
          _hasPermission = false;
        }
      }
    } catch (e) {
      _errorMessage = 'Kişiler yüklenirken bir hata oluştu: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestPermission() async {
    if (kIsWeb) return;
    final status = await Permission.contacts.request();
    if (status.isGranted) {
      _loadContacts();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rehbere erişim izni reddedildi.'),
            backgroundColor: _kPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<Map<String, String>> _parseVcf(String text) {
    final List<Map<String, String>> contacts = [];
    final cards = text.split('BEGIN:VCARD');
    for (var card in cards) {
      if (!card.contains('END:VCARD')) continue;
      String name = '';
      String phone = '';
      String email = '';
      
      final lines = card.split('\n');
      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('FN:')) {
          name = line.substring(3).trim();
        } else if (line.startsWith('N:') && name.isEmpty) {
          final parts = line.substring(2).split(';');
          name = parts.where((p) => p.isNotEmpty).join(' ').trim();
        } else if (line.startsWith('TEL')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            phone = parts.sublist(1).join(':').replaceAll(RegExp(r'\s+'), '');
          }
        } else if (line.startsWith('EMAIL')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            email = parts.sublist(1).join(':').trim();
          }
        }
      }
      if (phone.isNotEmpty) {
        contacts.add({
          'name': name.isEmpty ? 'İsimsiz' : name,
          'phone': phone,
          'email': email,
        });
      }
    }
    return contacts;
  }

  List<Map<String, String>> _parseCsv(String text) {
    final List<Map<String, String>> contacts = [];
    final lines = text.split('\n');
    if (lines.isEmpty) return contacts;
    
    String separator = ',';
    final firstLine = lines.first;
    if (firstLine.contains(';')) {
      separator = ';';
    }
    
    int nameCol = -1;
    int phoneCol = -1;
    int emailCol = -1;
    
    final headers = firstLine.split(separator);
    for (int i = 0; i < headers.length; i++) {
      final cell = headers[i].toLowerCase().trim();
      if (cell.contains('isim') || cell.contains('ad') || cell.contains('name')) {
        nameCol = i;
      } else if (cell.contains('tel') || cell.contains('telefon') || cell.contains('phone')) {
        phoneCol = i;
      } else if (cell.contains('mail') || cell.contains('eposta') || cell.contains('email')) {
        emailCol = i;
      }
    }
    
    if (nameCol == -1 && phoneCol == -1) {
      nameCol = 0;
      phoneCol = 1;
      if (headers.length > 2) emailCol = 2;
    }
    
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      final cells = line.split(separator);
      if (cells.length <= nameCol || cells.length <= phoneCol) continue;
      
      final name = cells[nameCol].replaceAll('"', '').trim();
      final phone = cells[phoneCol].replaceAll('"', '').replaceAll(RegExp(r'\s+'), '').trim();
      final email = emailCol != -1 && cells.length > emailCol ? cells[emailCol].replaceAll('"', '').trim() : '';
      
      if (phone.isNotEmpty) {
        contacts.add({
          'name': name.isEmpty ? 'İsimsiz' : name,
          'phone': phone,
          'email': email,
        });
      }
    }
    return contacts;
  }

  List<Map<String, String>> _parseExcel(List<int> bytes) {
    final List<Map<String, String>> contacts = [];
    try {
      final excel = Excel.decodeBytes(bytes);
      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null || sheet.maxRows <= 1) continue;
        
        int nameCol = -1;
        int phoneCol = -1;
        int emailCol = -1;
        
        final firstRow = sheet.rows.first;
        for (int i = 0; i < firstRow.length; i++) {
          final cellValue = firstRow[i]?.value?.toString().toLowerCase().trim() ?? '';
          if (cellValue.contains('isim') || cellValue.contains('ad') || cellValue.contains('name')) {
            nameCol = i;
          } else if (cellValue.contains('tel') || cellValue.contains('telefon') || cellValue.contains('phone')) {
            phoneCol = i;
          } else if (cellValue.contains('mail') || cellValue.contains('eposta') || cellValue.contains('email')) {
            emailCol = i;
          }
        }
        
        if (nameCol == -1 && phoneCol == -1) {
          nameCol = 0;
          phoneCol = 1;
          if (sheet.maxColumns > 2) emailCol = 2;
        }
        
        for (int r = 1; r < sheet.maxRows; r++) {
          final row = sheet.rows[r];
          if (row.length <= nameCol || row.length <= phoneCol) continue;
          
          final name = row[nameCol]?.value?.toString().trim() ?? '';
          final phone = row[phoneCol]?.value?.toString().replaceAll(RegExp(r'\s+'), '') ?? '';
          final email = emailCol != -1 && row.length > emailCol ? row[emailCol]?.value?.toString().trim() ?? '' : '';
          
          if (phone.isNotEmpty) {
            contacts.add({
              'name': name.isEmpty ? 'İsimsiz' : name,
              'phone': phone,
              'email': email,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Excel parsing error: $e');
    }
    return contacts;
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'vcf'],
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final file = result.files.first;
      final Uint8List? bytes;
      if (kIsWeb) {
        bytes = file.bytes;
      } else {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        throw Exception('Dosya içeriği okunamadı.');
      }

      final ext = file.extension?.toLowerCase() ?? '';
      List<Map<String, String>> parsed = [];

      if (ext == 'vcf') {
        final text = utf8.decode(bytes, allowMalformed: true);
        parsed = _parseVcf(text);
      } else if (ext == 'csv') {
        final text = utf8.decode(bytes, allowMalformed: true);
        parsed = _parseCsv(text);
      } else if (ext == 'xlsx' || ext == 'xls') {
        parsed = _parseExcel(bytes);
      } else {
        throw Exception('Desteklenmeyen dosya formatı.');
      }

      setState(() {
        _contacts = parsed;
        _selectedIndices.clear();
        _loadedFileName = file.name;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${parsed.length} kişi dosyadan yüklendi.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Dosya yüklenirken hata oluştu: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter contacts based on search query
    final List<int> filteredIndices = [];
    for (int i = 0; i < _contacts.length; i++) {
      final c = _contacts[i];
      final nameMatches = c['name']!.toLowerCase().contains(_searchQuery.toLowerCase());
      final phoneMatches = c['phone']!.contains(_searchQuery);
      if (_searchQuery.isEmpty || nameMatches || phoneMatches) {
        filteredIndices.add(i);
      }
    }

    return FullScreenSettingsPage(
      title: 'Rehberden İçe Aktar',
      useScrollView: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Web Warn Banner
          if (kIsWeb && _loadedFileName == null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kOrange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: _kOrange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Web sürümünde cihaz rehberine erişim desteklenmediği için kendi yedek dosyanızı (.xlsx, .csv, .vcf) aktarabilirsiniz.',
                      style: TextStyle(color: _kOrange, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          // 2. File Import Header (Only if file is loaded on Web/Windows)
          if (!_isLoading && _useFileImport && _loadedFileName != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBlue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.file_present_rounded, color: _kBlue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_loadedFileName dosyasından ${_contacts.length} kişi yüklendi.',
                      style: const TextStyle(color: _kBlue, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _kBlue, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _loadedFileName = null;
                      });
                      _loadContacts();
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: _kBorderColor),
          ],

          // 3. Conditional Content
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
                ),
              ),
            )
          else if (_useFileImport && _loadedFileName == null)
            // Web & Windows: Show Upload Card
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_upload_outlined, size: 72, color: _kBlue),
                        const SizedBox(height: 16),
                        const Text(
                          'Rehber Yedek Dosyası Yükle',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Müşterilerinizi toplu olarak eklemek için Excel (.xlsx), CSV (.csv) veya vCard (.vcf) formatındaki rehber dosyanızı seçin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: _kTextSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _importFromFile,
                          icon: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 18),
                          label: const Text(
                            'Dosya Seçin',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (!_hasPermission && _loadedFileName == null)
            // Mobile (iOS/Android): Show permission required
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.contact_phone_rounded, size: 64, color: _kTextSecondary),
                        const SizedBox(height: 16),
                        const Text(
                          'Rehber İzni Gerekli',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Müşterilerinizi hızlıca aktarabilmek için uygulamanın rehberinize erişmesine izin vermelisiniz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: _kTextSecondary),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _requestPermission,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text(
                            'İzin Ver',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 64, color: _kPink),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: _kTextSecondary),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            if (_loadedFileName != null) {
                              setState(() {
                                _loadedFileName = null;
                              });
                            }
                            _loadContacts();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Yeniden Dene', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else ...[
            // Arama kutusu
            Container(
              height: 38,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3E3E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, color: _kTextSecondary, size: 18),
                  hintText: 'Rehberde Ara...',
                  hintStyle: TextStyle(color: _kTextSecondary, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 9),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              ),
            ),

            // Seçim kontrolleri
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: Icon(
                    (_selectedIndices.length == filteredIndices.length && filteredIndices.isNotEmpty)
                        ? Icons.check_box_rounded 
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: _kGreen,
                  ),
                  label: Text(
                    (_selectedIndices.length == filteredIndices.length && filteredIndices.isNotEmpty)
                        ? 'Seçilenleri Temizle' 
                        : 'Tümünü Seç',
                    style: const TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () {
                    setState(() {
                      if (_selectedIndices.length == filteredIndices.length) {
                        _selectedIndices.clear();
                      } else {
                        _selectedIndices.clear();
                        _selectedIndices.addAll(filteredIndices);
                      }
                    });
                  },
                ),
                Text(
                  '${_selectedIndices.length} / ${filteredIndices.length} Seçildi',
                  style: const TextStyle(fontSize: 13, color: _kTextSecondary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(color: _kBorderColor),

            // Kişi Listesi (Virtualized & Scrollable)
            Expanded(
              child: filteredIndices.isEmpty
                  ? const Center(
                      child: Text(
                        'Aranan kişi bulunamadı.',
                        style: TextStyle(color: _kTextSecondary, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filteredIndices.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: _kBorderColor),
                      itemBuilder: (context, index) {
                        final contactIdx = filteredIndices[index];
                        final contact = _contacts[contactIdx];
                        final isSelected = _selectedIndices.contains(contactIdx);
                        return CheckboxListTile(
                          value: isSelected,
                          activeColor: _kGreen,
                          title: Text(
                            contact['name']!,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _kTextPrimary),
                          ),
                          subtitle: Text(
                            contact['phone']!,
                            style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                          ),
                          secondary: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _kBlue.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                contact['name']!.isNotEmpty ? contact['name']![0].toUpperCase() : '👤',
                                style: const TextStyle(color: _kBlue, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedIndices.add(contactIdx);
                              } else {
                                _selectedIndices.remove(contactIdx);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            
            // İçe Aktarma Butonu
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _selectedIndices.isEmpty
                    ? null
                    : () async {
                        final customers = ref.read(customersControllerProvider).value ?? [];
                        int importedCount = 0;
                        int skippedCount = 0;

                        // Show dialog to block user interface during DB operations
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
                            ),
                          ),
                        );

                        try {
                          for (final idx in _selectedIndices) {
                            final contact = _contacts[idx];
                            final phone = contact['phone']!;
                            
                            if (customers.any((c) => c.phone == phone)) {
                              skippedCount++;
                              continue;
                            }

                            final newCustomer = CustomerEntity(
                              id: const Uuid().v4(),
                              name: contact['name']!,
                              email: contact['email']!,
                              phone: phone,
                              balance: 0.0,
                              createdAt: DateTime.now(),
                            );
                            await ref.read(customersControllerProvider.notifier).addCustomer(newCustomer);
                            importedCount++;
                          }
                        } finally {
                          if (context.mounted) {
                            Navigator.pop(context); // Dismiss the progress loading dialog
                          }
                        }

                        if (context.mounted) {
                          Navigator.pop(context); // Close the ContactImportPage
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                importedCount > 0
                                    ? '$importedCount kişi rehberden başarıyla içe aktarıldı.${skippedCount > 0 ? " ($skippedCount kişi zaten kayıtlı olduğu için atlandı.)" : ""}'
                                    : 'Seçilen kişilerin tamamı zaten sistemde kayıtlı.',
                              ),
                              backgroundColor: importedCount > 0 ? _kGreen : _kOrange,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  _selectedIndices.isEmpty 
                      ? 'Lütfen Kişi Seçin' 
                      : 'Seçilenleri İçe Aktar (${_selectedIndices.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
