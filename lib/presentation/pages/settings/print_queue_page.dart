// lib/presentation/pages/settings/print_queue_page.dart
// Serenut POS — Yazıcı Kuyruğu İzleme Ekranı
// Backend: PersistentPrintQueue — crash-safe, retry logic bağlı
// Created: Phase 4 — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:serenutos/providers/service_providers.dart';

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
const _kGray          = Color(0xFF94A3B8);

// ── Providers ─────────────────────────────────────────────────────────────────

final _printJobsProvider = FutureProvider.autoDispose<List<PersistedPrintJob>>((ref) async {
  final queue = ref.watch(persistentPrintQueueProvider);
  return queue.loadAll();
});

// ── Page ──────────────────────────────────────────────────────────────────────

class PrintQueuePage extends ConsumerStatefulWidget {
  const PrintQueuePage({super.key});

  @override
  ConsumerState<PrintQueuePage> createState() => _PrintQueuePageState();
}

class _PrintQueuePageState extends ConsumerState<PrintQueuePage> {
  String _filterStatus = 'all'; // all | pending | success | failed | abandoned

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(_printJobsProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Yazıcı Kuyruğu',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kTextPrimary),
            tooltip: 'Yenile',
            onPressed: () => ref.invalidate(_printJobsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Status Summary Banner ───────────────────────────────────────────
          jobsAsync.when(
            data: (jobs) => _buildSummaryBanner(jobs),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // ── Filter Chips ────────────────────────────────────────────────────
          _buildFilterChips(),

          // ── Job List ────────────────────────────────────────────────────────
          Expanded(
            child: jobsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_kGreen),
                ),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: _kRed),
                    const SizedBox(height: 12),
                    Text('Kuyruk yüklenemedi: $e',
                        style: const TextStyle(color: _kTextSecondary)),
                  ],
                ),
              ),
              data: (jobs) {
                final filtered = _filterJobs(jobs);
                if (filtered.isEmpty) return _buildEmptyState();
                return RefreshIndicator(
                  color: _kGreen,
                  onRefresh: () async => ref.invalidate(_printJobsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PrintJobCard(
                      job: filtered[i],
                      onRetry: () => _retryJob(filtered[i]),
                      onDelete: () => _deleteJob(filtered[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: jobsAsync.maybeWhen(
        data: (jobs) {
          final hasPending = jobs.any((j) => j.status == PrintJobStatus.pending);
          final hasCompleted = jobs.any(
            (j) => j.status == PrintJobStatus.success || j.status == PrintJobStatus.abandoned,
          );
          if (!hasPending && !hasCompleted) return null;
          return _buildBottomActions(hasPending, hasCompleted);
        },
        orElse: () => null,
      ),
    );
  }

  // ── Summary Banner ─────────────────────────────────────────────────────────

  Widget _buildSummaryBanner(List<PersistedPrintJob> jobs) {
    final pending   = jobs.where((j) => j.status == PrintJobStatus.pending).length;
    final success   = jobs.where((j) => j.status == PrintJobStatus.success).length;
    final failed    = jobs.where((j) => j.status == PrintJobStatus.failed).length;
    final abandoned = jobs.where((j) => j.status == PrintJobStatus.abandoned).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _SummaryChip(count: pending,   label: 'Bekliyor',  color: _kAmber),
          const SizedBox(width: 8),
          _SummaryChip(count: success,   label: 'Başarılı',  color: _kGreen),
          const SizedBox(width: 8),
          _SummaryChip(count: failed,    label: 'Başarısız', color: _kRed),
          const SizedBox(width: 8),
          _SummaryChip(count: abandoned, label: 'İptal',     color: _kGray),
        ],
      ),
    );
  }

  // ── Filter Chips ───────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    const filters = [
      ('all', 'Tümü'),
      ('pending', 'Bekliyor'),
      ('success', 'Başarılı'),
      ('failed', 'Başarısız'),
      ('abandoned', 'İptal'),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isActive = _filterStatus == f.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filterStatus = f.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? _kBlue : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    f.$2,
                    style: TextStyle(
                      color: isActive ? Colors.white : _kTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Bottom Actions ─────────────────────────────────────────────────────────

  Widget _buildBottomActions(bool hasPending, bool hasCompleted) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorderColor)),
      ),
      child: Row(
        children: [
          if (hasPending)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _retryAllPending,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Tümünü Yeniden Dene'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBlue,
                  side: const BorderSide(color: _kBlue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          if (hasPending && hasCompleted) const SizedBox(width: 10),
          if (hasCompleted)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _clearCompleted,
                icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                label: const Text('Tamamlananları Temizle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  foregroundColor: _kTextSecondary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _retryJob(PersistedPrintJob job) async {
    final queue = ref.read(persistentPrintQueueProvider);
    await queue.resetStuckJobs();
    ref.invalidate(_printJobsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İş yeniden kuyruğa alındı'),
          backgroundColor: _kBlue,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteJob(PersistedPrintJob job) async {
    final queue = ref.read(persistentPrintQueueProvider);
    await queue.markFailed(job.id, error: 'Kullanıcı tarafından iptal edildi');
    ref.invalidate(_printJobsProvider);
  }

  Future<void> _retryAllPending() async {
    final queue = ref.read(persistentPrintQueueProvider);
    final jobs = await queue.loadPending();
    await queue.resetStuckJobs();
    ref.invalidate(_printJobsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${jobs.length} iş yeniden denemeye alındı'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearCompleted() async {
    final queue = ref.read(persistentPrintQueueProvider);
    await queue.clearCompleted();
    ref.invalidate(_printJobsProvider);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<PersistedPrintJob> _filterJobs(List<PersistedPrintJob> jobs) {
    if (_filterStatus == 'all') return jobs.reversed.toList();
    return jobs.reversed
        .where((j) => j.status.name == _filterStatus)
        .toList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.print_rounded, size: 40, color: _kGray),
          ),
          const SizedBox(height: 16),
          const Text(
            'Yazıcı kuyruğu boş',
            style: TextStyle(
              color: _kTextPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Satış fişi basıldığında burada görünür.',
            style: TextStyle(color: _kTextSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Print Job Card ────────────────────────────────────────────────────────────

class _PrintJobCard extends StatelessWidget {
  final PersistedPrintJob job;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _PrintJobCard({
    required this.job,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final style = _jobStyle(job.status);

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: style.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: style.bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(style.icon, size: 20, color: style.fgColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _kTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd.MM.yyyy HH:mm').format(job.createdAt),
                        style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: style.bgColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    style.label,
                    style: TextStyle(
                      color: style.fgColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (job.retryCount > 0 || job.lastError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.replay_rounded, size: 14, color: _kAmber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        job.lastError ?? 'Deneme sayısı: ${job.retryCount}/5',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (job.status == PrintJobStatus.pending ||
                job.status == PrintJobStatus.failed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.replay_rounded, size: 15),
                      label: const Text('Yeniden Dene'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBlue,
                        side: const BorderSide(color: _kBlue),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 15),
                    label: const Text('İptal'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kRed,
                      side: const BorderSide(color: _kRed),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  _JobStyle _jobStyle(PrintJobStatus status) {
    switch (status) {
      case PrintJobStatus.pending:
        return const _JobStyle(
          icon: Icons.pending_rounded, label: 'Bekliyor',
          bgColor: Color(0xFFFFFBEB), fgColor: _kAmber, borderColor: Color(0xFFFDE68A),
        );
      case PrintJobStatus.printing:
        return const _JobStyle(
          icon: Icons.print_rounded, label: 'Basılıyor',
          bgColor: Color(0xFFEFF6FF), fgColor: _kBlue, borderColor: Color(0xFFBFDBFE),
        );
      case PrintJobStatus.success:
        return const _JobStyle(
          icon: Icons.check_circle_rounded, label: 'Başarılı',
          bgColor: Color(0xFFECFDF5), fgColor: _kGreen, borderColor: Color(0xFFA7F3D0),
        );
      case PrintJobStatus.failed:
        return const _JobStyle(
          icon: Icons.error_rounded, label: 'Başarısız',
          bgColor: Color(0xFFFEF2F2), fgColor: _kRed, borderColor: Color(0xFFFECACA),
        );
      case PrintJobStatus.abandoned:
        return const _JobStyle(
          icon: Icons.cancel_rounded, label: 'İptal Edildi',
          bgColor: Color(0xFFF8FAFC), fgColor: _kGray, borderColor: _kBorderColor,
        );
    }
  }
}

class _JobStyle {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color fgColor;
  final Color borderColor;
  const _JobStyle({
    required this.icon, required this.label,
    required this.bgColor, required this.fgColor, required this.borderColor,
  });
}

// ── Summary Chip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _SummaryChip({required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text('$count',
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
          Text(label,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
