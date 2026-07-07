import 'dart:async';
import 'package:flutter/services.dart';

enum ScannerMode {
  sunmiHardware, // Sunmi built-in scanner (Android)
  camera,        // Camera-based (Android + iOS)
  usbKeyboard,   // USB scanner in HID keyboard mode (Windows)
  none,          // Not available / web
}

class ScanEvent {
  final String barcode;
  final ScannerMode source;
  final DateTime scannedAt;

  const ScanEvent({
    required this.barcode,
    required this.source,
    required this.scannedAt,
  });
}

abstract class IScannerService {
  Stream<ScanEvent> get scanStream;
  ScannerMode get activeMode;
  List<ScanEvent> get buffer;
  Future<ScannerMode> initialize();
  void onBarcodeDetected(String barcode);
  bool handleKeyEvent(KeyEvent event);
  Future<String?> triggerScan();
  List<ScanEvent> consumeBuffer();
  void dispose();
}
