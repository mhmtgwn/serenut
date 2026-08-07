import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/infrastructure/services/shared_hardware_service.dart';

class PrintQueuePage extends ConsumerStatefulWidget {
  const PrintQueuePage({super.key});

  @override
  ConsumerState<PrintQueuePage> createState() => _PrintQueuePageState();
}

class _PrintQueuePageState extends ConsumerState<PrintQueuePage> {
  bool _loading = true;
  String? _error;
  List<PrintJobRecord> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ref.invalidate(sharedHardwareJobsProvider);
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final jobs = await ref.read(printingRepositoryProvider).getJobs();
      if (mounted) setState(() => _jobs = jobs);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _retry(PrintJobRecord job) async {
    await ref.read(printingRepositoryProvider).retryJob(job.id);
    await ref.read(printingRuntimeProvider).processNow();
    await _load();
  }

  Future<void> _cancel(PrintJobRecord job) async {
    await ref.read(printingRepositoryProvider).cancelJob(job.id);
    await _load();
  }

  Future<void> _resolve(PrintJobRecord job, bool printed) async {
    await ref
        .read(printingRepositoryProvider)
        .confirmUncertainDelivery(job.id, printed: printed);
    if (!printed) await ref.read(printingRuntimeProvider).processNow();
    await _load();
  }

  Future<void> _sharedAction(
    SharedHardwareJobSummary job,
    String action,
  ) async {
    if (action == 'confirmNotPrinted') {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tekrar yazdırılsın mı?'),
          content: Text(
            '${job.hardwareName} çıktısının oluşmadığını doğruluyorsunuz. '
            'İş yeniden kuyruğa alınacak.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Tekrar yazdır'),
            ),
          ],
        ),
      );
      if (approved != true) return;
    }
    try {
      await ref.read(sharedHardwareServiceProvider).actOnJob(job.id, action);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ortak iş güncellenemedi: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(printingRuntimeSnapshotProvider);
    final sharedJobs = ref.watch(sharedHardwareJobsProvider);
    final runtimeError = runtime.value?.error ?? runtime.error?.toString();
    ref.listen(printingRuntimeSnapshotProvider, (_, next) {
      if (next.hasValue) _load();
    });
    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        title: const Text('Yazdırma Kuyruğu'),
        actions: [
          IconButton(
              onPressed: _load,
              tooltip: 'Yenile',
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          if (runtimeError != null)
            Container(
              width: double.infinity,
              color: POSColors.redLight,
              padding: const EdgeInsets.all(12),
              child: Text(
                'Yazdırma altyapısı çalışmıyor: $runtimeError',
                style: const TextStyle(color: POSColors.red),
              ),
            ),
          sharedJobs.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (_, __) => const SizedBox.shrink(),
            data: (jobs) => jobs.isEmpty
                ? const SizedBox.shrink()
                : _SharedJobsPanel(
                    jobs: jobs.take(5).toList(),
                    onAction: _sharedAction,
                  ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Kuyruk yüklenemedi: $_error'))
                    : _jobs.isEmpty
                        ? const _EmptyQueue()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _jobs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, index) => _JobCard(
                                job: _jobs[index],
                                onRetry: () => _retry(_jobs[index]),
                                onCancel: () => _cancel(_jobs[index]),
                                onPrinted: () => _resolve(_jobs[index], true),
                                onNotPrinted: () =>
                                    _resolve(_jobs[index], false),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _SharedJobsPanel extends StatelessWidget {
  final List<SharedHardwareJobSummary> jobs;
  final Future<void> Function(SharedHardwareJobSummary, String) onAction;

  const _SharedJobsPanel({required this.jobs, required this.onAction});

  @override
  Widget build(BuildContext context) => ExpansionTile(
        initiallyExpanded: jobs.any((job) =>
            job.state == 'queued' ||
            job.state == 'claimed' ||
            job.state == 'retry_wait' ||
            job.state == 'failed'),
        leading: const Icon(Icons.cloud_queue_rounded),
        title: const Text('Ortak yazdırma işleri'),
        subtitle: Text('${jobs.length} son işlem'),
        children: jobs.map((job) {
          final presentation = _sharedState(job.state);
          return ListTile(
            dense: true,
            leading: Icon(presentation.$2, color: presentation.$3),
            title: Text(job.hardwareName),
            subtitle: Text([
              job.requestedHere ? 'Bu cihazdan gönderildi' : 'Bu cihaz bastı',
              DateFormat('dd.MM HH:mm:ss').format(job.createdAt),
              if (job.errorMessage != null) job.errorMessage!,
            ].join(' · ')),
            trailing: _SharedJobActions(
              job: job,
              label: presentation.$1,
              onAction: onAction,
            ),
          );
        }).toList(growable: false),
      );
}

class _SharedJobActions extends StatelessWidget {
  final SharedHardwareJobSummary job;
  final String label;
  final Future<void> Function(SharedHardwareJobSummary, String) onAction;

  const _SharedJobActions({
    required this.job,
    required this.label,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (job.state == 'failed') {
      return FilledButton.tonalIcon(
        onPressed: () => onAction(job, 'retry'),
        icon: const Icon(Icons.replay_rounded),
        label: const Text('Tekrar dene'),
      );
    }
    if (job.state == 'queued' || job.state == 'retry_wait') {
      return TextButton(
        onPressed: () => onAction(job, 'cancel'),
        child: const Text('İptal et'),
      );
    }
    if (job.state == 'requires_confirmation') {
      return PopupMenuButton<String>(
        tooltip: 'Fiziksel sonucu doğrula',
        onSelected: (action) => onAction(job, action),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'confirmPrinted',
            child: Text('Çıktı basıldı'),
          ),
          PopupMenuItem(
            value: 'confirmNotPrinted',
            child: Text('Çıktı oluşmadı'),
          ),
        ],
        child: const Chip(label: Text('Sonucu doğrula')),
      );
    }
    return Text(label);
  }
}

(String, IconData, Color) _sharedState(String state) => switch (state) {
      'queued' => ('Bekliyor', Icons.schedule_rounded, POSColors.amber),
      'claimed' || 'executing' => (
          'İşleniyor',
          Icons.sync_rounded,
          POSColors.blue
        ),
      'retry_wait' => (
          'Tekrar denenecek',
          Icons.replay_rounded,
          POSColors.amber
        ),
      'succeeded' => (
          'Yazdırıldı',
          Icons.check_circle_rounded,
          POSColors.green
        ),
      'requires_confirmation' => (
          'Kontrol gerekli',
          Icons.help_rounded,
          POSColors.amber
        ),
      'failed' => ('Başarısız', Icons.error_rounded, POSColors.red),
      'cancelled' => (
          'İptal edildi',
          Icons.cancel_rounded,
          POSColors.textSecondary
        ),
      _ => (state, Icons.info_rounded, POSColors.textSecondary),
    };

class _JobCard extends StatelessWidget {
  final PrintJobRecord job;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onPrinted;
  final VoidCallback onNotPrinted;

  const _JobCard(
      {required this.job,
      required this.onRetry,
      required this.onCancel,
      required this.onPrinted,
      required this.onNotPrinted});

  @override
  Widget build(BuildContext context) {
    final presentation = _state(job.state);
    final retryable = const [
      PrintJobState.failed,
      PrintJobState.rejected,
      PrintJobState.cancelled
    ].contains(job.state);
    final cancellable = const [PrintJobState.queued, PrintJobState.retryWait]
        .contains(job.state);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_kindIcon(job.kind), color: presentation.$2),
            const SizedBox(width: 10),
            Expanded(
                child: Text(_kindLabel(job.kind),
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Chip(label: Text(presentation.$1)),
          ]),
          const SizedBox(height: 8),
          Text('Cihaz: ${job.deviceId} · Kopya: ${job.copies}'),
          Text(DateFormat('dd.MM.yyyy HH:mm:ss').format(job.createdAt),
              style: const TextStyle(color: POSColors.textSecondary)),
          if (job.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(job.errorMessage!,
                style: const TextStyle(color: POSColors.red)),
          ],
          if (job.state == PrintJobState.awaitingUserCheck) ...[
            const SizedBox(height: 10),
            const Text('Fiziksel çıktı oluştu mu?',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              TextButton(
                  onPressed: onNotPrinted,
                  child: const Text('Hayır, tekrar dene')),
              const Spacer(),
              FilledButton(
                  onPressed: onPrinted, child: const Text('Evet, basıldı')),
            ]),
          ] else if (retryable || cancellable) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (cancellable)
                TextButton(onPressed: onCancel, child: const Text('İptal et')),
              if (retryable)
                FilledButton.tonal(
                    onPressed: onRetry, child: const Text('Tekrar dene')),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.print_disabled_rounded,
              size: 56, color: POSColors.textSecondary),
          SizedBox(height: 12),
          Text('Yazdırma kuyruğu boş'),
        ]),
      );
}

