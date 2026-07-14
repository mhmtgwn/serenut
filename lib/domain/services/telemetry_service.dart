// lib/domain/services/telemetry_service.dart
// Structured Telemetry & Error Tracing — Sentry-ready observability layer.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Log severity levels — mirrors standard structured logging conventions.
enum LogLevel { debug, info, warning, error, critical }

extension LogLevelLabel on LogLevel {
  String get label => name.toUpperCase();
  String get emoji {
    switch (this) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.critical:
        return '🚨';
    }
  }
}

class TelemetryEvent {
  final String event;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  final LogLevel level;
  final String correlationId;

  TelemetryEvent({
    required this.event,
    required this.metadata,
    DateTime? timestamp,
    this.level = LogLevel.info,
    String? correlationId,
  })  : timestamp = timestamp ?? DateTime.now(),
        // 16-char base62 gives ~3.5×10²⁸ combinations — collision-safe even at
        // high-frequency POS + sync workloads (vs 8-char: ~2.8×10¹⁴).
        correlationId = correlationId ?? _generateCorrelationId();

  Map<String, dynamic> toJson() => {
        'event': event,
        'timestamp': timestamp.toIso8601String(),
        'level': level.label,
        'correlationId': correlationId,
        ...metadata,
      };

  factory TelemetryEvent.fromJson(Map<String, dynamic> json) {
    final eventName = json['event'] as String? ?? 'unknown';
    final timestampStr = json['timestamp'] as String?;
    final timestamp =
        timestampStr != null ? DateTime.parse(timestampStr) : DateTime.now();
    final levelStr = json['level'] as String? ?? 'INFO';
    final level = LogLevel.values.firstWhere(
      (l) => l.label == levelStr,
      orElse: () => LogLevel.info,
    );
    final correlationId = json['correlationId'] as String? ?? '';
    final meta = Map<String, dynamic>.from(json)
      ..remove('event')
      ..remove('timestamp')
      ..remove('level')
      ..remove('correlationId');

    return TelemetryEvent(
      event: eventName,
      timestamp: timestamp,
      metadata: meta,
      level: level,
      correlationId: correlationId,
    );
  }
}

/// Generates a 16-character base62 correlation ID.
/// Alphabet: [0-9A-Za-z] — 62^16 ≈ 4.7 × 10²⁸ combinations.
String _generateCorrelationId() {
  const alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  final raw = const Uuid().v4().replaceAll('-', ''); // 32 hex chars
  // Map each hex char to base62 by treating pairs as byte values mod 62
  final buf = StringBuffer();
  for (var i = 0; i < 16; i++) {
    final byte = int.parse(raw.substring(i * 2, i * 2 + 2), radix: 16);
    buf.write(alphabet[byte % 62]);
  }
  return buf.toString();
}

/// Configures automatic log rotation for the telemetry JSONL file.
class LogRetentionPolicy {
  /// Maximum number of log lines to retain (rolling window). Default: 1000.
  final int maxLines;

  /// How often (in write operations) the trim check runs. Default: every 100 writes.
  final int trimIntervalWrites;

  const LogRetentionPolicy({
    this.maxLines = 1000,
    this.trimIntervalWrites = 100,
  });
}

