// lib/infrastructure/services/unified_scanner_service.dart
// Serenut OS — Unified Barcode Scanner Service
// Supports: Sunmi hardware, camera (Android/iOS), USB keyboard (Windows)
// Features: debounce, anti-spam, offline buffer, platform detection

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:serenutos/infrastructure/services/native_scanner_bridge.dart';
import 'package:serenutos/domain/services/i_scanner_service.dart';

/// Production-grade scanner abstraction for all platforms.
class UnifiedScannerService implements IScannerService {
  static const Duration _cameraDebounceWindow = Duration(milliseconds: 1500);
  static const Duration _hardwareDebounceWindow = Duration(milliseconds: 150);
  static const Duration _spamWindow = Duration(milliseconds: 200);
  static const int _spamThreshold = 3;
  static const int _maxBufferSize = 50;

  final _scanController = StreamController<ScanEvent>.broadcast();
  final List<ScanEvent> _buffer = [];

  // Anti-spam / debounce state
  String? _lastBarcode;
  DateTime? _lastScanTime;
  int _recentScanCount = 0;
  DateTime? _spamWindowStart;

  // USB keyboard mode accumulator
  final StringBuffer _keyBuffer = StringBuffer();
  Timer? _keyTimer;
  DateTime? _lastKeystrokeTime;
  static const Duration _maxInterKeyDelay = Duration(milliseconds: 80);

  ScannerMode _activeMode = ScannerMode.none;
  bool _isInitialized = false;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Broadcast stream of scan events (deduplicated, rate-limited).
  @override
  Stream<ScanEvent> get scanStream => _scanController.stream;

  /// Current scanner mode detected.
  @override
  ScannerMode get activeMode => _activeMode;

  /// Scans buffered while caller was busy.
  @override
  List<ScanEvent> get buffer => List.unmodifiable(_buffer);

  /// For testing only: directly set the active mode.
  @visibleForTesting
  void setTestMode(ScannerMode mode) {
    _activeMode = mode;
    _isInitialized = true;
  }

  /// Initialize scanner for the current platform.
  @override
  Future<ScannerMode> initialize() async {
    if (_isInitialized) return _activeMode;
    _isInitialized = true;

    if (kIsWeb) {
      _activeMode = ScannerMode.none;
      return _activeMode;
    }

    // Windows → USB keyboard mode
    if (Platform.isWindows) {
      _activeMode = ScannerMode.usbKeyboard;
      // USB scanners act as keyboards — we intercept via HardwareKeyboard
      // The consumer must call handleKeyEvent() from a KeyboardListener widget
      return _activeMode;
    }

    // Android → try Sunmi hardware first
    if (Platform.isAndroid) {
      try {
        final hasSunmi = await NativeScannerBridge.hasScanner();
        if (hasSunmi) {
          _activeMode = ScannerMode.sunmiHardware;
          _startSunmiStream();
          return _activeMode;
        }
      } catch (_) {
        // Fall through to camera
      }
      _activeMode = ScannerMode.camera;
      return _activeMode;
    }

    // iOS → camera only
    if (Platform.isIOS) {
      _activeMode = ScannerMode.camera;
      return _activeMode;
    }

    _activeMode = ScannerMode.none;
    return _activeMode;
  }

  /// Manually push a barcode (e.g., from mobile_scanner camera callback).
  @override
  void onBarcodeDetected(String barcode) {
    _processBarcode(barcode, _activeMode);
  }

  /// Handle keyboard event for USB scanner mode (Windows).
  ///
  /// Usage: wrap top-level widget with KeyboardListener and call this.
  /// USB scanners send characters with sub-80ms delta, then '\n' at the end.
  @override
  bool handleKeyEvent(KeyEvent event) {
    if (_activeMode != ScannerMode.usbKeyboard) return false;
    if (event is! KeyDownEvent) return false;

    final char = event.character;
    final now = DateTime.now();

    // Check inter-key delta: if last key was pressed more than 80ms ago, this cannot be part of a high-speed scanner stream
    if (_lastKeystrokeTime != null &&
        now.difference(_lastKeystrokeTime!) > _maxInterKeyDelay) {
      _keyBuffer.clear();
    }
    _lastKeystrokeTime = now;

    // Enter key = end of barcode
    if (char == '\n' ||
        char == '\r' ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      final code = _keyBuffer.toString().trim();
      _keyBuffer.clear();
      _keyTimer?.cancel();
      _lastKeystrokeTime = null;
      if (code.length >= 4) {
        _processBarcode(code, ScannerMode.usbKeyboard);
        return true;
      }
      return false;
    }

    if (char == null || char.isEmpty) return false;

    // Accumulate characters
    _keyBuffer.write(char);

    // Safety timeout — if no enter after 100ms, flush buffer
    _keyTimer?.cancel();
    _keyTimer = Timer(const Duration(milliseconds: 100), () {
      _keyBuffer.clear();
      _lastKeystrokeTime = null;
    });

    return false;
  }

  /// Trigger a single scan from Sunmi hardware (for button-triggered mode).
  @override
  Future<String?> triggerScan() async {
    if (_activeMode == ScannerMode.sunmiHardware) {
      final code = await NativeScannerBridge.startScan();
      if (code != null && code.isNotEmpty) {
        _processBarcode(code, ScannerMode.sunmiHardware);
        return code;
      }
    }
    return null;
  }

  /// Consume and clear the scan buffer.
  @override
  List<ScanEvent> consumeBuffer() {
    final items = List<ScanEvent>.from(_buffer);
    _buffer.clear();
    return items;
  }

  @override
  void dispose() {
    _keyTimer?.cancel();
    _scanController.close();
  }

  // ── Private — Sunmi Continuous Stream ─────────────────────────────────────

  void _startSunmiStream() {
    // Sunmi hardware scanner broadcasts via EventChannel
    // The NativeScannerBridge eventChannel stream pipes scanned barcodes
    NativeScannerBridge.scanStream?.listen(
      (barcode) {
        if (barcode != null && barcode.isNotEmpty) {
          _processBarcode(barcode, ScannerMode.sunmiHardware);
        }
      },
      onError: (_) {
        // Scanner stream error — silently degrade to single-shot mode
      },
    );
  }

  // ── Private — Core Processing ─────────────────────────────────────────────

  void _processBarcode(String barcode, ScannerMode source) {
    final now = DateTime.now();
    final code = barcode.trim();
    if (code.isEmpty) return;

    // ── Spam rate limit ────────────────────────────────────────────────────
    if (_spamWindowStart == null ||
        now.difference(_spamWindowStart!) > _spamWindow) {
      _spamWindowStart = now;
      _recentScanCount = 0;
    }
    _recentScanCount++;
    if (_recentScanCount > _spamThreshold) {
      // Scanner flood — ignore until window resets
      return;
    }

    // ── Debounce (duplicate elimination) ─────────────────────────────────
    final debounceWindow = (source == ScannerMode.camera)
        ? _cameraDebounceWindow
        : _hardwareDebounceWindow;

    if (_lastBarcode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < debounceWindow) {
      // Same barcode within debounce window — ignore
      return;
    }

    _lastBarcode = code;
    _lastScanTime = now;

    final event = ScanEvent(
      barcode: code,
      source: source,
      scannedAt: now,
    );

    // ── Buffer + broadcast ─────────────────────────────────────────────────
    if (_buffer.length < _maxBufferSize) {
      _buffer.add(event);
    }
    _scanController.add(event);
  }
}
