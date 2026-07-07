// lib/infrastructure/services/native_printer_bridge.dart
// Serenut POS — Native Printer Bridge (Platform-guarded)
// Supports: Sunmi internal (Android), Bluetooth (Android)
// iOS / Windows: returns safe no-op (network printer only on those platforms)
// Updated: 24 Jun 2026

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativePrinterBridge {
  static const MethodChannel _bluetoothChannel =
      MethodChannel('com.shaman.printer/bluetooth');
  static const MethodChannel _sunmiChannel =
      MethodChannel('com.shaman.printer/sunmi');
  static const MethodChannel _usbChannel =
      MethodChannel('com.shaman.printer/usb');

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
      try {
        final tempDir = Directory.systemTemp;
        final timeToken = DateTime.now().microsecondsSinceEpoch;
        final bytesFile = File('${tempDir.path}/serenut_print_$timeToken.bin');
        await bytesFile.writeAsBytes(bytes);

        final cleanPath = bytesFile.path.replaceAll('\\', '/');

        final psScript = '''
\$code = @"
using System;
using System.Runtime.InteropServices;
public class RawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public class DOCINFOA {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }
    [DllImport("winspool.Drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool OpenPrinter([MarshalAs(UnmanagedType.LPStr)] string szPrinter, out IntPtr hPrinter, IntPtr pd);
    [DllImport("winspool.Drv", EntryPoint = "ClosePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, Int32 level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);
    [DllImport("winspool.Drv", EntryPoint = "EndDocPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint = "StartPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint = "EndPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint = "WritePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, Int32 dwCount, out Int32 dwWritten);

    public static bool SendBytesToPrinter(string szPrinterName, byte[] bytes) {
        IntPtr hPrinter = new IntPtr(0);
        DOCINFOA di = new DOCINFOA();
        di.pDocName = "Serenut POS Raw Receipt";
        di.pDataType = "RAW";
        if (OpenPrinter(szPrinterName, out hPrinter, IntPtr.Zero)) {
            if (StartDocPrinter(hPrinter, 1, di)) {
                if (StartPagePrinter(hPrinter)) {
                    IntPtr pUnmanagedBytes = Marshal.AllocCoTaskMem(bytes.Length);
                    Marshal.Copy(bytes, 0, pUnmanagedBytes, bytes.Length);
                    Int32 dwWritten = 0;
                    WritePrinter(hPrinter, pUnmanagedBytes, bytes.Length, out dwWritten);
                    EndPagePrinter(hPrinter);
                    Marshal.FreeCoTaskMem(pUnmanagedBytes);
                }
                EndDocPrinter(hPrinter);
            }
            ClosePrinter(hPrinter);
        }
        return true;
    }
}
"@
Add-Type -TypeDefinition \$code
[RawPrinter]::SendBytesToPrinter("$printerName", [System.IO.File]::ReadAllBytes("$cleanPath"))
''';

        final scriptFile = File('${tempDir.path}/serenut_print_$timeToken.ps1');
        await scriptFile.writeAsString(psScript);

        final result = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path
        ]);

        try {
          await bytesFile.delete();
          await scriptFile.delete();
        } catch (_) {}

        return result.exitCode == 0;
      } catch (_) {
        return false;
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
      final List<dynamic>? devices =
          await _bluetoothChannel.invokeMethod<List<dynamic>>('getPairedDevices');
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
      final bool? success =
          await _sunmiChannel.invokeMethod<bool>('printRawData', {'data': bytes});
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
