import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef GetDefaultPrinterFunc = Int32 Function(Pointer<Utf16>, Pointer<Uint32>);
typedef GetDefaultPrinter = int Function(Pointer<Utf16>, Pointer<Uint32>);

final class PrinterInfo4W extends Struct {
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pServerName;
  @Uint32()
  external int attributes;
}

typedef EnumPrintersWFunc = Int32 Function(
  Uint32 flags,
  Pointer<Utf16> name,
  Uint32 level,
  Pointer<Uint8> pPrinterEnum,
  Uint32 cbBuf,
  Pointer<Uint32> pcbNeeded,
  Pointer<Uint32> pcReturned,
);

typedef EnumPrintersWDart = int Function(
  int flags,
  Pointer<Utf16> name,
  int level,
  Pointer<Uint8> pPrinterEnum,
  int cbBuf,
  Pointer<Uint32> pcbNeeded,
  Pointer<Uint32> pcReturned,
);

void main() {
  test('GetDefaultPrinterW via FFI', () {
    final lib = DynamicLibrary.open('winspool.drv');
    final fn = lib.lookupFunction<GetDefaultPrinterFunc, GetDefaultPrinter>('GetDefaultPrinterW');
    final sizePtr = calloc<Uint32>();
    fn(nullptr, sizePtr);
    print('Required buffer size: ${sizePtr.value}');
    expect(sizePtr.value, greaterThan(0));
    final buf = calloc<Uint16>(sizePtr.value);
    final res = fn(buf.cast<Utf16>(), sizePtr);
    final printerName = buf.cast<Utf16>().toDartString();
    print('Result: $res, Printer name: "$printerName"');
    expect(res, isNot(0));
    expect(printerName.isNotEmpty, isTrue);
    calloc.free(buf);
    calloc.free(sizePtr);
  });

  test('EnumPrintersW Level 4 via FFI', () {
    final lib = DynamicLibrary.open('winspool.drv');
    final fn = lib.lookupFunction<EnumPrintersWFunc, EnumPrintersWDart>('EnumPrintersW');
    final cbNeeded = calloc<Uint32>();
    final cReturned = calloc<Uint32>();
    const flags = 0x00000002 | 0x00000004; // PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS

    fn(flags, nullptr, 4, nullptr, 0, cbNeeded, cReturned);
    print('Enum needed bytes: ${cbNeeded.value}');
    expect(cbNeeded.value, greaterThan(0));

    final buf = calloc<Uint8>(cbNeeded.value);
    final res = fn(flags, nullptr, 4, buf, cbNeeded.value, cbNeeded, cReturned);
    expect(res, isNot(0));
    print('Printers returned: ${cReturned.value}');

    final ptrList = buf.cast<PrinterInfo4W>();
    final names = <String>[];
    for (var i = 0; i < cReturned.value; i++) {
      final item = ptrList[i];
      if (item.pPrinterName != nullptr) {
        names.add(item.pPrinterName.toDartString());
      }
    }
    print('Found printers: $names');
    expect(names.isNotEmpty, isTrue);

    calloc.free(buf);
    calloc.free(cbNeeded);
    calloc.free(cReturned);
  });
}