(String, Color) _state(PrintJobState state) => switch (state) {
      PrintJobState.created => ('Oluşturuldu', POSColors.textSecondary),
      PrintJobState.queued => ('Bekliyor', POSColors.amber),
      PrintJobState.rendering => ('Hazırlanıyor', POSColors.blue),
      PrintJobState.sending => ('Gönderiliyor', POSColors.blue),
      PrintJobState.delivered => ('Teslim edildi', POSColors.green),
      PrintJobState.retryWait => ('Tekrar bekliyor', POSColors.amber),
      PrintJobState.awaitingUserCheck => ('Doğrulama gerekli', POSColors.amber),
      PrintJobState.confirmed => ('Doğrulandı', POSColors.green),
      PrintJobState.rejected => ('Çıktı hatalı', POSColors.red),
      PrintJobState.failed => ('Başarısız', POSColors.red),
      PrintJobState.cancelled => ('İptal edildi', POSColors.textSecondary),
    };

String _kindLabel(PrintDocumentKind kind) => switch (kind) {
      PrintDocumentKind.receipt => 'Fiş',
      PrintDocumentKind.productLabel => 'Ürün etiketi',
      PrintDocumentKind.orderLabel => 'Sipariş etiketi',
    };

IconData _kindIcon(PrintDocumentKind kind) => switch (kind) {
      PrintDocumentKind.receipt => Icons.receipt_long_rounded,
      PrintDocumentKind.productLabel => Icons.label_rounded,
      PrintDocumentKind.orderLabel => Icons.inventory_2_rounded,
    };
