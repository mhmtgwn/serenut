// lib/presentation/pages/onboarding/bootstrap_loading_view.dart
// Serenut OS — Automated Initial Bootstrap Loading View (Sprint 2)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/service_providers.dart';
import '../../../providers/audit_provider.dart';

class BootstrapLoadingView extends ConsumerStatefulWidget {
  final VoidCallback onCompleted;

  const BootstrapLoadingView({super.key, required this.onCompleted});

  @override
  ConsumerState<BootstrapLoadingView> createState() =>
      _BootstrapLoadingViewState();
}

class _BootstrapLoadingViewState extends ConsumerState<BootstrapLoadingView> {
  double _progress = 0.0;
  String _statusText = 'Başlatılıyor...';
  String? _errorMsg;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSync();
    });
  }

  Future<void> _startSync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _errorMsg = null;
    });

    try {
      final bootstrapService = ref.read(bootstrapSyncServiceProvider);
      await bootstrapService.runBootstrap((progress, statusText) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _statusText = statusText;
          });
        }
      });

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _progress = 100.0;
        });
        // Introduce a slight delay for smooth visual transition
        await Future.delayed(const Duration(milliseconds: 800));
        widget.onCompleted();
      }
    } catch (e, st) {
      // Log bootstrap failure to audit trail for telemetry / support diagnostics
      try {
        final audit = await ref.read(auditServiceProvider.future);
        await audit.logEvent(
          eventType: 'bootstrap_sync_failed',
          entityType: 'system',
          entityId: 'bootstrap',
          newValue: e.toString(),
          notes:
              'Bootstrap senkronizasyonu başarısız: ${e.toString()}\n${st.toString().substring(0, st.toString().length.clamp(0, 500))}',
        );
      } catch (_) {
        // Audit service may not be available during very early onboarding — fail silently
      }
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _errorMsg = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surface.withAlpha(200),
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32.0, vertical: 40.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Loading Animation Header
                      if (_errorMsg == null)
                        const SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            strokeWidth: 6,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.green),
                          ),
                        )
                      else
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 80,
                        ),
                      const SizedBox(height: 32),

                      Text(
                        _errorMsg == null
                            ? 'Sistem Hazırlanıyor'
                            : 'Bağlantı Hatası',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),

                      Text(
                        _errorMsg == null
                            ? 'Lütfen bekleyin, Serenut OS ilk kurulum verileri senkronize ediliyor.'
                            : 'Sunucuya bağlanırken bir hata oluştu. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.textTheme.bodyMedium?.color?.withAlpha(180),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      if (_errorMsg == null) ...[
                        // Progress Bar & Percentage Indicators
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progress / 100,
                            minHeight: 12,
                            backgroundColor:
                                theme.colorScheme.primary.withAlpha(40),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _statusText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '%${_progress.toStringAsFixed(0)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Error Details Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.redAccent.withAlpha(60)),
                          ),
                          child: Text(
                            _errorMsg!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.redAccent,
                              fontFamily: 'monospace',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Retry Button
                        ElevatedButton.icon(
                          onPressed: _startSync,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tekrar Dene'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
