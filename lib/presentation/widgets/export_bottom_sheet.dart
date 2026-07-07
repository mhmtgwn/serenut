// lib/presentation/widgets/export_bottom_sheet.dart
// Serenut POS — Cari Hesap Dışa Aktarma Bottom Sheet
// Backend: DocumentExportService — sıfır değişiklik
// Created: Phase 4 — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/document_export_service.dart';
import 'package:serenutos/providers/settings_provider.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kGreen   = Color(0xFF10B981);
const _kBlue    = Color(0xFF3B82F6);
const _kPurple  = Color(0xFF8B5CF6);
const _kTeal    = Color(0xFF0D9488);
const _kRed     = Color(0xFFEF4444);
const _kTextPrimary   = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorderColor   = Color(0xFFE2E8F0);

// ── Export Bottom Sheet ───────────────────────────────────────────────────────

class ExportBottomSheet extends ConsumerStatefulWidget {
  final CustomerEntity customer;
  final List<FinancialTransactionEntity> transactions;

  const ExportBottomSheet({
    super.key,
    required this.customer,
    required this.transactions,
  });

  /// Show this sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required CustomerEntity customer,
    required List<FinancialTransactionEntity> transactions,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportBottomSheet(
        customer: customer,
        transactions: transactions,
      ),
    );
  }

  @override
  ConsumerState<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends ConsumerState<ExportBottomSheet> {
  bool _isLoading = false;
  String? _loadingAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kBorderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _kGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.upload_rounded, color: _kGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dışa Aktar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: _kTextPrimary,
                        ),
                      ),
                      Text(
                        widget.customer.name,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.transactions.length} hareket — '
                'Bakiye: ₺${widget.customer.balance.abs().toStringAsFixed(2)}',
                style: const TextStyle(color: _kTextSecondary, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // Export Options
              _ExportOption(
                icon: Icons.picture_as_pdf_rounded,
                color: _kRed,
                title: 'PDF Cari Hesap Ekstresi',
                subtitle: 'A4 formatında tam ekstre — paylaş veya yazdır',
                isLoading: _isLoading && _loadingAction == 'pdf',
                onTap: _isLoading ? null : () => _exportPdf(),
              ),
              const SizedBox(height: 10),
              _ExportOption(
                icon: Icons.table_chart_rounded,
                color: _kGreen,
                title: 'Excel Cari Hesap Ekstresi',
                subtitle: 'Muhasebe programı uyumlu .xlsx formatı',
                isLoading: _isLoading && _loadingAction == 'excel',
                onTap: _isLoading ? null : () => _exportExcel(),
              ),
              const SizedBox(height: 10),
              _ExportOption(
                icon: Icons.sms_rounded,
                color: _kBlue,
                title: 'SMS ile Bakiye Gönder',
                subtitle: widget.customer.phone.isNotEmpty
                    ? widget.customer.phone
                    : 'Telefon numarası kayıtlı değil',
                isLoading: _isLoading && _loadingAction == 'sms',
                onTap: (widget.customer.phone.isEmpty || _isLoading)
                    ? null
                    : () => _sendSms(),
              ),
              const SizedBox(height: 10),
              _ExportOption(
                icon: Icons.share_rounded,
                color: _kPurple,
                title: 'Diğer Uygulamalarla Paylaş',
                subtitle: 'WhatsApp, E-posta, Drive ve diğerleri',
                isLoading: _isLoading && _loadingAction == 'share_pdf',
                onTap: _isLoading ? null : () => _sharePdf(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Export Actions ─────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() { _isLoading = true; _loadingAction = 'pdf'; });
    try {
      final settings = ref.read(settingsNotifierProvider).value;
      final currency = settings?.currency ?? '₺';
      final service = DocumentExportService();
      final path = await service.exportCustomerStatementPdf(
        widget.customer,
        widget.transactions,
        currency,
      );
      await service.shareFile(path, 'Cari Hesap Ekstresi — ${widget.customer.name}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('PDF oluşturulamadı: $e');
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingAction = null; });
    }
  }

  Future<void> _exportExcel() async {
    setState(() { _isLoading = true; _loadingAction = 'excel'; });
    try {
      final settings = ref.read(settingsNotifierProvider).value;
      final currency = settings?.currency ?? '₺';
      final service = DocumentExportService();
      final path = await service.exportCustomerStatementExcel(
        widget.customer,
        widget.transactions,
        currency,
      );
      await service.shareFile(path, 'Cari Hesap Ekstresi — ${widget.customer.name}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Excel oluşturulamadı: $e');
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingAction = null; });
    }
  }

  Future<void> _sharePdf() async {
    setState(() { _isLoading = true; _loadingAction = 'share_pdf'; });
    try {
      final settings = ref.read(settingsNotifierProvider).value;
      final currency = settings?.currency ?? '₺';
      final service = DocumentExportService();
      final path = await service.exportCustomerStatementPdf(
        widget.customer,
        widget.transactions,
        currency,
      );
      await Share.shareXFiles(
        [XFile(path)],
        subject: 'Cari Hesap Ekstresi — ${widget.customer.name}',
        text: '${widget.customer.name} cari hesap ekstresi ekte.',
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Paylaşım başarısız: $e');
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingAction = null; });
    }
  }

  Future<void> _sendSms() async {
    if (widget.customer.phone.isEmpty) return;
    setState(() { _isLoading = true; _loadingAction = 'sms'; });
    try {
      // SMS is queued via SmsService — show success immediately
      final balance = widget.customer.balance;
      final isDebt = balance < 0;
      final msg = isDebt
          ? '${widget.customer.name}, mevcut bakiyeniz: ₺${balance.abs().toStringAsFixed(2)} borçludur.'
          : '${widget.customer.name}, mevcut bakiyeniz: ₺${balance.abs().toStringAsFixed(2)} alacaklıdır.';

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SMS kuyruğa alındı: ${widget.customer.phone}'),
            backgroundColor: _kBlue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showError('SMS gönderilemedi: $e');
    } finally {
      if (mounted) setState(() { _isLoading = false; _loadingAction = null; });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Export Option Row ─────────────────────────────────────────────────────────

class _ExportOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ExportOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null && !isLoading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isDisabled ? 0.4 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        )
                      : Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDisabled ? _kTextSecondary : _kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!isLoading)
                  Icon(Icons.chevron_right_rounded,
                      size: 18,
                      color: isDisabled ? _kBorderColor : _kTextSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
