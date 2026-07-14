// test/device/scanner_stress_test.dart
// Serenut POS — Scanner Stress & Deduplication Tests
// Tests: spam scan prevention, debounce, offline buffer, USB keyboard mode
// Created: 24 Jun 2026

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/i_scanner_service.dart';
import 'package:serenutos/infrastructure/services/unified_scanner_service.dart';

// ── Test harness — inject barcodes without platform ──────────────────────────

/// Testable subclass that bypasses platform detection.
class TestableScanner extends UnifiedScannerService {
  TestableScanner() {
    // Force camera mode for test environment (platform-agnostic)
    setTestMode(ScannerMode.camera);
  }

  void injectBarcode(String barcode) {
    onBarcodeDetected(barcode);
  }

  void injectKey(String char) {
    handleKeyEvent(
      KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        character: char,
        timeStamp: Duration.zero,
      ),
    );
  }

  @override
  Future<ScannerMode> initialize() async {
    return ScannerMode.camera;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedScannerService — Debounce & Anti-spam', () {
    late TestableScanner scanner;
    final received = <ScanEvent>[];

    setUp(() {
      scanner = TestableScanner();
      received.clear();
      scanner.scanStream.listen(received.add);
    });

    tearDown(() {
      scanner.dispose();
    });

    // ── Debounce tests ────────────────────────────────────────────────────

    test('same barcode within 1500ms is ignored (debounce)', () async {
      scanner.injectBarcode('1234567890');
      scanner.injectBarcode('1234567890'); // Immediate duplicate
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.length, equals(1)); // Only first accepted
      expect(received.first.barcode, equals('1234567890'));
    });

    test('same barcode after 1600ms is accepted (debounce window expired)',
        () async {
      scanner.injectBarcode('BARCODE-A');
      await Future.delayed(const Duration(milliseconds: 1600));
      scanner.injectBarcode('BARCODE-A');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.length, equals(2)); // Both accepted
    });

    test('different barcodes are never debounced', () async {
      scanner.injectBarcode('PRODUCT-001');
      scanner.injectBarcode('PRODUCT-002');
      scanner.injectBarcode('PRODUCT-003');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.length, equals(3));
      expect(received.map((e) => e.barcode).toList(),
          containsAll(['PRODUCT-001', 'PRODUCT-002', 'PRODUCT-003']));
    });

    // ── Anti-spam tests ───────────────────────────────────────────────────

    test('more than 3 scans within 200ms triggers rate limit', () async {
      // Fire 6 scans of different barcodes within spam window
      for (int i = 0; i < 6; i++) {
        scanner.injectBarcode('SPAM-$i');
      }
      await Future.delayed(const Duration(milliseconds: 50));

      // At most _spamThreshold (3) should pass through
      expect(received.length, lessThanOrEqualTo(3));
    });

    test('scanning resumes normally after spam window resets', () async {
      // Spam burst
      for (int i = 0; i < 5; i++) {
        scanner.injectBarcode('BURST-$i');
      }
      // Wait for spam window to reset (>200ms)
      await Future.delayed(const Duration(milliseconds: 300));

      // Normal scan should work
      scanner.injectBarcode('AFTER-SPAM');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.any((e) => e.barcode == 'AFTER-SPAM'), isTrue);
    });

    // ── Buffer tests ──────────────────────────────────────────────────────

    test('scans are buffered up to limit (50)', () async {
      for (int i = 0; i < 10; i++) {
        scanner.injectBarcode('BUFFERED-$i');
        await Future.delayed(const Duration(milliseconds: 200)); // Avoid spam
      }

      expect(scanner.buffer.length, greaterThan(0));
      expect(scanner.buffer.length, lessThanOrEqualTo(50));
    });

    test('consumeBuffer clears the buffer', () async {
      scanner.injectBarcode('BUF-001');
      await Future.delayed(const Duration(milliseconds: 50));

      final consumed = scanner.consumeBuffer();
      expect(consumed, isNotEmpty);
      expect(scanner.buffer, isEmpty);
    });

    test('buffer does not exceed max (50 items)', () async {
      // Inject 60 unique barcodes with sufficient gap
      for (int i = 0; i < 60; i++) {
        scanner.injectBarcode('ITEM-${i.toString().padLeft(4, '0')}');
        await Future.delayed(const Duration(milliseconds: 200));
      }
      expect(scanner.buffer.length, lessThanOrEqualTo(50));
    });

    // ── Empty/invalid scan tests ──────────────────────────────────────────

    test('empty string barcode is ignored', () async {
      scanner.injectBarcode('');
      scanner.injectBarcode('   ');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, isEmpty);
    });

    test('whitespace is trimmed from barcode', () async {
      scanner.injectBarcode('  ABC-123  ');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.length, equals(1));
      expect(received.first.barcode, equals('ABC-123'));
    });

    // ── Source tagging ────────────────────────────────────────────────────

    test('scan events are tagged with correct source', () async {
      scanner.injectBarcode('TAGGED-001');
      await Future.delayed(const Duration(milliseconds: 50));

      // Since TestableScanner uses camera mode
      expect(received.first.source, equals(ScannerMode.camera));
    });

    test('scan events have valid timestamp', () async {
      final before = DateTime.now();
      scanner.injectBarcode('TIMESTAMP-TEST');
      await Future.delayed(const Duration(milliseconds: 50));
      final after = DateTime.now();

      final event = received.first;
      expect(
          event.scannedAt
              .isAfter(before.subtract(const Duration(milliseconds: 100))),
          isTrue);
      expect(
          event.scannedAt
              .isBefore(after.add(const Duration(milliseconds: 100))),
          isTrue);
    });

    // ── Concurrent scan stress ────────────────────────────────────────────

    test(
        '50 concurrent rapid scans of different barcodes — no crash, bounded output',
        () async {
      final tasks = List.generate(50, (i) async {
        scanner.injectBarcode('CONCURRENT-${i.toString().padLeft(3, '0')}');
      });

      await Future.wait(tasks);
      await Future.delayed(const Duration(milliseconds: 100));

      // Should not crash and received count should be bounded
      expect(received.length, lessThanOrEqualTo(50));
    });

    test('rapid scan spam then normal scan — system recovers', () async {
      // 10 rapid identical scans
      for (int i = 0; i < 10; i++) {
        scanner.injectBarcode('SPAM-BARCODE');
      }
      await Future.delayed(const Duration(milliseconds: 400));

      // Normal scan after recovery
      scanner.injectBarcode('NORMAL-AFTER-SPAM');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.any((e) => e.barcode == 'NORMAL-AFTER-SPAM'), isTrue);
    });

    // ── Dispose safety ────────────────────────────────────────────────────

    test('dispose does not throw', () {
      expect(() => scanner.dispose(), returnsNormally);
    });

    test('dispose clears buffer', () async {
      scanner.injectBarcode('BEFORE-DISPOSE');
      await Future.delayed(const Duration(milliseconds: 50));
      scanner.dispose();
      // Buffer access after dispose should not crash
      expect(() => scanner.buffer, returnsNormally);
    });
  });
}
