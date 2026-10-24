// lib/presentation/widgets/migration_consent_dialog.dart
// Serenut OS — Core Next Veritabanı Geçiş Onayı Diyaloğu (Stage 10.12.17)
// Kullanıcıya açık bilgi veren, yedekleme garantisi sunan ve erteleme imkanı tanıyan onay penceresi.

import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';

/// Kullanıcıya Core Next veritabanı geçiş onay penceresini gösterir.
Future<MigrationConsentDecision> showMigrationConsentDialog({
  required BuildContext context,
  String? sourceDbPath,
  String? targetDbPath,
  int? estimatedProductCount,
  int? estimatedCustomerCount,
}) async {
  return await showDialog<MigrationConsentDecision>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MigrationConsentDialog(
          sourceDbPath: sourceDbPath,
          targetDbPath: targetDbPath,
          estimatedProductCount: estimatedProductCount,
          estimatedCustomerCount: estimatedCustomerCount,
        ),
      ) ??
      MigrationConsentDecision.postponed;
}

class MigrationConsentDialog extends StatefulWidget {
  final String? sourceDbPath;
  final String? targetDbPath;
  final int? estimatedProductCount;
  final int? estimatedCustomerCount;
  final ValueChanged<MigrationConsentDecision>? onDecision;

  const MigrationConsentDialog({
    super.key,
    this.sourceDbPath,
    this.targetDbPath,
    this.estimatedProductCount,
    this.estimatedCustomerCount,
    this.onDecision,
  });

  @override
  State<MigrationConsentDialog> createState() => _MigrationConsentDialogState();
}

class _MigrationConsentDialogState extends State<MigrationConsentDialog> {
  bool _showAuditDetails = false;

  @override
  Widget build(BuildContext context) {
    final prodCountStr = widget.estimatedProductCount != null
        ? '${widget.estimatedProductCount} adet'
        : '37.000+ adet';
    final custCountStr = widget.estimatedCustomerCount != null
        ? '${widget.estimatedCustomerCount} adet'
        : '500+ adet';

    return Dialog(
      backgroundColor: POSColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: POSColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Başlık Bölümü ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: POSColors.greenLight,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Icon(
                      Icons.security_update_good_rounded,
                      color: POSColors.green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sistem ve Veritabanı Optimizasyonu',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: POSColors.text,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Core Next Yeni Nesil Altyapı Geçişi',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: POSColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(color: POSColors.border, height: 1),
              const SizedBox(height: AppSpacing.md),

              // ── Açıklama ve Kapsam Bilgisi (Kaydırılabilir Alan) ──
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. İşlem Nedeni
                      Text(
                        'Neden Yapılıyor?',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: POSColors.text,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'İşletmenizin satış, stok ve cari işlemlerinin daha yüksek performansla, kuruş hassasiyetinde ve sıfır veri kaybı güvencesiyle çalışabilmesi için veritabanınız Core Next mimarisine taşınacaktır.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: POSColors.textSecondary,
                              height: 1.45,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2. Aktarılacak Veriler
                      Text(
                        'Aktarılacak Veriler ve Kapsam',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: POSColors.text,
                            ),
                      ),
                      const SizedBox(height: 6),
                      _buildInfoItem(
                        icon: Icons.inventory_2_outlined,
                        title: 'Katalog ve Stoklar',
                        subtitle: '$prodCountStr ürün ve stok kayıtları kuruş bazında aktarılacaktır.',
                      ),
                      _buildInfoItem(
                        icon: Icons.people_outline_rounded,
                        title: 'Cari Hesaplar ve Bakiyeler',
                        subtitle: '$custCountStr müşteri, defter hareketleri ve taksit planları.',
                      ),
                      _buildInfoItem(
                        icon: Icons.point_of_sale_rounded,
                        title: 'Satışlar, Siparişler ve Kasa',
                        subtitle: 'Tüm geçmiş satışlar, siparişler ve nakit kasa hareketleri eksiksiz korunacaktır.',
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 3. Önemli Güvenlik ve Kesinti Uyarısı
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: POSColors.amberLight,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(
                            color: POSColors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: POSColors.amberDark,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'Önemli Bilgilendirme',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: POSColors.amberDark,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '• İşlem süresince (~10-15 saniye) uygulama kullanılamayabilir.\n'
                              '• İşlem başlamadan önce otomatik doğrulanmış SQLite yedeği alınır.\n'
                              '• Yeni satış yapıldıktan sonra eski sürüme geri dönüş, yeni kayıtların kaybolmaması için güvenlik kilitleriyle korunur.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: POSColors.text,
                                    height: 1.45,
                                  ),
                            ),
                          ],
                        ),
                      ),

                      // 4. Detaylı İnceleme Paneli (Açılır Sekme)
                      if (_showAuditDetails) ...[
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: POSColors.card,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(color: POSColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Teknik Denetim ve Güvenlik Parametreleri',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: POSColors.text,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              _buildParamRow('Kaynak Veritabanı:', widget.sourceDbPath ?? 'serenut_pos.db'),
                              _buildParamRow('Hedef Veritabanı:', widget.targetDbPath ?? 'core_next.db'),
                              _buildParamRow('Doğrulama Modu:', 'PRAGMA integrity_check + WAL Checkpoint'),
                              _buildParamRow('Finansal Mutabakat:', 'Kuruş duyarlı (Authoritative cents)'),
                              _buildParamRow('Rollback Güvencesi:', 'assertSafeRollback (Fail-Closed)'),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              const Divider(color: POSColors.border, height: 1),
              const SizedBox(height: AppSpacing.md),

              // ── Aksiyon Butonları ──
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  // 1. Şimdi Değil (İptal / Ertele)
                  OutlinedButton(
                    onPressed: () => _submitDecision(MigrationConsentDecision.postponed),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: POSColors.textSecondary,
                      side: const BorderSide(color: POSColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                    ),
                    child: const Text('Şimdi Değil'),
                  ),

                  // 2. Koşulları İncele / Gizle
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAuditDetails = !_showAuditDetails;
                      });
                    },
                    icon: Icon(
                      _showAuditDetails ? Icons.expand_less_rounded : Icons.manage_search_rounded,
                      size: 16,
                      color: POSColors.green,
                    ),
                    label: Text(
                      _showAuditDetails ? 'Gizle' : 'Koşulları İncele',
                      style: const TextStyle(color: POSColors.green, fontWeight: FontWeight.w600),
                    ),
                  ),

                  // 3. Geçişi Onayla
                  FilledButton.icon(
                    onPressed: () => _submitDecision(MigrationConsentDecision.approved),
                    style: FilledButton.styleFrom(
                      backgroundColor: POSColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('Geçişi Onayla'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitDecision(MigrationConsentDecision decision) {
    if (widget.onDecision != null) {
      widget.onDecision!(decision);
    } else {
      Navigator.of(context).pop(decision);
    }
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: POSColors.green),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$title: $subtitle',
              style: const TextStyle(fontSize: 13, color: POSColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: POSColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: POSColors.text),
            ),
          ),
        ],
      ),
    );
  }
}
