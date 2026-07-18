// lib/infrastructure/services/native_printer_bridge.dart
// Serenut OS — Native Printer Bridge (Platform-guarded)
// Supports: Sunmi internal (Android), Bluetooth (Android)
// iOS / Windows: returns safe no-op (network printer only on those platforms)
// Updated: 24 Jun 2026

import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// FFI helper signatures for winspool.drv raw printing
typedef OpenPrinterWUtf16Func = Int32 Function(
  Pointer<Utf16> pPrinterName,
  Pointer<IntPtr> phPrinter,
  Pointer<Void> pDefault,
);
typedef OpenPrinterWFunc = int Function(
  Pointer<Utf16> pPrinterName,
  Pointer<IntPtr> phPrinter,
  Pointer<Void> pDefault,
);

typedef ClosePrinterFunc = Int32 Function(
  IntPtr hPrinter,
);
typedef ClosePrinterDartFunc = int Function(
  int hPrinter,
);

final class DocInfo1W extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDataType;
}

typedef StartDocPrinterWFunc = Uint32 Function(
  IntPtr hPrinter,
  Uint32 level,
  Pointer<DocInfo1W> pDocInfo,
);
typedef StartDocPrinterWDartFunc = int Function(
  int hPrinter,
  int level,
  Pointer<DocInfo1W> pDocInfo,
);

typedef EndDocPrinterFunc = Int32 Function(
  IntPtr hPrinter,
);
typedef EndDocPrinterDartFunc = int Function(
  int hPrinter,
);

typedef StartPagePrinterFunc = Int32 Function(
  IntPtr hPrinter,
);
typedef StartPagePrinterDartFunc = int Function(
  int hPrinter,
);

typedef EndPagePrinterFunc = Int32 Function(
  IntPtr hPrinter,
);
typedef EndPagePrinterDartFunc = int Function(
  int hPrinter,
);

typedef WritePrinterFunc = Int32 Function(
  IntPtr hPrinter,
  Pointer<Uint8> pBuf,
  Uint32 cbBuf,
  Pointer<Uint32> pcWritten,
);
typedef WritePrinterDartFunc = int Function(
  int hPrinter,
  Pointer<Uint8> pBuf,
  int cbBuf,
  Pointer<Uint32> pcWritten,
);

class NativePrinterBridge {
  final WinspoolWrapper _winspool;

  NativePrinterBridge([WinspoolWrapper? winspool])
      : _winspool = winspool ?? WinspoolWrapperImpl();

  static NativePrinterBridge _defaultInstance = NativePrinterBridge();

  @visibleForTesting
  static set defaultInstance(NativePrinterBridge instance) {
    _defaultInstance = instance;
  }

  static const MethodChannel _bluetoothChannel =
      MethodChannel('com.serenutos.printer/bluetooth');
  static const MethodChannel _sunmiChannel =
      MethodChannel('com.serenutos.printer/sunmi');
  static const MethodChannel _usbChannel =
      MethodChannel('com.serenutos.printer/usb');

  static bool usePowerShellFallback = false;

  static Future<bool> _printUsbPowerShellFallback(
      String printerName, List<int> bytes) async {
    try {
      final tempFile = File(
          '${Directory.systemTemp.path}/print_raw_${DateTime.now().microsecondsSinceEpoch}.bin');
      await tempFile.writeAsBytes(bytes);

      final psScript = '''
\$code = @'
using System;
using System.Runtime.InteropServices;
public class RawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DOCINFO {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }
    [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern int StartDocPrinter(IntPtr hPrinter, int level, ref DOCINFO pDocInfo);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBuf, int cbBuf, out int pcWritten);
}
'@
Add-Type -TypeDefinition \$code
  \$success = \$false
if ([RawPrinter]::OpenPrinter("$printerName", [ref] \$hPrinter, [IntPtr]::Zero)) {
    try {
        \$docInfo = New-Object RawPrinter+DOCINFO
        \$docInfo.pDocName = "Serenut OS Fallback Receipt"
        \$docInfo.pDataType = "RAW"
        if ([RawPrinter]::StartDocPrinter(\$hPrinter, 1, [ref] \$docInfo) -ne 0) {
            if ([RawPrinter]::StartPagePrinter(\$hPrinter)) {
                \$bytes = [System.IO.File]::ReadAllBytes("${tempFile.path.replaceAll('\\', '\\\\')}")
                \$pinnedArray = [System.Runtime.InteropServices.GCHandle]::Alloc(\$bytes, "Pinned")
                \$pBuf = \$pinnedArray.AddrOfPinnedObject()
                \$written = 0
                if ([RawPrinter]::WritePrinter(\$hPrinter, \$pBuf, \$bytes.Length, [ref] \$written)) {
                    \$success = \$true
                }
                \$pinnedArray.Free()
                [RawPrinter]::EndPagePrinter(\$hPrinter)
            }
            [RawPrinter]::EndDocPrinter(\$hPrinter)
        }
    } finally {
        [RawPrinter]::ClosePrinter(\$hPrinter)
    }
}
if (-not \$success) {
    exit 1
}

''';

      final res = await Process.run('powershell', ['-Command', psScript]);
      try {
        await tempFile.delete();
      } catch (_) {}
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('PowerShell fallback printing failed: $e');
      return false;
    }
  }

