import 'dart:async';
import 'package:flutter/services.dart';
import 'package:serenutos/infrastructure/services/native_scanner_bridge.dart';

class ResilientScannerService {
  static final ResilientScannerService _instance = ResilientScannerService._();
  factory ResilientScannerService() => _instance;
  ResilientScannerService._();

  final _scanController = StreamController<String>.broadcast();
  final List<String> _scanBuffer = [];

  Stream<String> get scanStream => _scanController.stream;
  List<String> get buffer => List.unmodifiable(_scanBuffer);

  /// Trigger a scan with retry reconnection logic and buffer support
  Future<String?> startResilientScan() async {
    int attempts = 0;
    const int maxAttempts = 3;
    const retryDelay = Duration(milliseconds: 500);

    while (attempts < maxAttempts) {
      attempts++;
      try {
        final code = await NativeScannerBridge.startScan();
        if (code != null && code.isNotEmpty) {
          // Add to buffer and notify stream
          _scanBuffer.add(code);
          _scanController.add(code);
          return code;
        }
        if (attempts < maxAttempts) {
          await Future.delayed(retryDelay);
        }
      } on PlatformException catch (_) {
        if (attempts >= maxAttempts) {
          rethrow;
        }
        await Future.delayed(retryDelay);
      }
    }
    return null;
  }

  /// Consumes and clears the scan buffer
  void clearBuffer() {
    _scanBuffer.clear();
  }

  /// Dispose resources
  void dispose() {
    _scanController.close();
  }
}
