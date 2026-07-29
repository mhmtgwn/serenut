// lib/presentation/pages/onboarding/bootstrap_loading_view.dart
// Serenut OS — Automated Initial Bootstrap Loading View (Sprint 2)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/service_providers.dart';
import '../../../providers/audit_provider.dart';
import '../../widgets/branded_splash_screen.dart';

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
    return BrandedSplashScreen(
      status: 'İlk kurulum hazırlanıyor',
      detail: _statusText,
      progress: _errorMsg == null ? _progress / 100 : null,
      error: _errorMsg,
      onRetry: _errorMsg == null ? null : _startSync,
    );
  }
}
