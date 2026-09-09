// lib/presentation/mixins/barcode_scanner_mixin.dart
//
// Serenut OS — Ortak Donanım Barkod Okuyucu Mixin'i
// USB/Bluetooth HID klavye modunda çalışan barkod okuyucuların hızlı karakter
// akışını (80ms zaman aşımı ile) yakalar ve tam barkod oluştuğunda [onBarcodeScanned]
// fonksiyonunu tetikler.
//
// Kullanılan sayfalar:
// - SalesPage
// - OrdersPage
// - ProductsPage
// - OrderCreationDialog

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

mixin BarcodeScannerMixin<T extends StatefulWidget> on State<T> {
  String _barcodeBuffer = '';
  DateTime? _lastBufferTime;

  /// Barkod dinleyicisini başlatır (genellikle [initState] içinde çağrılır).
  void initBarcodeScanner() {
    HardwareKeyboard.instance.addHandler(_handleBarcodeKeyEvent);
  }

  /// Barkod dinleyicisini kaldırır (genellikle [dispose] içinde çağrılır).
  void disposeBarcodeScanner() {
    HardwareKeyboard.instance.removeHandler(_handleBarcodeKeyEvent);
  }

  /// Mevcut sayfanın veya sekmenin barkod dinlemeye uygun olup olmadığını kontrol eder.
  /// İlgili sayfa bunu override edip sekme indeksi veya route kontrolü ekleyebilir.
  bool canHandleBarcodeScan() {
    if (!mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    return true;
  }

  /// Barkod başarıyla okunduğunda tetiklenir (en az 3 karakter + Enter).
  void onBarcodeScanned(String barcode);

  /// Global klavye olayını işler.
  bool _handleBarcodeKeyEvent(KeyEvent event) {
    if (!canHandleBarcodeScan()) return false;

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;

    // Enter tuşu geldiğinde: buffer yeterince uzunsa barkodu gönder
    if (isEnter) {
      if (_barcodeBuffer.length >= 3) {
        if (event is KeyDownEvent) {
          final code = _barcodeBuffer;
          _barcodeBuffer = '';
          onBarcodeScanned(code);
        }
        return true; // Enter olayını tüket (form submit tetiklenmesini önler)
      }
      if (event is KeyDownEvent) {
        _barcodeBuffer = '';
      }
      return false;
    }

    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastBufferTime != null) {
      final diff = now.difference(_lastBufferTime!).inMilliseconds;
      if (diff > 80) {
        _barcodeBuffer = '';
      }
    }
    _lastBufferTime = now;

    String? char = event.character;
    if (char == null) {
      final label = event.logicalKey.keyLabel;
      if (label.length == 1 && RegExp(r'[a-zA-Z0-9-]').hasMatch(label)) {
        char = label;
      }
    }
    if (char != null && char.length == 1) {
      _barcodeBuffer += char;
    }
    return false;
  }
}
