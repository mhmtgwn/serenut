// core_next/client_core/lib/infrastructure/hardware/printer_transport.dart

import 'dart:io';
import 'dart:typed_data';

/// Yazıcı Bağlantı Arayüzü (Clean Architecture Transport Abstraction)
abstract class PrinterTransport {
  Future<void> sendBytes(Uint8List bytes);
  Future<void> close();
}

/// 1. TCP/IP Ağ Yazıcısı Taşıyıcısı (GERÇEK İMPLEMENTASYON)
class TcpIpPrinterTransport implements PrinterTransport {
  final String host;
  final int port;
  final Duration timeout;

  const TcpIpPrinterTransport({
    required this.host,
    this.port = 9100,
    this.timeout = const Duration(seconds: 3),
  });

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<void> close() async {}
}

/// 2. Windows RAW Spooler Taşıyıcısı (MİMARİ SPESİFİKASYON)
/// 
/// Windows altında USB veya LPT ile bağlanan fiş yazıcılarına sürücü
/// grafik işlemesini atlayarak ham ESC/POS baytlarını göndermek için
/// Windows Spooler API (`winspool.drv`) kullanılır:
/// - OpenPrinterW
/// - StartDocPrinterW (DOC_INFO_1, pDataType: "RAW")
/// - StartPagePrinter
/// - WritePrinter
/// - EndPagePrinter
/// - EndDocPrinter
/// - ClosePrinter
abstract class WindowsRawSpoolerTransport implements PrinterTransport {
  final String printerName;

  const WindowsRawSpoolerTransport({required this.printerName});
}

/// 3. USB Bulk Endpoint Taşıyıcısı (MİMARİ SPESİFİKASYON)
/// 
/// Windows ve Android'de doğrudan USB Vendor/Product ID ile
/// Bulk Out endpoint'ine bayt yazma sözleşmesi.
abstract class UsbBulkTransport implements PrinterTransport {
  final int vendorId;
  final int productId;

  const UsbBulkTransport({
    required this.vendorId,
    required this.productId,
  });
}

/// 4. Bluetooth SPP / RFCOMM Taşıyıcısı (MİMARİ SPESİFİKASYON)
/// 
/// Mobil veya masaüstü Bluetooth SPP (Serial Port Profile) bağlantısı.
abstract class BluetoothSppTransport implements PrinterTransport {
  final String macAddress;

  const BluetoothSppTransport({required this.macAddress});
}
