// lib/presentation/observers/telemetry_provider_observer.dart
// Serenut OS — Riverpod Telemetry & Diagnostics Observer
// Captures unhandled provider failures and AsyncError states across all controllers
// and routes them to TelemetryService for automatic VPS reporting.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/services/telemetry_service.dart';

class TelemetryProviderObserver extends ProviderObserver {
  final TelemetryService _telemetry;

  TelemetryProviderObserver({TelemetryService? telemetry})
      : _telemetry = telemetry ?? TelemetryService();

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    super.providerDidFail(provider, error, stackTrace, container);

    final providerName = provider.name ?? provider.runtimeType.toString();
    _telemetry.logError(
      error,
      stackTrace,
      context: 'Riverpod:$providerName',
      level: LogLevel.error,
    );
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    super.didUpdateProvider(provider, previousValue, newValue, container);

    // Capture mutations using AsyncValue.guard or setting AsyncError
    if (newValue is AsyncError) {
      final prevError = previousValue is AsyncError ? previousValue.error : null;
      // Prevent duplicate logging if state hasn't changed its error
      if (identical(prevError, newValue.error)) return;

      final providerName = provider.name ?? provider.runtimeType.toString();
      _telemetry.logError(
        newValue.error,
        newValue.stackTrace,
        context: 'RiverpodState:$providerName',
        level: LogLevel.error,
      );
    }
  }
}
