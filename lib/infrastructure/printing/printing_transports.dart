import 'dart:io';
import 'dart:typed_data';

import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';
import 'package:serenutos/infrastructure/services/shared_hardware_service.dart';

class TcpPrintTransport implements PrintTransport {
  final Future<Socket> Function(String host, int port, {Duration? timeout})
      connector;
  final Duration timeout;

  TcpPrintTransport({
    Future<Socket> Function(String host, int port, {Duration? timeout})?
        connector,
    this.timeout = const Duration(seconds: 5),
  }) : connector = connector ?? Socket.connect;

  @override
  bool supports(PrinterTransportKind kind) => kind == PrinterTransportKind.tcp;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    final host = configuration['host']?.toString().trim() ?? '';
    final port = _integer(configuration['port'], 9100);
    if (host.isEmpty || port < 1 || port > 65535) {
      throw const PrintTransportException(
        code: 'invalid_tcp_configuration',
        message: 'Yazıcı IP adresi veya portu geçersiz.',
        retryable: false,
      );
    }
    Socket? socket;
    var deliveryStarted = false;
    try {
      socket = await connector(host, port, timeout: timeout);
      for (var copy = 0; copy < copies; copy++) {
        deliveryStarted = true;
        socket.add(bytes);
        await socket.flush();
      }
      return PrintTransportObservation(
        transport: PrinterTransportKind.tcp.name,
        acceptedAt: DateTime.now(),
        details: {
          'host': host,
          'port': port,
          'bytesAccepted': bytes.length * copies,
          'copies': copies,
        },
      );
    } on PrintTransportException {
      rethrow;
    } catch (error) {
      throw PrintTransportException(
        code: deliveryStarted ? 'tcp_delivery_uncertain' : 'tcp_connect_failed',
        message: error.toString(),
        retryable: true,
        deliveryUncertain: deliveryStarted,
      );
    } finally {
      await socket?.close();
    }
  }
}

typedef RawNativePrint = Future<bool> Function(
    String printerName, List<int> bytes);

class WindowsSpoolerPrintTransport implements PrintTransport {
  final RawNativePrint rawPrint;

  WindowsSpoolerPrintTransport({RawNativePrint? rawPrint})
      : rawPrint = rawPrint ?? NativePrinterBridge.printUsbRaw;

  @override
  bool supports(PrinterTransportKind kind) =>
      kind == PrinterTransportKind.windowsSpooler ||
      kind == PrinterTransportKind.usb;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    final printerName = configuration['printerName']?.toString().trim() ?? '';
    if (printerName.isEmpty) {
      throw const PrintTransportException(
        code: 'printer_name_missing',
        message: 'Windows/USB yazıcı adı tanımlı değil.',
        retryable: false,
      );
    }
    for (var copy = 0; copy < copies; copy++) {
      final accepted = await rawPrint(printerName, bytes);
      if (!accepted) {
        throw PrintTransportException(
          code: 'native_spool_rejected',
          message: '$printerName ham yazdırma işini kabul etmedi.',
          retryable: true,
          deliveryUncertain: copy > 0,
        );
      }
    }
    return PrintTransportObservation(
      transport: PrinterTransportKind.windowsSpooler.name,
      acceptedAt: DateTime.now(),
      details: {
        'printerName': printerName,
        'bytesAccepted': bytes.length * copies,
        'copies': copies,
      },
    );
  }
}

class BluetoothPrintTransport implements PrintTransport {
  final Future<bool> Function(String address) connect;
  final Future<bool> Function(List<int> bytes) rawPrint;

  BluetoothPrintTransport({
    Future<bool> Function(String address)? connect,
    Future<bool> Function(List<int> bytes)? rawPrint,
  })  : connect = connect ?? NativePrinterBridge.connectBluetoothDevice,
        rawPrint = rawPrint ?? NativePrinterBridge.printBluetoothRaw;