class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  File? _logFile;
  final List<TelemetryEvent> _inMemoryQueue = [];
  int _writeCount = 0;

  /// Log retention policy — configurable via constructor injection in tests.
  LogRetentionPolicy retention = const LogRetentionPolicy();

  /// When true, CRITICAL-level events are also forwarded to a remote endpoint.
  /// Set via `TelemetryService().remotePushEnabled = true` after auth is ready.
  bool remotePushEnabled = false;

  /// Optional remote push handler — inject a closure to send CRITICAL logs
  /// to your backend / Sentry without coupling this service to any SDK.
  ///
  /// Example:
  /// ```dart
  /// TelemetryService().onCriticalEvent = (event) async {
  ///   await Sentry.captureMessage(event.event, level: SentryLevel.fatal);
  /// };
  /// ```
  Future<void> Function(TelemetryEvent)? onCriticalEvent;

  Future<File> _getLogFile() async {
    if (_logFile != null) return _logFile!;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logsDir = Directory(p.join(directory.path, 'telemetry'));
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      _logFile = File(p.join(logsDir.path, 'telemetry_logs.jsonl'));
    } catch (_) {
      _logFile = File('telemetry_logs.jsonl');
    }
    return _logFile!;
  }

  Future<void> _write(TelemetryEvent telemetryEvent) async {
    _inMemoryQueue.add(telemetryEvent);

    final label = telemetryEvent.level.emoji;
    final msg = '$label [${telemetryEvent.level.label}] ${telemetryEvent.event}'
        ' (corr:${telemetryEvent.correlationId})';

    if (kIsWeb) {
      debugPrint(
          '🌐 [TELEMETRY] $msg — ${jsonEncode(telemetryEvent.metadata)}');
      return;
    }

    debugPrint(msg);

    try {
      final file = await _getLogFile();
      final line = '${jsonEncode(telemetryEvent.toJson())}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);

      // Rolling trim: run every N writes to keep log bounded
      _writeCount++;
      if (_writeCount % retention.trimIntervalWrites == 0) {
        unawaited(_trimLog(file));
      }
    } catch (_) {
      // Suppress telemetry errors to prevent cascading failures in production
    }

    // CRITICAL events: fire optional remote push handler (Sentry-ready hook)
    if (telemetryEvent.level == LogLevel.critical &&
        remotePushEnabled &&
        onCriticalEvent != null) {
      try {
        await onCriticalEvent!(telemetryEvent);
      } catch (_) {
        // Remote push failures must never crash the local logging path
      }
    }
  }

  /// Trims the log file to the last [LogRetentionPolicy.maxLines] lines.
  /// Runs asynchronously (fire-and-forget) to avoid blocking callers.
  Future<void> _trimLog(File file) async {
    try {
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      if (lines.length <= retention.maxLines) return;
      final trimmed = lines.sublist(lines.length - retention.maxLines);
      await file.writeAsString('${trimmed.join('\n')}\n', flush: true);
    } catch (_) {
      // Non-fatal: trim failure leaves log slightly oversized but still functional
    }
  }

  /// Logs a telemetry event at INFO level (backward-compatible).
  Future<void> logEvent(String event, [Map<String, dynamic>? metadata]) async {
    final payload = {
      if (!kIsWeb)
        'rss_mb': (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(2),
      ...?metadata,
    };
    await _write(TelemetryEvent(event: event, metadata: payload));
  }

  /// Logs a structured event with an explicit severity level.
  Future<void> logStructured({
    required String event,
    required LogLevel level,
    Map<String, dynamic>? metadata,
    String? correlationId,
  }) async {
    final payload = {
      if (!kIsWeb)
        'rss_mb': (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(2),
      ...?metadata,
    };
    await _write(TelemetryEvent(
      event: event,
      metadata: payload,
      level: level,
      correlationId: correlationId,
    ));
  }

  /// Logs an exception with its stack trace at ERROR or CRITICAL level.
  /// Sentry-ready: replace body with `Sentry.captureException(error, stackTrace: stackTrace)`.
  Future<void> logError(
    Object error,
    StackTrace stackTrace, {
    String? context,
    LogLevel level = LogLevel.error,
    String? correlationId,
  }) async {
    unawaited(Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (context != null) {
          scope.setTag('context', context);
        }
        scope.setTag('level', level.name);
        scope.setTag('correlationId', correlationId ?? 'none');
      },
    ));

    await logStructured(
      event: 'unhandled_exception',
      level: level,
      correlationId: correlationId,
      metadata: {
        'error_type': error.runtimeType.toString(),
        'error_message': error.toString(),
        'stack_trace': stackTrace.toString().split('\n').take(10).join('\n'),
        if (context != null) 'context': context,
      },
    );
  }

  /// Retrieves all logged telemetry events.
  Future<List<TelemetryEvent>> getEvents() async {
    if (kIsWeb) return _inMemoryQueue;
    final list = <TelemetryEvent>[];
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            list.add(TelemetryEvent.fromJson(json));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return list;
  }

  /// Retrieves only events at or above [minLevel] severity.
  /// Useful for CRITICAL log viewer screens.
  Future<List<TelemetryEvent>> getEventsByLevel(LogLevel minLevel) async {
    final all = await getEvents();
    return all.where((e) => e.level.index >= minLevel.index).toList();
  }

  /// Clears all logged telemetry events.
  Future<void> clearLogs() async {
    _inMemoryQueue.clear();
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