  @visibleForTesting
  Future<bool> printUsbFfi(String printerName, List<int> bytes) async {
    Pointer<Utf16>? pPrinterName;
    Pointer<IntPtr>? phPrinter;
    Pointer<DocInfo1W>? docInfo;
    Pointer<Uint8>? pBytes;
    Pointer<Uint32>? pcWritten;
    int hPrinter = 0;

    try {
      pPrinterName = printerName.toNativeUtf16();
      phPrinter = calloc<IntPtr>();

      final openRes = _winspool.openPrinter(pPrinterName, phPrinter, nullptr);
      if (openRes == 0) return false;

      hPrinter = phPrinter.value;

      docInfo = calloc<DocInfo1W>();
      docInfo.ref.pDocName = 'Serenut OS Raw Receipt'.toNativeUtf16();
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDataType = 'RAW'.toNativeUtf16();

      final docId = _winspool.startDocPrinter(hPrinter, 1, docInfo);
      if (docId == 0) return false;

      bool printSuccess = false;
      try {
        final pageRes = _winspool.startPagePrinter(hPrinter);
        if (pageRes != 0) {
          try {
            pBytes = calloc<Uint8>(bytes.length);
            for (var i = 0; i < bytes.length; i++) {
              pBytes[i] = bytes[i];
            }
            pcWritten = calloc<Uint32>();

            final writeRes = _winspool.writePrinter(
                hPrinter, pBytes, bytes.length, pcWritten);
            printSuccess = writeRes != 0;
          } finally {
            if (pBytes != null) calloc.free(pBytes);
            if (pcWritten != null) calloc.free(pcWritten);
          }
          _winspool.endPagePrinter(hPrinter);
        }
      } finally {
        _winspool.endDocPrinter(hPrinter);
      }

      return printSuccess;
    } finally {
      if (pPrinterName != null) calloc.free(pPrinterName);
      if (phPrinter != null) calloc.free(phPrinter);
      if (docInfo != null) {
        if (docInfo.ref.pDocName != nullptr) calloc.free(docInfo.ref.pDocName);
        if (docInfo.ref.pDataType != nullptr)
          calloc.free(docInfo.ref.pDataType);
        calloc.free(docInfo);
      }
      if (hPrinter != 0) {
        _winspool.closePrinter(hPrinter);
      }
    }
  }

  // ── Platform guards ────────────────────────────────────────────────────────

  /// True only on Android — native channels only exist there.
  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // ── USB PRINTER METHODS ────────────────────────────────────────────────────

