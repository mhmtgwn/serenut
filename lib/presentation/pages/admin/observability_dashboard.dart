// lib/presentation/pages/admin/observability_dashboard.dart
// Serenut POS — System Observability Dashboard
// Backend: ObservabilityService.getSystemHealthMetrics() — sıfır değişiklik
// Created: Phase 5 — 01 Jul 2026

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/services/observability_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/providers/repository_providers.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kBgColor = Color(0xFF0D1117); // GitHub dark
const _kCardBg = Color(0xFF161B22);
const _kBorderColor = Color(0xFF30363D);
const _kTextPrimary = Color(0xFFE6EDF3);
const _kTextSecondary = Color(0xFF8B949E);
const _kGreen = Color(0xFF3FB950);
const _kRed = Color(0xFFF85149);
const _kAmber = Color(0xFFD29922);
const _kBlue = Color(0xFF58A6FF);
const _kPurple = Color(0xFFBC8CFF);

// ── Providers ─────────────────────────────────────────────────────────────────

final _healthMetricsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final transactionRepo =
      await ref.watch(financialTransactionRepositoryProvider.future);
  final service = ObservabilityService(transactionRepository: transactionRepo);
  return service.getSystemHealthMetrics();
});

final _recentLogsProvider =
    FutureProvider.autoDispose<List<TelemetryEvent>>((ref) async {
  return TelemetryService().getEventsByLevel(LogLevel.warning);
});

// ── Dashboard ─────────────────────────────────────────────────────────────────

class ObservabilityDashboard extends ConsumerStatefulWidget {
  const ObservabilityDashboard({super.key});

  @override
  ConsumerState<ObservabilityDashboard> createState() =>
      _ObservabilityDashboardState();
}

