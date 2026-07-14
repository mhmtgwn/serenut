// lib/infrastructure/services/native_scanner_bridge.dart
// Serenut POS — Native Scanner Bridge (MethodChannel + EventChannel)
// Supports: Sunmi hardware scanner continuous mode
// Updated: 24 Jun 2026

import 'package:flutter/services.dart';

class NativeScannerBridge {
  static const MethodChannel _channel = MethodChannel('com.sunmi.scanner');
  static const EventChannel _eventChannel =
      EventChannel('com.sunmi.scanner/events');

  // ── Scanner Availability ───────────────────────────────────────────────────

  /// Check if the hardware scanner is available on this device.
  static Future<bool> hasScanner() async {
    try {
      final bool? available = await _channel.invokeMethod<bool>('hasScanner');
      return available ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Get scanner model info.
  static Future<Map<String, String>> getScannerInfo() async {
    try {
      final Map<dynamic, dynamic>? info =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getScannerInfo');
      if (info == null) return {};
      return Map<String, String>.from(info);
    } on PlatformException catch (_) {
      return {};
    } on MissingPluginException catch (_) {
      return {};
    }
  }

  // ── Single-shot Scan ───────────────────────────────────────────────────────

  /// Trigger a single scan from the hardware scanner.
  /// Returns the scanned barcode string or null if cancelled/failed.
  static Future<String?> startScan() async {
    try {
      final String? barcode = await _channel.invokeMethod<String>('startScan');
      return barcode;
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  /// Stop the scanner.
  static Future<bool> stopScan() async {
    try {
      final bool? success = await _channel.invokeMethod<bool>('stopScan');
      return success ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  // ── Continuous Scan Stream (EventChannel) ──────────────────────────────────

  /// Continuous barcode stream from Sunmi hardware scanner.
  ///
  /// The Android side broadcasts each scanned barcode as a String event.
  /// Returns null if EventChannel is not available (non-Sunmi device).
  ///
  /// Usage:
  /// ```dart
  /// NativeScannerBridge.scanStream?.listen((barcode) { ... });
  /// ```
  static Stream<String?>? get scanStream {
    try {
      return _eventChannel
          .receiveBroadcastStream()
          .map((event) => event?.toString());
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Continuous Scan Control ────────────────────────────────────────────────

  /// Enable continuous scanning mode (scanner fires on every successful read).
  static Future<bool> startContinuousScan() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('startContinuousScan');
      return ok ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Disable continuous scanning mode.
  static Future<bool> stopContinuousScan() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('stopContinuousScan');
      return ok ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}