  /// Print raw ESC/POS bytes on a USB printer.
  /// Supports: Windows spooler printing (via win32 APIs wrapped in PowerShell) and Android USB OTG.
  static Future<bool> printUsbRaw(String printerName, List<int> bytes) async {
    if (kIsWeb) return false;

    // Windows spooler raw printing
    if (Platform.isWindows) {
      if (usePowerShellFallback) {
        return _printUsbPowerShellFallback(printerName, bytes);
      }
      try {
        final success = await _defaultInstance.printUsbFfi(printerName, bytes);
        if (!success) {
          debugPrint(
              'WinSpool FFI returned false. Trying PowerShell fallback...');
          return _printUsbPowerShellFallback(printerName, bytes);
        }
        return success;
      } catch (e) {
        debugPrint('WinSpool FFI crashed. Trying PowerShell fallback...');
        return _printUsbPowerShellFallback(printerName, bytes);
      }
    }

    // Android USB OTG printing
    if (Platform.isAndroid) {
      try {
        final bool? success = await _usbChannel.invokeMethod<bool>(
          'printRawData',
          {'printerName': printerName, 'data': bytes},
        );
        return success ?? false;
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  // ── BLUETOOTH PRINTER METHODS ──────────────────────────────────────────────

  /// Check if Bluetooth is enabled and available on the device.
  /// Returns false on iOS/Windows/Web (not supported).
  static Future<bool> isBluetoothAvailable() async {
    if (!_isAndroid) return false;
    try {
      final bool? available =
          await _bluetoothChannel.invokeMethod<bool>('isBluetoothAvailable');
      return available ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Get list of paired Bluetooth devices.
  /// Returns empty list on non-Android platforms.
  static Future<List<Map<String, String>>> getPairedBluetoothDevices() async {
    if (!_isAndroid) return [];
    try {
      final List<dynamic>? devices = await _bluetoothChannel
          .invokeMethod<List<dynamic>>('getPairedDevices');
      if (devices == null) return [];
      return devices.map((d) {
        final map = Map<String, dynamic>.from(d as Map);
        return {
          'name': map['name']?.toString() ?? 'Bilinmeyen Cihaz',
          'address': map['address']?.toString() ?? '',
        };
      }).toList();
    } on PlatformException catch (_) {
      return [];
    } on MissingPluginException catch (_) {
      return [];
    }
  }

  /// Connect to a Bluetooth printer by its MAC address.
  static Future<bool> connectBluetoothDevice(String address) async {
    if (!_isAndroid) return false;
    try {
      final bool? connected = await _bluetoothChannel
          .invokeMethod<bool>('connect', {'address': address});
      return connected ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Disconnect from the current Bluetooth printer.
  static Future<bool> disconnectBluetooth() async {
    if (!_isAndroid) return false;
    try {
      final bool? disconnected =
          await _bluetoothChannel.invokeMethod<bool>('disconnect');
      return disconnected ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Print raw ESC/POS bytes on the Bluetooth printer.
  static Future<bool> printBluetoothRaw(List<int> bytes) async {
    if (!_isAndroid) return false;
    try {
      final bool? success = await _bluetoothChannel.invokeMethod<bool>(
        'printRawData',
        {'data': Uint8List.fromList(bytes)},
      );
      return success ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Print a test page on the Bluetooth printer.
  static Future<bool> testBluetoothPrint(String protocol) async {
    if (!_isAndroid) return false;
    try {
      final bool? success = await _bluetoothChannel
          .invokeMethod<bool>('testPrint', {'protocol': protocol});
      return success ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  // ── SUNMI EMBEDDED PRINTER METHODS ────────────────────────────────────────

  /// Check if the built-in Sunmi printer is available.
  /// Always returns false on non-Android devices.
  static Future<bool> hasSunmiPrinter() async {
    if (!_isAndroid) return false;
    try {
      final bool? available =
          await _sunmiChannel.invokeMethod<bool>('hasPrinter');
      return available ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Get the built-in Sunmi printer model name.
  static Future<String> getSunmiPrinterModel() async {
    if (!_isAndroid) return 'N/A';
    try {
      final String? model =
          await _sunmiChannel.invokeMethod<String>('getPrinterModel');
      return model ?? 'Sunmi Gomulu';
    } on PlatformException catch (_) {
      return 'Sunmi Gomulu';
    } on MissingPluginException catch (_) {
      return 'N/A';
    }
  }

  /// Print raw ESC/POS bytes on the built-in Sunmi printer.
  static Future<bool> printSunmiRaw(List<int> bytes) async {
    if (!_isAndroid) return false;
    try {
      final bool? success = await _sunmiChannel
          .invokeMethod<bool>('printRawData', {'data': bytes});
      return success ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Get Sunmi printer status.
  static Future<String> getSunmiPrinterStatus() async {
    if (!_isAndroid) return 'unavailable';
    try {
      final String? status =
          await _sunmiChannel.invokeMethod<String>('getPrinterVersion');
      return status ?? 'unknown';
    } on PlatformException catch (_) {
      return 'error';
    } on MissingPluginException catch (_) {
      return 'unavailable';
    }
  }
}

/// Arayüz: Windows Spooler raw yazdırma FFI çağrıları için mock'lanabilir soyut sınıf
abstract class WinspoolWrapper {
  int openPrinter(Pointer<Utf16> pPrinterName, Pointer<IntPtr> phPrinter,
      Pointer<Void> pDefault);
  int closePrinter(int hPrinter);
  int startDocPrinter(int hPrinter, int level, Pointer<DocInfo1W> pDocInfo);
  int endDocPrinter(int hPrinter);
  int startPagePrinter(int hPrinter);
  int endPagePrinter(int hPrinter);
  int writePrinter(
      int hPrinter, Pointer<Uint8> pBuf, int cbBuf, Pointer<Uint32> pcWritten);
}

/// Üretim Uygulaması: winspool.drv DLL FFI çağrılarını gerçekleştiren gerçek wrapper
class WinspoolWrapperImpl implements WinspoolWrapper {
  late final DynamicLibrary _dylib;
  late final OpenPrinterWFunc _openPrinter;
  late final ClosePrinterDartFunc _closePrinter;
  late final StartDocPrinterWDartFunc _startDocPrinter;
  late final EndDocPrinterDartFunc _endDocPrinter;
  late final StartPagePrinterDartFunc _startPagePrinter;
  late final EndPagePrinterDartFunc _endPagePrinter;
  late final WritePrinterDartFunc _writePrinter;

  WinspoolWrapperImpl() {
    if (Platform.isWindows) {
      _dylib = DynamicLibrary.open('winspool.drv');
      _openPrinter =
          _dylib.lookupFunction<OpenPrinterWUtf16Func, OpenPrinterWFunc>(
              'OpenPrinterW');
      _closePrinter =
          _dylib.lookupFunction<ClosePrinterFunc, ClosePrinterDartFunc>(
              'ClosePrinter');
      _startDocPrinter =
          _dylib.lookupFunction<StartDocPrinterWFunc, StartDocPrinterWDartFunc>(
              'StartDocPrinterW');
      _endDocPrinter =
          _dylib.lookupFunction<EndDocPrinterFunc, EndDocPrinterDartFunc>(
              'EndDocPrinter');
      _startPagePrinter =
          _dylib.lookupFunction<StartPagePrinterFunc, StartPagePrinterDartFunc>(
              'StartPagePrinter');
      _endPagePrinter =
          _dylib.lookupFunction<EndPagePrinterFunc, EndPagePrinterDartFunc>(
              'EndPagePrinter');
      _writePrinter =
          _dylib.lookupFunction<WritePrinterFunc, WritePrinterDartFunc>(
              'WritePrinter');
    }
  }

  @override
  int openPrinter(Pointer<Utf16> pPrinterName, Pointer<IntPtr> phPrinter,
      Pointer<Void> pDefault) {
    return _openPrinter(pPrinterName, phPrinter, pDefault);
  }

  @override
  int closePrinter(int hPrinter) {
    return _closePrinter(hPrinter);
  }

  @override
  int startDocPrinter(int hPrinter, int level, Pointer<DocInfo1W> pDocInfo) {
    return _startDocPrinter(hPrinter, level, pDocInfo);
  }

  @override
  int endDocPrinter(int hPrinter) {
    return _endDocPrinter(hPrinter);
  }

  @override
  int startPagePrinter(int hPrinter) {
    return _startPagePrinter(hPrinter);
  }

  @override
  int endPagePrinter(int hPrinter) {
    return _endPagePrinter(hPrinter);
  }

  @override
  int writePrinter(
      int hPrinter, Pointer<Uint8> pBuf, int cbBuf, Pointer<Uint32> pcWritten) {
    return _writePrinter(hPrinter, pBuf, cbBuf, pcWritten);
  }
}
