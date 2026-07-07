// lib/presentation/pages/sync_conflict_page.dart
// Serenut POS — Senkronizasyon Çakışma Çözüm Ekranı
// Backend: SyncStateMachine + SyncTraceService — sıfır değişiklik
// Created: Phase 4 — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:serenutos/domain/services/sync_trace_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kBgColor       = Color(0xFFF8FAFC);
const _kCardBg        = Colors.white;
const _kBorderColor   = Color(0xFFE2E8F0);
const _kTextPrimary   = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen         = Color(0xFF10B981);
const _kRed           = Color(0xFFEF4444);
const _kAmber         = Color(0xFFF59E0B);
const _kBlue          = Color(0xFF3B82F6);
const _kPurple        = Color(0xFF8B5CF6);
const _kGray          = Color(0xFF94A3B8);

// ── Providers ─────────────────────────────────────────────────────────────────

final _recentIncidentDetailProvider = FutureProvider.autoDispose<List<SyncIncident>>((ref) async {
  final tracer = SyncTraceService();
  return tracer.getRecentCriticals(hours: 72);
});

// ── Page ──────────────────────────────────────────────────────────────────────

class SyncConflictPage extends ConsumerWidget {
  const SyncConflictPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState    = ref.watch(syncProvider);
    final incidentsAsync = ref.watch(_recentIncidentDetailProvider);
    final recentAsync  = ref.watch(recentSessionsProvider);

