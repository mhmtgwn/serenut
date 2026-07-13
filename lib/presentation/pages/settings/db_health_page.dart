import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';

class DbHealthPage extends ConsumerStatefulWidget {
  const DbHealthPage({super.key});

  @override
  ConsumerState<DbHealthPage> createState() => _DbHealthPageState();
}

class _DbHealthPageState extends ConsumerState<DbHealthPage> {
  DatabaseHealthReport? _report;
  bool _isLoading = false;
  bool _hasScanned = false;

  Future<void> _runHealthCheck() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = await ref.read(dataIntegrityServiceProvider.future);
      final report = await service.checkDatabaseHealth();
      setState(() {
        _report = report;
        _hasScanned = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sağlık kontrolü başarısız oldu: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _repairHealth() async {
    requirePermissionAccess(
      context,
      permission: Permission.settingsDatabase,
      title: 'Veritabanı Onarım Yetkisi',
      requirePin: true,
      onGranted: (approvedByUserId, approvedByUserName) async {
        setState(() {
          _isLoading = true;
        });

        try {
          final service = await ref.read(dataIntegrityServiceProvider.future);
          await service.repairDatabaseHealth();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Veritabanı başarıyla onarıldı.')),
            );
          }
          // Re-run scan to verify fix
          await _runHealthCheck();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Veritabanı onarımı başarısız oldu: $e')),
            );
          }
        } finally {
          setState(() {
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runHealthCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final hasAccess = currentUser != null && (
      currentUser.role == UserRole.sysadmin ||
      currentUser.role == UserRole.owner ||
      currentUser.role == UserRole.admin ||
      currentUser.hasPermission(Permission.settingsDatabase.value)
    );

    if (!hasAccess) {
      return const Scaffold(
        body: Center(
          child: Text('Bu sayfaya erişim yetkiniz bulunmuyor.'),
        ),
      );
    }

    return FullScreenSettingsPage(
      title: 'Veritabanı Sağlık Kontrolü',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Explanation Card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderColor),
            ),
            child: const Row(
              children: [
                Icon(Icons.health_and_safety_rounded, color: kGreen, size: 40),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Veri Bütünlüğü Güvencesi',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kTextPrimary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Bu araç veritabanındaki yetim kayıtları, bozuk referansları, negatif stokları ve cari hesap sapmalarını denetler.',
                        style: TextStyle(fontSize: 12, color: kTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Loading state ──
          if (_isLoading && !_hasScanned)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(kGreen)),
              ),
            )

          // ── Scan Result Section ──
          else if (_hasScanned && _report != null) ...[
            _buildStatusHeader(_report!),
            const SizedBox(height: 20),
            const Text(
              'DETAYLI DENETİM RAPORU',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextSecondary, letterSpacing: 0.3),
            ),
            const SizedBox(height: 8),
            _buildReportDetailsCard(_report!),
            const SizedBox(height: 24),
            _buildActionButtons(_report!),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusHeader(DatabaseHealthReport report) {
    final bool isHealthy = report.isHealthy;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isHealthy ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHealthy ? const Color(0xFFA7F3D0) : const Color(0xFFFCA5A5)),
      ),
      child: Column(
        children: [
          Icon(
            isHealthy ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: isHealthy ? kGreen : kPink,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            isHealthy ? 'Veritabanı Sağlıklı' : 'Sağlık Sorunları Tespit Edildi',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isHealthy ? const Color(0xFF065F46) : const Color(0xFF991B1B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isHealthy
                ? 'Tüm referanslar, stoklar ve cari hesap bakiyeleri mükemmel durumda.'
                : 'Veritabanında otomatik onarılması gereken yapısal tutarsızlıklar bulundu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isHealthy ? const Color(0xFF047857) : const Color(0xFFB91C1C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportDetailsCard(DatabaseHealthReport report) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            icon: Icons.shopping_basket_outlined,
            title: 'Yetim Satış Kalemleri',
            count: report.orphanedSaleItemsCount,
          ),
          const IOSDivider(),
          _buildDetailRow(
            icon: Icons.list_alt_rounded,
            title: 'Yetim Sipariş Kalemleri',
            count: report.orphanedOrderItemsCount,
          ),
          const IOSDivider(),
          _buildDetailRow(
            icon: Icons.credit_card_rounded,
            title: 'Yetim Sipariş Ödemeleri',
            count: report.orphanedOrderPaymentsCount,
          ),
          const IOSDivider(),
          _buildDetailRow(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Yetim Finansal Hareketler',
            count: report.orphanedTransactionsCount,
          ),
          const IOSDivider(),
          _buildDetailRow(
            icon: Icons.inventory_2_outlined,
            title: 'Negatif Stoklu Ürünler',
            count: report.negativeStockProductsCount,
          ),
          const IOSDivider(),
          _buildDetailRow(
            icon: Icons.compare_arrows_rounded,
            title: 'Cari Bakiye Sapmaları (Drift)',
            count: report.customerBalanceDriftsCount,
          ),
          const IOSDivider(),
          _buildDetailRow(
            icon: Icons.fingerprint_rounded,
            title: 'Çift UUID Kayıtları',
            count: report.duplicateUuidsCount,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required int count,
  }) {
    final bool hasIssue = count > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: hasIssue ? kPink : kTextSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: kTextPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: hasIssue ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              hasIssue ? '$count Sorun' : 'Temiz',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: hasIssue ? kPink : kTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(DatabaseHealthReport report) {
    final bool isHealthy = report.isHealthy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isHealthy) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _isLoading ? null : _repairHealth,
            icon: const Icon(Icons.build_rounded),
            label: const Text('Sorunları Düzelt ve Onar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: kTextPrimary,
            side: const BorderSide(color: kBorderColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isLoading ? null : _runHealthCheck,
          icon: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(kTextSecondary)))
              : const Icon(Icons.refresh_rounded),
          label: const Text('Yeniden Tara', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }
}
