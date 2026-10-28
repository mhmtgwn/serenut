// lib/domain/services/error_boundary.dart
// Sentry-ready centralized error boundary for Serenut OS.
// Coverage: Flutter framework, async zones, platform channels, and background isolates.

import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

class ErrorBoundary {
  static final _telemetry = TelemetryService();

  static String _generateErrorReference(String error) {
    final hash =
        (error.hashCode.abs() % 0xFFFFFF).toRadixString(16).toUpperCase();
    return 'ERR-${hash.padLeft(6, '0')}';
  }

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
      final isMissingPlugin = details.exception is MissingPluginException;
      final isLayoutOverflow =
          details.exceptionAsString().contains('RenderFlex overflowed');
      final refCode = _generateErrorReference(details.exception.toString());

      // Enrich with additional context from FlutterErrorDetails
      final enrichedContext = [
        'FlutterError',
        if (details.library != null) 'library:${details.library}',
        if (details.context != null) 'context:${details.context}',
      ].join(' | ');

      final effectiveStack = (details.stack != null &&
              details.stack.toString().trim().isNotEmpty)
          ? details.stack!
          : StackTrace.fromString(details.toString());

      await _telemetry.logError(
        details.exception,
        effectiveStack,
        context: enrichedContext,
        correlationId: refCode,
        level: (isMissingPlugin || isLayoutOverflow)
            ? LogLevel.warning
            : LogLevel.critical,
      );

      // Do not show red screen for MissingPluginException
      if (kDebugMode && !isMissingPlugin) {
        FlutterError.presentError(details);
      }
    };

    // User-friendly fallback widget when a widget build fails (replaces default red/grey box)
    ErrorWidget.builder = (FlutterErrorDetails details) {
      final refCode = _generateErrorReference(details.exception.toString());
      return Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.2)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined,
                    color: Color(0xFF0F766E), size: 36),
                const SizedBox(height: 8),
                const Text(
                  'Arayüz Yüklenirken Bir Aksaklık Oluştu',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Hata kaydı otomatik olarak teknik ekibimize iletildi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    'Referans: $refCode',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    };

    // ── 2. Platform-level / unhandled async errors ────────────────────────────
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final isMissingPlugin = error is MissingPluginException;
      final refCode = _generateErrorReference(error.toString());

      _telemetry.logError(
        error,
        stack,
        context: 'PlatformDispatcher.onError',
        correlationId: refCode,
        level: isMissingPlugin ? LogLevel.warning : LogLevel.critical,
      );

      if (isMissingPlugin) return true; // Handled gracefully, do not crash

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
          final refCode = _generateErrorReference(errorStr);
          await _telemetry.logStructured(
            event: 'isolate_uncaught_error',
            level: LogLevel.critical,
            correlationId: refCode,
            metadata: {
              'error_message': errorStr,
              'stack_trace': stackStr.split('\n').take(10).join('\n'),
            },
          );
          try {
            unawaited(Sentry.captureMessage(
              'Uncaught isolate error: $errorStr',
              level: SentryLevel.fatal,
              withScope: (scope) {
                scope.setTag('error_reference', refCode);
                scope.setTag('error_source', 'isolate_uncaught_error');
                scope.setContexts('stack', {'trace': stackStr});
              },
            ));
          } catch (_) {
            // Sentry failure is non-blocking
          }
        }).sendPort,
      );
    }
  }

  /// Wraps a single async operation in a guarded zone that captures all errors.
  ///
  /// Usage:
  /// ```dart
  /// await ErrorBoundary.run(() async {
  ///   await syncService.sync();
  /// }, context: 'sync_v4');
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
