import 'dart:async';
import 'dart:convert';

import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';
import 'package:serenutos/infrastructure/printing/print_asset_encoder.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';

class PhysicalPrintTestDispatch {
  final String jobId;
  final String deviceId;
  final PrintDocumentKind kind;
  final DateTime deliveredAt;

  const PhysicalPrintTestDispatch({
    required this.jobId,
    required this.deviceId,
    required this.kind,
    required this.deliveredAt,
  });
}

class PhysicalPrintTestService {
  final PrintingRepository repository;
  final PrintingRuntime runtime;
  final PrintAssetEncoder assets;
  final Duration timeout;

  const PhysicalPrintTestService({
    required this.repository,
    required this.runtime,
    this.assets = const PrintAssetEncoder(),
    this.timeout = const Duration(seconds: 30),
  });

  Future<PhysicalPrintTestDispatch> dispatch({
    required String deviceId,
    required PrintDocumentKind kind,
  }) async {
    final device = await repository.getDevice(deviceId);
    final job = await repository.enqueueForDevice(
      kind: kind,
      deviceId: deviceId,
      payloadJson: jsonEncode(await _payloadFor(kind, device)),
    );
    if (runtime.isRunning) {
      await runtime.processNow();
    } else {
      await runtime.start();
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = await repository.getJob(job.id);
      if (current == null) {
        throw StateError('Fiziksel test işi kayboldu.');
      }
      if (current.state == PrintJobState.delivered) {
        await repository.requestPhysicalConfirmation(job.id);
        return PhysicalPrintTestDispatch(
          jobId: job.id,
          deviceId: deviceId,
          kind: kind,
          deliveredAt: DateTime.now(),
        );
      }
      if (current.state == PrintJobState.failed ||
          current.state == PrintJobState.rejected ||
          current.state == PrintJobState.awaitingUserCheck) {
        throw StateError(
          current.errorMessage ?? 'Test çıktısı yazıcıya teslim edilemedi.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Yazıcı test işi zaman aşımına uğradı.', timeout);
  }

  Future<void> confirm(
    PhysicalPrintTestDispatch dispatch, {
    required bool passed,
  }) async {
    await repository.resolvePhysicalConfirmation(
      dispatch.jobId,
      passed: passed,
    );
    final device = await repository.getDevice(dispatch.deviceId);
    if (device == null) return;
    final now = DateTime.now();
    await repository.saveDevice(PrinterDeviceProfile(
      id: device.id,
      name: device.name,
      language: device.language,
      transport: device.transport,
      transportConfig: device.transportConfig,
      capabilities: device.capabilities,
      enabled: device.enabled,
      lastTestedAt: now,
      lastTestSucceeded: passed,
      lastTestMessage: passed
          ? 'Fiziksel test çıktısı kullanıcı tarafından doğrulandı.'
          : 'Fiziksel test çıktısı kullanıcı tarafından reddedildi.',
      createdAt: device.createdAt,
      updatedAt: now,
    ));
  }

  static Map<String, Object?> _receiptPayload(List<int>? logo) => {
        'business': {'name': 'SERENUT OS'},
        'document': {
          'number': 'FIZIKSEL-TEST',
          'date': '04.08.2026 12:34',
          'payment': 'TEST',
          'customerName': 'Çağrı ŞĞİÖÜçşı',
          'total': 299.95,
          'paid': 299.95,
          'barcode': '1234567890',
        },
        'items': [
          {
            'name': 'Sağ kenar ölçüm ürünü',
            'quantity': 1,
            'unitPrice': 299.95,
          },
        ],
        'currency': 'TL',
        if (logo != null) 'logoEscPosBase64': base64Encode(logo),
      };

  Future<Map<String, Object?>> _payloadFor(
    PrintDocumentKind kind, [
    PrinterDeviceProfile? device,
  ]) async {
    final logo = await assets.loadLogo(null);
    final capabilities = device?.capabilities ?? const {};
    final config = device?.transportConfig ?? const {};
    final widthMm = (capabilities['mediaWidthMm'] as num?)?.toInt() ??
        (config['labelWidthMm'] as num?)?.toInt() ??
        50;
    final heightMm = (capabilities['mediaHeightMm'] as num?)?.toInt() ??
        (config['labelHeightMm'] as num?)?.toInt() ??
        30;
    final gapMm = (capabilities['gapMm'] as num?)?.toInt() ??
        (config['labelGapMm'] as num?)?.toInt() ??
        2;
    final dpi = (capabilities['dpi'] as num?)?.toInt() ??
        (config['dpi'] as num?)?.toInt() ??
        203;
    final printableWidthDots =
        (capabilities['printableWidthDots'] as num?)?.toInt() ??
            (config['printableWidthDots'] as num?)?.toInt();

    return switch (kind) {
      PrintDocumentKind.receipt => _receiptPayload(
          logo == null ? null : assets.toEscPosRaster(logo, maxWidth: 320)),
      PrintDocumentKind.productLabel => _labelPayload(
          logo,
          widthMm: widthMm,
          heightMm: heightMm,
          gapMm: gapMm,
          dpi: dpi,
          printableWidthDots: printableWidthDots,
        ),
      PrintDocumentKind.orderLabel => _orderLabelPayload(
          logo,
          widthMm: widthMm,
          heightMm: heightMm,
          gapMm: gapMm,
          dpi: dpi,
          printableWidthDots: printableWidthDots,
        ),
    };
  }

  static Map<String, Object?> _labelPayload(
    List<int>? logo, {
    int widthMm = 50,
    int heightMm = 30,
    int gapMm = 2,
    int dpi = 203,
    int? printableWidthDots,
  }) {
    final label = LabelModel(
      productName: 'Ürününüzün adı',
      businessName: 'SERENUT OS',
      weight: 1,
      price: 299.95,
      barcode: '1234567890',
      qrData: 'physical-test',
      timestamp: DateTime.utc(2026, 8, 4, 12, 34),
    );
    return {
      'labels': [label.toMap()],
      'labelWidthMm': widthMm,
      'labelHeightMm': heightMm,
      'labelGapMm': gapMm,
      'labelDpi': dpi,
      if (printableWidthDots != null) 'printableWidthDots': printableWidthDots,
      if (logo != null) 'logoBytesBase64': base64Encode(logo),
    };
  }

  static Map<String, Object?> _orderLabelPayload(
    List<int>? logo, {
    int widthMm = 50,
    int heightMm = 30,
    int gapMm = 2,
    int dpi = 203,
    int? printableWidthDots,
  }) =>
      {
        'orderNo': '12345678',
        'customerName': 'Çağrı Yılmaz',
        'productName': 'Sipariş ürünü',
        'quantity': 2.0,
        'items': [
          {
            'product_name': 'Sağ kenar ölçüm ürünü',
            'quantity': 2.0,
            'unit_price': 149.975,
          },
        ],
        'note': 'Özenle hazırlayınız',
        'timestamp': DateTime.utc(2026, 8, 4, 12, 34).toIso8601String(),
        'totalAmount': 299.95,
        'itemsCount': 1,
        'businessName': null, // Sipariş etiketinde işletme adı gösterilmez
        'labelWidthMm': widthMm,
        'labelHeightMm': heightMm,
        'labelGapMm': gapMm,
        'labelDpi': dpi,
        if (printableWidthDots != null) 'printableWidthDots': printableWidthDots,
      };
}
