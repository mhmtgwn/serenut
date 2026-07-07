// lib/providers/device_status_provider.dart
// Serenut POS — Device Status Provider (Printer + Scanner heartbeat)
// Polls device health every 30s; shows banner on failure
// Created: 24 Jun 2026

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

// ── Status Enums ──────────────────────────────────────────────────────────────

enum PrinterConnectionStatus { connected, disconnected, failing, queueMode }
enum ScannerConnectionStatus { hardware, camera, keyboard, offline }

// ── Device State ──────────────────────────────────────────────────────────────

class DeviceState {
  final PrinterConnectionStatus printerStatus;
  final ScannerConnectionStatus scannerStatus;
  final int pendingPrintJobs;
  final String? printerError;
  final DateTime lastChecked;

  const DeviceState({
    this.printerStatus = PrinterConnectionStatus.disconnected,
    this.scannerStatus = ScannerConnectionStatus.offline,
    this.pendingPrintJobs = 0,
    this.printerError,
    required this.lastChecked,
  });

  bool get printerOk =>
      printerStatus == PrinterConnectionStatus.connected;

  bool get hasPendingJobs => pendingPrintJobs > 0;

  bool get requiresAttention =>
      printerStatus == PrinterConnectionStatus.failing ||
      printerStatus == PrinterConnectionStatus.queueMode ||
      pendingPrintJobs > 0;

  DeviceState copyWith({
    PrinterConnectionStatus? printerStatus,
    ScannerConnectionStatus? scannerStatus,
    int? pendingPrintJobs,
    String? printerError,
    DateTime? lastChecked,
  }) {
    return DeviceState(
      printerStatus:    printerStatus   ?? this.printerStatus,
      scannerStatus:    scannerStatus   ?? this.scannerStatus,
      pendingPrintJobs: pendingPrintJobs ?? this.pendingPrintJobs,
      printerError:     printerError,
      lastChecked:      lastChecked     ?? this.lastChecked,
    );
  }
}

// ── Device Status Notifier ────────────────────────────────────────────────────

class DeviceStatusNotifier extends StateNotifier<DeviceState> {
  final Ref _ref;
  final PersistentPrintQueue _printQueue;
  Timer? _heartbeatTimer;

  static const Duration _heartbeatInterval = Duration(seconds: 30);

  DeviceStatusNotifier(this._ref, this._printQueue)
      : super(DeviceState(lastChecked: DateTime.now())) {
    // Initial check + start heartbeat
    _check();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _check());
  }

  /// Manually trigger a device health check.
  Future<void> refresh() => _check();

  Future<void> _check() async {
    final settings = _ref.read(settingsNotifierProvider).value;

    // ── Printer check ─────────────────────────────────────────────────────
    PrinterConnectionStatus printerStatus;
    String? printerError;

    try {
      printerStatus = await _checkPrinter(settings);
    } catch (e) {
      printerStatus = PrinterConnectionStatus.failing;
      printerError = e.toString();
    }

    // ── Scanner check ─────────────────────────────────────────────────────
    ScannerConnectionStatus scannerStatus;
    if (kIsWeb) {
      scannerStatus = ScannerConnectionStatus.offline;
    } else if (Platform.isWindows) {
      scannerStatus = ScannerConnectionStatus.keyboard;
    } else if (Platform.isAndroid) {
      final hasSunmi = await NativePrinterBridge.hasSunmiPrinter()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      scannerStatus = hasSunmi
          ? ScannerConnectionStatus.hardware
          : ScannerConnectionStatus.camera;
    } else if (Platform.isIOS) {
      scannerStatus = ScannerConnectionStatus.camera;
    } else {
      scannerStatus = ScannerConnectionStatus.offline;
    }

    // ── Pending print jobs ────────────────────────────────────────────────
    final pending = await _printQueue.pendingCount();

    state = state.copyWith(
      printerStatus:    printerStatus,
      printerError:     printerError,
      scannerStatus:    scannerStatus,
      pendingPrintJobs: pending,
      lastChecked:      DateTime.now(),
    );
  }

  Future<PrinterConnectionStatus> _checkPrinter(settings) async {
    if (settings == null) return PrinterConnectionStatus.disconnected;

    final printerName = settings.printerName?.trim();
    final printerIp   = settings.printerIp?.trim();

    // Sunmi check (Android only)
    if (printerName == 'sunmi') {
      if (!kIsWeb && Platform.isAndroid) {
        final status = await NativePrinterBridge.getSunmiPrinterStatus()
            .timeout(const Duration(seconds: 3), onTimeout: () => 'timeout');
        return (status == 'unavailable' || status == 'timeout')
            ? PrinterConnectionStatus.disconnected
            : PrinterConnectionStatus.connected;
      }
      return PrinterConnectionStatus.disconnected;
    }

    // Network printer TCP ping
    if (printerIp != null && printerIp.isNotEmpty) {
      if (kIsWeb) return PrinterConnectionStatus.disconnected;
      try {
        final socket = await Socket.connect(
          printerIp,
          settings.printerPort,
          timeout: const Duration(seconds: 3),
        );
        await socket.close();
        return PrinterConnectionStatus.connected;
      } on SocketException {
        return PrinterConnectionStatus.disconnected;
      } on TimeoutException {
        return PrinterConnectionStatus.disconnected;
      }
    }

    // Queue mode — printer not configured but there are pending jobs
    final pending = await _printQueue.pendingCount();
    if (pending > 0) return PrinterConnectionStatus.queueMode;

    return PrinterConnectionStatus.disconnected;
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final deviceStatusProvider =
    StateNotifierProvider<DeviceStatusNotifier, DeviceState>((ref) {
  final queue = ref.watch(persistentPrintQueueProvider);
  return DeviceStatusNotifier(ref, queue);
});

/// Quick accessor — true if printer needs attention.
final printerNeedsAttentionProvider = Provider<bool>(
  (ref) => ref.watch(deviceStatusProvider).requiresAttention,
);

/// Pending print job count.
final pendingPrintJobsProvider = Provider<int>(
  (ref) => ref.watch(deviceStatusProvider).pendingPrintJobs,
);

/// Current scanner mode label for display.
final scannerModeLabelProvider = Provider<String>((ref) {
  final status = ref.watch(deviceStatusProvider).scannerStatus;
  return switch (status) {
    ScannerConnectionStatus.hardware => 'Sunmi Tarayici',
    ScannerConnectionStatus.camera   => 'Kamera Tarayici',
    ScannerConnectionStatus.keyboard => 'USB Tarayici',
    ScannerConnectionStatus.offline  => 'Tarayici Yok',
  };
});