class _ObservabilityDashboardState
    extends ConsumerState<ObservabilityDashboard> {
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Auto-refresh every 30 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        ref.invalidate(_healthMetricsProvider);
        ref.invalidate(_recentLogsProvider);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(_healthMetricsProvider);
    final logsAsync = ref.watch(_recentLogsProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kCardBg,
        foregroundColor: _kTextPrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.15),
                border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: _kGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Sistem Sağlık Durumu',
              style: TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 17),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kTextSecondary),
            onPressed: () {
              ref.invalidate(_healthMetricsProvider);
              ref.invalidate(_recentLogsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kGreen,
        backgroundColor: _kCardBg,
        onRefresh: () async {
          ref.invalidate(_healthMetricsProvider);
          ref.invalidate(_recentLogsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Last Refresh ────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Son güncelleme: ${DateFormat('HH:mm:ss').format(DateTime.now())}',
                style: const TextStyle(color: _kTextSecondary, fontSize: 10),
              ),
            ),
            const SizedBox(height: 8),

            // ── Health Metrics ──────────────────────────────────────────────
            metricsAsync.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _ErrorCard(message: e.toString()),
              data: (metrics) => _buildMetricsGrid(metrics),
            ),
            const SizedBox(height: 16),

            // ── System Status Indicators ────────────────────────────────────
            metricsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (metrics) => _buildStatusIndicators(metrics),
            ),
            const SizedBox(height: 16),

            // ── Recent Log Events ───────────────────────────────────────────
            _buildSectionHeader('📋 SON UYARI/HATA OLAYLARI'),
            const SizedBox(height: 8),
            logsAsync.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _ErrorCard(message: e.toString()),
              data: (events) => _buildEventLog(events),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Metrics Grid ──────────────────────────────────────────────────────────

  Widget _buildMetricsGrid(Map<String, dynamic> metrics) {
    final driftRate = (metrics['drift_rate'] as num?)?.toDouble() ?? 0.0;
    final failureRate =
        (metrics['sync_failure_rate'] as num?)?.toDouble() ?? 0.0;
    final anomalyCount = (metrics['anomaly_count'] as int?) ?? 0;
    final totalTx = (metrics['total_transactions'] as int?) ?? 0;
    final syncSuccess = (metrics['sync_success_count'] as int?) ?? 0;
    final syncFail = (metrics['sync_failure_count'] as int?) ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _MetricCard(
          label: 'Drift Rate',
          value: '${(driftRate * 100).toStringAsFixed(2)}%',
          icon: Icons.sync_alt_rounded,
          color: driftRate > 0.1
              ? _kRed
              : driftRate > 0.05
                  ? _kAmber
                  : _kGreen,
          sublabel: driftRate > 0.1 ? '⚠️ Yüksek' : '✓ Normal',
          tooltip: 'Lamport clock / fiziksel zaman sapması oranı',
        ),
        _MetricCard(
          label: 'Sync Başarısızlık',
          value: '${(failureRate * 100).toStringAsFixed(1)}%',
          icon: Icons.cloud_off_rounded,
          color: failureRate > 0.2
              ? _kRed
              : failureRate > 0.1
                  ? _kAmber
                  : _kGreen,
          sublabel: 'S:$syncSuccess F:$syncFail',
          tooltip: 'Toplam sync denemelerine oranla başarısız olanlar',
        ),
        _MetricCard(
          label: 'Anomali Sayısı',
          value: '$anomalyCount',
          icon: Icons.security_rounded,
          color: anomalyCount > 0 ? _kRed : _kGreen,
          sublabel: anomalyCount > 0 ? '🚨 İnceleme Gerekli' : '✓ Temiz',
          tooltip: 'Güvenlik anomalisi tespit edilen event sayısı',
        ),
        _MetricCard(
          label: 'Toplam İşlem',
          value: '$totalTx',
          icon: Icons.receipt_long_rounded,
          color: _kBlue,
          sublabel: 'Ledger kayıtları',
          tooltip: 'Sistemdeki toplam finansal işlem sayısı',
        ),
      ],
    );
  }

  // ── Status Indicators ─────────────────────────────────────────────────────

  Widget _buildStatusIndicators(Map<String, dynamic> metrics) {
    final driftRate = (metrics['drift_rate'] as num?)?.toDouble() ?? 0.0;
    final failureRate =
        (metrics['sync_failure_rate'] as num?)?.toDouble() ?? 0.0;
    final anomalyCount = (metrics['anomaly_count'] as int?) ?? 0;

    final indicators = [
      _StatusIndicator(
        label: 'Ledger Bütünlüğü',
        isHealthy: driftRate < 0.05,
        detail: driftRate < 0.05
            ? 'Yerel ve bulut zamanı uyumlu (Veri bütünlüğü garantilendi)'
            : 'Zaman sapması algılandı (Bütünlük kontrolü önerilir)',
      ),
      _StatusIndicator(
        label: 'Senkronizasyon',
        isHealthy: failureRate < 0.1,
        detail: failureRate < 0.1
            ? 'Bulut senkronizasyonu aktif ve güvende'
            : 'Senkronizasyon bekleniyor (İnternet bağlantısını kontrol edin)',
      ),
      _StatusIndicator(
        label: 'Güvenlik',
        isHealthy: anomalyCount == 0,
        detail: anomalyCount == 0
            ? 'Veri anomalisi tespit edilmedi (İşlemler doğruluğu onaylı)'
            : 'Şüpheli kayıtlar bulundu (IT incelemesi önerilir)',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SISTEM DURUMU',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          ...indicators.map((ind) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ind.isHealthy ? _kGreen : _kRed,
                        boxShadow: [
                          BoxShadow(
                            color: (ind.isHealthy ? _kGreen : _kRed)
                                .withValues(alpha: 0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      ind.label,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      ind.detail,
                      style: TextStyle(
                        color: ind.isHealthy ? _kGreen : _kRed,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Event Log ─────────────────────────────────────────────────────────────

  Widget _buildEventLog(List<TelemetryEvent> events) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorderColor),
        ),
        child: const Center(
          child: Text(
            'Uyarı veya hata olayı bulunmuyor ✓',
            style: TextStyle(color: _kTextSecondary, fontSize: 13),
          ),
        ),
      );
    }

    final recentEvents = events.reversed.take(20).toList();

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: recentEvents.asMap().entries.map((entry) {
          final event = entry.value;
          final isLast = entry.key == recentEvents.length - 1;
          final levelColor = switch (event.level) {
            LogLevel.critical => _kRed,
            LogLevel.error => const Color(0xFFF85149),
            LogLevel.warning => _kAmber,
            _ => _kTextSecondary,
          };

          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.level.emoji,
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.event,
                            style: TextStyle(
                              color: levelColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            DateFormat('dd.MM HH:mm:ss')
                                .format(event.timestamp),
                            style: const TextStyle(
                              color: _kTextSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast) const Divider(height: 1, color: _kBorderColor),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _kTextSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Metric Card ───────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String sublabel;
  final String tooltip;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.sublabel,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              sublabel,
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Indicator ──────────────────────────────────────────────────────────

class _StatusIndicator {
  final String label;
  final bool isHealthy;
  final String detail;
  const _StatusIndicator({
    required this.label,
    required this.isHealthy,
    required this.detail,
  });
}

// ── Loading / Error Cards ─────────────────────────────────────────────────────

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(_kGreen),
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _kRed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: _kRed, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
