import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/printing/sqlite_printing_application_service.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_printing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqlitePrintingRepository repository;
  late SqlitePrintingApplicationService service;

  final settings = Settings(
    businessName: 'Serenut Market',
    businessPhone: '0212 000 00 00',
    businessAddress: 'İstanbul',
  );

  PrintDesignProfile profile(PrintDocumentKind kind) => PrintDesignProfile(
        id: 'design-${kind.name}',
        name: kind.name,
        kind: kind,
        schemaVersion: 1,
        rendererVersion: switch (kind) {
          PrintDocumentKind.receipt => 'escpos-v1',
          PrintDocumentKind.productLabel => 'tspl-product-v1',
          PrintDocumentKind.orderLabel => 'tspl-order-v1',
        },
        definition: const {'showLogo': true, 'showBarcode': true},
        isDefault: true,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  PrinterDeviceProfile device({
    required String id,
    required PrinterLanguage language,
    required Map<String, Object?> capabilities,
  }) =>
      PrinterDeviceProfile(
        id: id,
        name: id,
        language: language,
        transport: PrinterTransportKind.tcp,
        transportConfig: const {'host': '127.0.0.1', 'port': 9100},
        capabilities: capabilities,
        enabled: true,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseSchema.createTables(db);
    repository = SqlitePrintingRepository(DbGatewayImpl.raw(db));
    final coordinator = PrintQueueCoordinator(
      repository: repository,
      renderers: const [],
      transports: const [],
    );
    service = SqlitePrintingApplicationService(
      repository: repository,
      runtime:
          PrintingRuntime(repository: repository, coordinator: coordinator),
    );

    for (final kind in PrintDocumentKind.values) {
      await repository.saveDesignProfile(profile(kind));
    }
    await repository.saveDevice(device(
      id: 'receipt-58',
      language: PrinterLanguage.escPos,
      capabilities: const {'paperWidthMm': 58, 'printableWidthDots': 384},
    ));
    await repository.saveDevice(device(
      id: 'label-50x30',
      language: PrinterLanguage.tspl,
      capabilities: const {
        'mediaWidthMm': 50,
        'mediaHeightMm': 30,
        'gapMm': 2,
        'dpi': 203,
      },
    ));
    await repository.saveRoute(PrinterRoute(
      kind: PrintDocumentKind.receipt,
      deviceId: 'receipt-58',
      designProfileId: 'design-receipt',
      updatedAt: DateTime.utc(2026),
    ));
    for (final kind in [
      PrintDocumentKind.productLabel,
      PrintDocumentKind.orderLabel,
    ]) {
      await repository.saveRoute(PrinterRoute(
        kind: kind,
        deviceId: 'label-50x30',
        designProfileId: 'design-${kind.name}',
        updatedAt: DateTime.utc(2026),
      ));
    }
  });

  tearDown(() => db.close());

  test('sale receipt snapshots the routed 58 mm device', () async {
    final sale = SaleEntity(
      id: 'sale-123456789',
      customerId: 'customer-1',
      totalAmount: 125,
      paidAmount: 100,
      paymentMethod: 'cash',
      status: 'completed',
      createdAt: DateTime.utc(2026, 8, 4, 12, 30),
      items: const [],
    );

    final job = await service.queueSaleReceipt(
      sale,
      const [
        {'product_name': 'Türk Kahvesi', 'quantity': 1, 'unit_price': 125},
      ],
      null,
      settings,
    );

    expect(job.deviceId, 'receipt-58');
    expect(jsonDecode(job.capabilitySnapshotJson)['paperWidthMm'], 58);
    final payload = jsonDecode(job.payloadJson) as Map<String, dynamic>;
    expect(payload['document']['number'], 'sale-123');
    expect(payload['items'], hasLength(1));
  });

  test('product labels create one immutable job per product', () async {
    final products = [
      ProductEntity(
        id: '869000000001',
        name: 'Ürün Bir',
        description: '',
        price: 29.95,
        quantity: 10,
        category: 'Genel',
      ),
      ProductEntity(
        id: '869000000002',
        name: 'Ürün İki',
        description: '',
        price: 39.95,
        quantity: 5,
        category: 'Genel',
      ),
    ];

    final jobs = await service.queueProductLabels(products, settings);

    expect(jobs, hasLength(2));
    expect(jobs.map((job) => job.deviceId).toSet(), {'label-50x30'});
    expect(
      jobs.map((job) => (jsonDecode(job.payloadJson)['labels'] as List)
          .single['productName']),
      ['Ürün Bir', 'Ürün İki'],
    );
  });

  test('order label creates one aggregate job for the entire order', () async {
    final items = <Map<String, dynamic>>[
      {'product_name': 'Gömlek', 'quantity': 2, 'unit_price': 100},
      {'product_name': 'Pantolon', 'quantity': 1, 'unit_price': 250},
    ];
    final order = OrderEntity(
      id: 'order-123456789',
      customerId: 'customer-1',
      status: 'created',
      createdAt: DateTime.utc(2026, 8, 4),
      items: items,
    );

    final job = await service.queueOrderLabel(order, items, settings);
    final payload = jsonDecode(job.payloadJson) as Map<String, dynamic>;

    expect(job.kind, PrintDocumentKind.orderLabel);
    expect(job.deviceId, 'label-50x30');
    expect(payload['items'], hasLength(2));
    expect(payload['productName'], '2 Ürün / Paket');
    expect(await repository.getJobs(), hasLength(1));
  });
}