  @override
  bool supports(PrinterTransportKind kind) =>
      kind == PrinterTransportKind.bluetooth;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    final address = (configuration['address'] ?? configuration['printerName'])
            ?.toString()
            .trim() ??
        '';
    if (address.isEmpty || !await connect(address)) {
      throw const PrintTransportException(
        code: 'bluetooth_connect_failed',
        message: 'Bluetooth yazıcıya bağlanılamadı.',
        retryable: true,
      );
    }
    for (var copy = 0; copy < copies; copy++) {
      if (!await rawPrint(bytes)) {
        throw const PrintTransportException(
          code: 'bluetooth_delivery_uncertain',
          message: 'Bluetooth yazdırma sonucu doğrulanamadı.',
          retryable: true,
          deliveryUncertain: true,
        );
      }
    }
    return PrintTransportObservation(
      transport: PrinterTransportKind.bluetooth.name,
      acceptedAt: DateTime.now(),
      details: {'address': address, 'copies': copies},
    );
  }
}

class EmbeddedPrintTransport implements PrintTransport {
  final Future<bool> Function(List<int> bytes) rawPrint;

  EmbeddedPrintTransport({Future<bool> Function(List<int> bytes)? rawPrint})
      : rawPrint = rawPrint ?? NativePrinterBridge.printSunmiRaw;

  @override
  bool supports(PrinterTransportKind kind) =>
      kind == PrinterTransportKind.embedded;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    for (var copy = 0; copy < copies; copy++) {
      if (!await rawPrint(bytes)) {
        throw const PrintTransportException(
          code: 'embedded_delivery_uncertain',
          message: 'Gömülü yazıcı çıktısı doğrulanamadı.',
          retryable: true,
          deliveryUncertain: true,
        );
      }
    }
    return PrintTransportObservation(
      transport: PrinterTransportKind.embedded.name,
      acceptedAt: DateTime.now(),
      details: {'copies': copies},
    );
  }
}

typedef CloudPrintQueue = Future<String> Function({
  required String hardwareId,
  required String operation,
  required List<int> bytes,
  required int copies,
  required String idempotencyKey,
});

class CloudRelayPrintTransport implements PrintTransport {
  final CloudPrintQueue queue;

  CloudRelayPrintTransport(SharedHardwareService service)
      : queue = service.queuePrint;

  CloudRelayPrintTransport.withQueue(this.queue);

  @override
  bool supports(PrinterTransportKind kind) =>
      kind == PrinterTransportKind.cloudRelay;

  @override
  Future<PrintTransportObservation> send({
    required Uint8List bytes,
    required int copies,
    required Map<String, Object?> configuration,
  }) async {
    final hardwareId = configuration['hardwareId']?.toString() ?? '';
    final jobId = configuration['jobId']?.toString() ?? '';
    final documentKind = configuration['documentKind']?.toString() ?? '';
    if (hardwareId.isEmpty || jobId.isEmpty) {
      throw const PrintTransportException(
        code: 'invalid_cloud_relay_configuration',
        message: 'Ortak yazıcı kimliği eksik.',
        retryable: false,
      );
    }
    final operation = switch (documentKind) {
      'receipt' => 'printReceipt',
      'productLabel' => 'printProductLabel',
      'orderLabel' => 'printOrderLabel',
      _ => 'testPrint',
    };
    try {
      final remoteJobId = await queue(
        hardwareId: hardwareId,
        operation: operation,
        bytes: bytes,
        copies: copies,
        idempotencyKey: jobId,
      );
      return PrintTransportObservation(
        transport: PrinterTransportKind.cloudRelay.name,
        acceptedAt: DateTime.now(),
        details: {'remoteJobId': remoteJobId, 'hardwareId': hardwareId},
        physicalConfirmationRequired: true,
      );
    } catch (error) {
      throw PrintTransportException(
        code: 'cloud_relay_unavailable',
        message: 'Ortak yazdırma kuyruğuna ulaşılamadı: $error',
        retryable: true,
      );
    }
  }
}

int _integer(Object? value, int fallback) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
