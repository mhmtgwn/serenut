// test/services/native_printer_bridge_test.dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';

class MockWinspoolWrapper implements WinspoolWrapper {
  String? lastPrinterName;
  List<int>? lastBytes;
  bool openPrinterCalled = false;
  bool startDocPrinterCalled = false;
  bool writePrinterCalled = false;
  bool closePrinterCalled = false;

  @override
  int openPrinter(Pointer<Utf16> pPrinterName, Pointer<IntPtr> phPrinter, Pointer<Void> pDefault) {
    openPrinterCalled = true;
    lastPrinterName = pPrinterName.toDartString();
    // Simulate successful handle creation (e.g. hPrinter = 42)
    phPrinter.value = 42;
    return 1; // success
  }

  @override
  int closePrinter(int hPrinter) {
    closePrinterCalled = true;
    expect(hPrinter, 42);
    return 1; // success
  }

  @override
  int startDocPrinter(int hPrinter, int level, Pointer<DocInfo1W> pDocInfo) {
    startDocPrinterCalled = true;
    expect(hPrinter, 42);
    expect(level, 1);
    expect(pDocInfo.ref.pDocName.toDartString(), 'Serenut POS Raw Receipt');
    expect(pDocInfo.ref.pDataType.toDartString(), 'RAW');
    return 1; // doc ID
  }

  @override
  int endDocPrinter(int hPrinter) {
    expect(hPrinter, 42);
    return 1;
  }

  @override
  int startPagePrinter(int hPrinter) {
    expect(hPrinter, 42);
    return 1;
  }

  @override
  int endPagePrinter(int hPrinter) {
    expect(hPrinter, 42);
    return 1;
  }

  @override
  int writePrinter(int hPrinter, Pointer<Uint8> pBuf, int cbBuf, Pointer<Uint32> pcWritten) {
    writePrinterCalled = true;
    expect(hPrinter, 42);
    
    // Copy bytes out of pointer buffer
    final copied = <int>[];
    for (var i = 0; i < cbBuf; i++) {
      copied.add(pBuf[i]);
    }
    lastBytes = copied;
    
    // Simulate bytes written
    pcWritten.value = cbBuf;
    return 1; // success
  }
}

void main() {
  group('NativePrinterBridge FFI Unit Tests', () {
    test('FFI print path successfully maps parameters and executes FFI calls', () async {
      final mockWinspool = MockWinspoolWrapper();
      final bridge = NativePrinterBridge(mockWinspool);

      final testBytes = [0x1B, 0x40, 0x41, 0x42, 0x43, 0x0A];
      const constPrinterName = 'Thermal USB Printer';

      // Call public printUsbFfi method directly on bridge
      final bool success = await bridge.printUsbFfi(constPrinterName, testBytes);

      expect(success, isTrue);
      expect(mockWinspool.openPrinterCalled, isTrue);
      expect(mockWinspool.lastPrinterName, constPrinterName);
      expect(mockWinspool.startDocPrinterCalled, isTrue);
      expect(mockWinspool.writePrinterCalled, isTrue);
      expect(mockWinspool.lastBytes, testBytes);
      expect(mockWinspool.closePrinterCalled, isTrue);
    });
  });
}
