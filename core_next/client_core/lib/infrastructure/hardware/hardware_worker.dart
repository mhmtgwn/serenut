// core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'hardware_commands.dart';
import 'esc_pos_builder.dart';
import 'tspl_builder.dart';

/// Ana UI Thread ile Arka Plan Isolate Arasındaki Köprü (Hardware Worker)
class HardwareWorker {
  SendPort? _isolateSendPort;
  Isolate? _isolate;
  final ReceivePort _mainReceivePort = ReceivePort();
  final StreamController<HardwareEvent> _eventsController =
      StreamController<HardwareEvent>.broadcast();

  Stream<HardwareEvent> get events => _eventsController.stream;
  bool get isInitialized => _isolateSendPort != null;

  /// Arka plan Isolate'ini başlatır
  Future<void> initialize() async {
    if (_isolate != null) return;

    final completer = Completer<void>();

    _mainReceivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        completer.complete();
      } else if (message is HardwareEvent) {
        _eventsController.add(message);
      }
    });

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _mainReceivePort.sendPort,
    );

    await completer.future;
  }

  /// Fiş yazdırma işini arka plan kuyruğuna atar (Sıfır UI blokajı)
  void printReceipt(PrintReceiptCommand cmd) {
    if (_isolateSendPort == null) {
      throw StateError('HardwareWorker henüz başlatılmadı.');
    }
    _isolateSendPort!.send(cmd);
  }

  /// Etiket yazdırma işini arka plan kuyruğuna atar
  void printLabel(PrintLabelCommand cmd) {
    if (_isolateSendPort == null) {
      throw StateError('HardwareWorker henüz başlatılmadı.');
    }
    _isolateSendPort!.send(cmd);
  }

  /// Kaynakları temizle
  Future<void> dispose() async {
    _mainReceivePort.close();
    await _eventsController.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  // ── ARKA PLAN ISOLATE GİRİŞ NOKTASI ───────────────────────────────────────
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    final escPosBuilder = EscPosBuilder();
    final tsplBuilder = TsplBuilder();

    isolateReceivePort.listen((message) async {
      if (message is PrintReceiptCommand) {
        await _handleReceipt(message, escPosBuilder, mainSendPort);
      } else if (message is PrintLabelCommand) {
        await _handleLabel(message, tsplBuilder, mainSendPort);
      }
    });
  }

  static Future<void> _handleReceipt(
    PrintReceiptCommand cmd,
    EscPosBuilder builder,
    SendPort mainSendPort,
  ) async {
    try {
      final bytes = builder.buildReceipt(cmd);
      await _dispatchBytes(bytes, cmd.transport, cmd.targetAddress, cmd.port);

      mainSendPort.send(HardwareEvent(
        correlationId: cmd.correlationId,
        isSuccess: true,
        status: PrinterStatus.ready,
      ));
    } catch (e) {
      mainSendPort.send(HardwareEvent(
        correlationId: cmd.correlationId,
        isSuccess: false,
        status: PrinterStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  static Future<void> _handleLabel(
    PrintLabelCommand cmd,
    TsplBuilder builder,
    SendPort mainSendPort,
  ) async {
    try {
      final bytes = builder.buildLabel(cmd);
      await _dispatchBytes(bytes, cmd.transport, cmd.targetAddress, cmd.port);

      mainSendPort.send(HardwareEvent(
        correlationId: cmd.correlationId,
        isSuccess: true,
        status: PrinterStatus.ready,
      ));
    } catch (e) {
      mainSendPort.send(HardwareEvent(
        correlationId: cmd.correlationId,
        isSuccess: false,
        status: PrinterStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  static Future<void> _dispatchBytes(
    Uint8List bytes,
    PrinterTransportType transport,
    String targetAddress,
    int port,
  ) async {
    if (transport == PrinterTransportType.tcpIp) {
      // Ağ yazıcısına 9100 portundan soket aç (Zaman aşımı 3 saniye)
      Socket? socket;
      try {
        socket = await Socket.connect(
          targetAddress,
          port,
          timeout: const Duration(seconds: 3),
        );
        socket.add(bytes);
        await socket.flush();
      } finally {
        await socket?.close();
      }
    }
    // Not: USB ve Bluetooth taşımaları platform kanalı / libserialport üzerinden
    // benzer şekilde byte akışı olarak bu izole katmanda beslenir.
  }
}
