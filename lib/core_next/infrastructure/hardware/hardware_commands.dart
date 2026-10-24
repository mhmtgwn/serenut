// core_next/client_core/lib/infrastructure/hardware/hardware_commands.dart

enum PrinterTransportType { tcpIp, usb, bluetooth }

enum PrinterStatus { ready, busy, paperOut, offline, error }

/// Donanım Isolate'ine gönderilen temel komut arayüzü
sealed class HardwareCommand {
  final String correlationId;
  const HardwareCommand(this.correlationId);
}

/// Fiş Yazdırma Komutu
class PrintReceiptCommand extends HardwareCommand {
  final String receiptNo;
  final String title;
  final String? address;
  final String? phone;
  final List<ReceiptLineItem> items;
  final int subtotalCents;
  final int discountCents;
  final int totalCents;
  final int paidCents;
  final int debtCents;
  final String paymentType;
  final String? customerName;
  final DateTime timestamp;
  
  // Hedef Yazıcı Konfigürasyonu
  final PrinterTransportType transport;
  final String targetAddress; // IP adresi veya USB/BT portu
  final int port; // TCP için varsayılan 9100
  final bool openCashDrawer;
  final bool cutPaper;

  const PrintReceiptCommand({
    required String correlationId,
    required this.receiptNo,
    required this.title,
    this.address,
    this.phone,
    required this.items,
    required this.subtotalCents,
    this.discountCents = 0,
    required this.totalCents,
    required this.paidCents,
    this.debtCents = 0,
    required this.paymentType,
    this.customerName,
    required this.timestamp,
    this.transport = PrinterTransportType.tcpIp,
    this.targetAddress = '127.0.0.1',
    this.port = 9100,
    this.openCashDrawer = false,
    this.cutPaper = true,
  }) : super(correlationId);
}

class ReceiptLineItem {
  final String name;
  final int quantity;
  final int unitPriceCents;
  final int totalCents;

  const ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
  });
}

/// TSPL Barkod Etiket Yazdırma Komutu
class PrintLabelCommand extends HardwareCommand {
  final String productName;
  final String barcode;
  final int priceCents;
  final int widthMm;
  final int heightMm;
  final int copies;
  final PrinterTransportType transport;
  final String targetAddress;
  final int port;

  const PrintLabelCommand({
    required String correlationId,
    required this.productName,
    required this.barcode,
    required this.priceCents,
    this.widthMm = 40,
    this.heightMm = 30,
    this.copies = 1,
    this.transport = PrinterTransportType.tcpIp,
    this.targetAddress = '127.0.0.1',
    this.port = 9100,
  }) : super(correlationId);
}

/// Arka Plan Isolate'inden Ana UI Thread'ine Gelen Durum Bildirimi
class HardwareEvent {
  final String correlationId;
  final bool isSuccess;
  final PrinterStatus status;
  final String? errorMessage;

  const HardwareEvent({
    required this.correlationId,
    required this.isSuccess,
    required this.status,
    this.errorMessage,
  });
}
