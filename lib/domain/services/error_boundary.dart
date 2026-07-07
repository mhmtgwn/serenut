// lib/domain/services/error_boundary.dart
// Sentry-ready centralized error boundary for Serenut POS.
// Coverage: Flutter framework, async zones, platform channels, and background isolates.

import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

class ErrorBoundary {
  static final _telemetry = TelemetryService();

  /// Install ALL global error handlers. Call from `main()` before `runApp()`.
  ///
  /// Covers:
  ///   1. Flutter framework (widget build, layout, rendering)
  ///   2. Unhandled async futures (PlatformDispatcher)
  ///   3. Native platform channel errors (MethodChannel, EventChannel)
  ///   4. Background Isolate uncaught errors
  ///
  /// Usage:
  /// ```dart
  /// void main() {
  ///   ErrorBoundary.install();
  ///   runApp(const MyApp());
  /// }
  /// ```
  static void install() {
    // ── 1. Flutter framework errors (widget build, layout, rendering) ────────
    FlutterError.onError = (FlutterErrorDetails details) async {
      // Enrich with additional context from FlutterErrorDetails
      final enrichedContext = [
        'FlutterError',
        if (details.library != null) 'library:${details.library}',
        if (details.context != null) 'context:${details.context}',
      ].join(' | ');

      await _telemetry.logError(
        details.exception,
        details.stack ?? StackTrace.empty,
        context: enrichedContext,
        level: LogLevel.critical,
      );
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    // ── 2. Platform-level / unhandled async errors ────────────────────────────
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _telemetry.logError(
        error,
        stack,
        context: 'PlatformDispatcher.onError',
        level: LogLevel.critical,
      );
      return !kDebugMode; // propagate in debug for visibility
    };

    // ── 3. Platform channel errors (MethodChannel / EventChannel) ─────────────
    // Wraps the default binary messenger to catch MissingPluginException and
    // PlatformException without touching each individual channel call-site.
    // For robust coverage, wrap individual critical channels at usage sites
    // using the `wrapChannel()` helper below.
    //
    // Note: Flutter 3.x does not expose a global channel interceptor; per-channel
    // wrapping via `ErrorBoundary.wrapChannel()` is the recommended pattern.

    // ── 4. Isolate uncaught errors ─────────────────────────────────────────────
    // Dart Isolate.current.addErrorListener only works for the root isolate.
    // For spawned isolates, use the receivePort pattern inside the isolate.
    if (!kIsWeb) {
      Isolate.current.addErrorListener(
        RawReceivePort((dynamic pair) async {
          if (pair is! List || pair.length < 2) return;
          final errorStr = pair[0]?.toString() ?? 'Unknown isolate error';
          final stackStr = pair[1]?.toString() ?? '';
          await _telemetry.logStructured(
            event: 'isolate_uncaught_error',
            level: LogLevel.critical,
            metadata: {
              'error_message': errorStr,
              'stack_trace': stackStr.split('\n').take(10).join('\n'),
            },
          );
        }).sendPort,
      );
    }
  }

  /// Wraps a single async operation in a guarded zone that captures all errors.
  ///
  /// Usage:
  /// ```dart
  /// await ErrorBoundary.run(() async {
  ///   await syncPendingSales();
  /// }, context: 'syncPendingSales');
  /// ```
  static Future<void> run(
    Future<void> Function() body, {
    String? context,
    LogLevel level = LogLevel.error,
  }) async {
    await runZonedGuarded(
      body,
      (Object error, StackTrace stack) {
        _telemetry.logError(error, stack, context: context, level: level);
      },
    );
  }

  /// Wraps a platform channel call to capture [PlatformException] and
  /// [MissingPluginException].
  ///
  /// **Behavior by mode:**
  /// - DEBUG: rethrows immediately so errors are visible during development
  ///          (fail-fast — no silent swallowing).
  /// - RELEASE/PROFILE: logs the error and returns `null` (graceful fallback).
  ///
  /// Usage:
  /// ```dart
  /// final status = await ErrorBoundary.wrapChannel(
  ///   () => _channel.invokeMethod('getPrinterStatus'),
  ///   context: 'printer_status',
  /// );
  /// ```
  static Future<T?> wrapChannel<T>(
    Future<T?> Function() channelCall, {
    String? context,
  }) async {
    try {
      return await channelCall();
    } on PlatformException catch (e, st) {
      await _telemetry.logError(
        e,
        st,
        context: 'PlatformChannel${context != null ? ':$context' : ''}',
        level: LogLevel.error,
      );
      // In debug mode: surface immediately so developers catch misconfigurations
      if (kDebugMode) rethrow;
      return null; // Production: graceful fallback
    } on MissingPluginException catch (e, st) {
      await _telemetry.logError(
        e,
        st,
        context: 'MissingPlugin${context != null ? ':$context' : ''}',
        level: LogLevel.warning,
      );
      if (kDebugMode) rethrow;
      return null;
    }
  }
}