    final hasActiveConflict = syncState.status == SyncStatus.error;

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Senkronizasyon Durumu',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kTextPrimary),
            onPressed: () {
              ref.invalidate(_recentIncidentDetailProvider);
              ref.invalidate(recentSessionsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kGreen,
        onRefresh: () async {
          ref.invalidate(_recentIncidentDetailProvider);
          ref.invalidate(recentSessionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Current Sync Status Card ─────────────────────────────────────
            _buildCurrentStatusCard(context, ref, syncState, hasActiveConflict),
            const SizedBox(height: 16),

            // ── Active Conflict Resolution ───────────────────────────────────
            if (hasActiveConflict) ...[
              _buildConflictResolutionCard(context, ref, syncState),
              const SizedBox(height: 16),
            ],

            // ── Recent Incidents (Son 72 saat) ───────────────────────────────
            _buildSectionHeader('SON 72 SAAT İNCİDENTLAR'),
            const SizedBox(height: 8),
            incidentsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_kAmber),
                  ),
                ),
              ),
              error: (e, _) => _buildErrorCard('İncident verileri yüklenemedi: $e'),
              data: (incidents) {
                if (incidents.isEmpty) {
                  return _buildNoIncidentsCard();
                }
                return Column(
                  children: incidents.map((inc) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _IncidentCard(incident: inc),
                  )).toList(),
                );
              },
            ),
            const SizedBox(height: 16),

            // ── Recent Sync Sessions ─────────────────────────────────────────
            _buildSectionHeader('SON SYNC OTURUMLARI'),
            const SizedBox(height: 8),
            recentAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (sessions) => _buildSessionList(sessions),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Current Status Card ────────────────────────────────────────────────────

  Widget _buildCurrentStatusCard(
    BuildContext context,
    WidgetRef ref,
    SyncState syncState,
    bool hasConflict,
  ) {
    final (color, icon, title, subtitle) = switch (syncState.status) {
      SyncStatus.idle    => (_kGray,  Icons.cloud_queue_rounded,   'Senkronizasyon Bekleniyor', 'Son işlem bekleniyor'),
      SyncStatus.syncing => (_kBlue,  Icons.sync_rounded,           'Senkronize Ediliyor...', 'Veriler sunucuya gönderiliyor'),
      SyncStatus.success => (_kGreen, Icons.cloud_done_rounded,     'Senkronize', syncState.lastSyncAt != null
          ? 'Son: ${DateFormat('dd.MM.yyyy HH:mm').format(syncState.lastSyncAt!)}'
          : 'Tüm veriler güncel'),
      SyncStatus.error   => (_kRed,   Icons.cloud_off_rounded,      'Senkronizasyon Hatası', syncState.lastError ?? 'Bilinmeyen hata'),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: syncState.status == SyncStatus.syncing
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      )
                    : Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          if (syncState.lastSyncedCount != null && syncState.lastSyncedCount! > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 14, color: _kGreen),
                  const SizedBox(width: 6),
                  Text(
                    '${syncState.lastSyncedCount} kayıt senkronize edildi',
                    style: const TextStyle(
                        color: _kGreen, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
          if (hasConflict) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => ref.read(syncProvider.notifier).triggerSync(),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Yeniden Dene'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Conflict Resolution Card ───────────────────────────────────────────────

  Widget _buildConflictResolutionCard(
    BuildContext context,
    WidgetRef ref,
    SyncState syncState,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: _kAmber, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Otomatik Çözüm Seçeneği',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _kTextPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sunucu verisi her zaman doğru kabul edilir (server-authoritative)',
                      style: TextStyle(color: _kTextSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: _kBorderColor),
          const SizedBox(height: 10),
          const Text(
            'Bu sistem fintech sınıfı immutable ledger kullanır. '
            'Çakışmalar sunucu verisi esas alınarak otomatik çözülür. '
            'Tüm işlemler audit log\'a kaydedilir.',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showConflictDetails(context, syncState),
                  icon: const Icon(Icons.info_outline_rounded, size: 16),
                  label: const Text('Detaylar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPurple,
                    side: const BorderSide(color: _kPurple),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => ref.read(syncProvider.notifier).triggerSync(),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Otomatik Çöz'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAmber,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showConflictDetails(BuildContext context, SyncState syncState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.sync_problem_rounded, color: _kAmber, size: 22),
            SizedBox(width: 8),
            Text('Çakışma Detayı',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (syncState.lastError != null) ...[
              const Text('Hata Mesajı:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  syncState.lastError!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _kRed,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              '⚡ Çözüm Stratejisi:\n'
              'Sistem, server-authoritative model kullanır. '
              'Yerel değişiklikler sunucu ile merge edilir. '
              'Hiçbir veri kaybolmaz — tüm işlemler loglanır.',
              style: TextStyle(fontSize: 12, color: _kTextSecondary, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // ── Session List ───────────────────────────────────────────────────────────

  Widget _buildSessionList(List<String> sessions) {
    if (sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorderColor),
        ),
        child: const Center(
          child: Text(
            'Henüz kayıtlı oturum yok',
            style: TextStyle(color: _kTextSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: sessions.take(10).toList().asMap().entries.map((entry) {
          final isLast = entry.key == sessions.take(10).length - 1;
          final sessionId = entry.value;
          return Column(
            children: [
              ListTile(
                dense: true,
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.sync_rounded, size: 16, color: _kBlue),
                ),
                title: Text(
                  sessionId.substring(0, sessionId.length > 16 ? 16 : sessionId.length),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _kTextPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Sync oturumu',
                  style: TextStyle(fontSize: 10, color: _kTextSecondary),
                ),
                trailing: const Icon(Icons.chevron_right_rounded,
                    size: 16, color: _kTextSecondary),
              ),
              if (!isLast) const Divider(height: 1, indent: 56),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildNoIncidentsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: _kGreen, size: 32),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Son 72 saatte incident yok',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kGreen,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Sistem sağlıklı çalışıyor. Tüm sync işlemleri başarılı.',
                  style: TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kRed.withValues(alpha: 0.2)),
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: _kTextSecondary,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Incident Card ─────────────────────────────────────────────────────────────

class _IncidentCard extends StatelessWidget {
  final SyncIncident incident;

  const _IncidentCard({required this.incident});

  @override
  Widget build(BuildContext context) {
    final color = incident.hasCritical ? _kRed : _kAmber;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  incident.hasCritical
                      ? Icons.error_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fingerprint: ${incident.fingerprint}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kTextPrimary,
                      ),
                    ),
                    Text(
                      DateFormat('dd.MM HH:mm').format(incident.firstSeen),
                      style: const TextStyle(
                          color: _kTextSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  incident.hasCritical ? 'KRİTİK' : 'HATA',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: incident.events.take(3).map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${e.level.emoji} ${e.event}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: _kTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )).toList(),
            ),
          ),
          if (incident.events.length > 3) ...[
            const SizedBox(height: 4),
            Text(
              '+${incident.events.length - 3} daha fazla olay',
              style: const TextStyle(color: _kTextSecondary, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}
