// lib/presentation/pages/customer/ledger_explainability_sheet.dart
// Serenut OS — Ledger Bakiye Analiz & Doğrulama Ekranı
// Backend: DataIntegrityService (explainCustomerBalance + rebuildCustomerBalance + verifyLedgerInvariant) — sıfır değişiklik
// Created: Phase 4 — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kTextPrimary = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorderColor = Color(0xFFE2E8F0);

// ── Ledger Explainability Sheet ────────────────────────────────────────────────

class LedgerExplainabilitySheet extends ConsumerStatefulWidget {
  final CustomerEntity customer;

  const LedgerExplainabilitySheet({
    super.key,
    required this.customer,
  });

  /// Shows this sheet as a modal bottom sheet.
  static Future<void> show(BuildContext context, CustomerEntity customer) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LedgerExplainabilitySheet(customer: customer),
    );
  }

  @override
  ConsumerState<LedgerExplainabilitySheet> createState() =>
      _LedgerExplainabilitySheetState();
}

class _LedgerExplainabilitySheetState
    extends ConsumerState<LedgerExplainabilitySheet> {
  bool _isRebuilding = false;
  bool _isVerifying = true;
  bool? _isInvariantValid;
  List<BalanceExplanationRecord>? _explanations;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final service = await ref.read(dataIntegrityServiceProvider.future);
      final valid = await service.verifyLedgerInvariant(widget.customer.id);
      final list = await service.explainCustomerBalance(widget.customer.id);

      if (mounted) {
        setState(() {
          _isInvariantValid = valid;
          _explanations = list;
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ledger verileri alınamadı: $e';
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _rebuildBalance() async {
    setState(() {
      _isRebuilding = true;
    });

    try {
      final service = await ref.read(dataIntegrityServiceProvider.future);
      await service.rebuildCustomerBalance(widget.customer.id);

      // Invalidate customer providers to refresh UI balance values
      ref.invalidate(customersControllerProvider);
      ref.invalidate(customerBalanceDetailsProvider(widget.customer.id));

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Bakiye ledger hareketlerinden başarıyla yeniden oluşturuldu.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRebuilding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      height: media.size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _kPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.history_toggle_off_rounded,
                        color: _kPurple, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bakiye Analiz & Doğrulama',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _kTextPrimary,
                          ),
                        ),
                        Text(
                          '${widget.customer.name} — Cari Ledger İzlenebilirliği',
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: _kTextSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 24, color: _kBorderColor),

            Expanded(
              child: _error != null
                  ? Center(
                      child:
                          Text(_error!, style: const TextStyle(color: _kRed)))
                  : _isVerifying
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(_kPurple),
                            strokeWidth: 2,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              // Invariant Status Card
                              _buildStatusCard(),
                              const SizedBox(height: 16),

                              // State Replay / Rebuild Button
                              if (_isInvariantValid == false) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _isRebuilding ? null : _rebuildBalance,
                                    icon: _isRebuilding
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                      Colors.white),
                                            ),
                                          )
                                        : const Icon(Icons.restart_alt_rounded,
                                            size: 18),
                                    label: const Text(
                                        'Bakiyeyi Ledger\'dan Yeniden Hesapla (Replay)'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kBlue,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Section Header
                              Row(
                                children: [
                                  const Icon(Icons.analytics_outlined,
                                      color: _kTextSecondary, size: 16),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'KRONOLOJİK LEDGER GEÇMİŞİ',
                                    style: TextStyle(
                                      color: _kTextSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_explanations?.length ?? 0} İşlem',
                                    style: const TextStyle(
                                        color: _kTextSecondary, fontSize: 10),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Explanation List
                              Expanded(
                                child: _explanations == null ||
                                        _explanations!.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Bu müşteriye ait finansal işlem bulunamadı.',
                                          style: TextStyle(
                                              color: _kTextSecondary,
                                              fontSize: 13),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _explanations!.length,
                                        itemBuilder: (context, index) {
                                          final record = _explanations![index];
                                          return _buildTimelineItem(
                                              record,
                                              index ==
                                                  _explanations!.length - 1);
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status Card ────────────────────────────────────────────────────────────

  Widget _buildStatusCard() {
    final isValid = _isInvariantValid ?? true;
    final cardBg =
        isValid ? _kGreen.withOpacity(0.04) : _kRed.withOpacity(0.04);
    final borderCol =
        isValid ? _kGreen.withOpacity(0.2) : _kRed.withOpacity(0.2);
    final iconColor = isValid ? _kGreen : _kRed;
    final title =
        isValid ? 'Veri Bütünlüğü Doğrulandı' : 'Bakiye Sapması Tespit Edildi';
    final desc = isValid
        ? 'Müşteri net bakiyesi, veritabanı ledger hareket geçmişi ile matematiksel olarak 100% uyuşuyor.'
        : 'Müşterinin güncel bakiye değeri ile ledger hareketlerinin toplamı eşleşmiyor. State Replay yapmanız önerilir.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: borderCol),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isValid ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
              color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Timeline Item ──────────────────────────────────────────────────────────

  Widget _buildTimelineItem(BalanceExplanationRecord record, bool isLast) {
    final isIncrease = record.type == 'payment' ||
        record.type == 'collection' ||
        record.type == 'cancellation';
    final color = isIncrease ? _kGreen : _kRed;
    final prefix = isIncrease ? '+' : '-';
    final amountText = '$prefix₺${record.amount.toStringAsFixed(2)}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Indicator & Line
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: _kBorderColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),

          // Content Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _getTypeLabel(record.type),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: _kTextPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        amountText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record.description,
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          color: _kTextSecondary, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd.MM.yyyy HH:mm').format(record.date),
                        style: const TextStyle(
                            color: _kTextSecondary, fontSize: 10),
                      ),
                      const Spacer(),
                      Text(
                        'Running Balance: ₺${record.runningBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _kTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'sale':
        return 'Satış';
      case 'payment':
        return 'Ödeme';
      case 'cancellation':
        return 'İptal';
      case 'collection':
        return 'Tahsilat';
      case 'refund':
        return 'İade';
      default:
        return type.toUpperCase();
    }
  }
}
