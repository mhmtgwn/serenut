// test/ui/home_qr_scanner_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/widgets/home/qr_order_scanner_dialog.dart';
import 'package:serenutos/providers/repository_providers.dart';

class _FakeOrderRepository implements IOrderRepository {
  final Map<String, OrderEntity> orders = {};

  @override
  Future<OrderEntity?> findById(dynamic id) async {
    return orders[id.toString()];
  }

  @override
  Future<List<OrderEntity>> findFiltered({
    String? searchQuery,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool overdueOnly = false,
    int limit = 25,
    int offset = 0,
  }) async {
    if (searchQuery != null && searchQuery.isNotEmpty) {
      return orders.values
          .where((o) => o.id.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }
    return orders.values.toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSaleRepository implements ISaleRepository {
  final Map<String, SaleEntity> sales = {};

  @override
  Future<SaleEntity?> findById(dynamic id) async {
    return sales[id.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepository implements IProductRepository {
  @override
  Future<List<ProductEntity>> findFiltered({
    String? searchQuery,
    String? category,
    String? stockFilter,
    String? sortBy,
    int? limit,
    int? offset,
  }) async {
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeOrderRepository fakeOrderRepo;
  late _FakeSaleRepository fakeSaleRepo;
  late _FakeProductRepository fakeProductRepo;

  setUp(() {
    fakeOrderRepo = _FakeOrderRepository();
    fakeSaleRepo = _FakeSaleRepository();
    fakeProductRepo = _FakeProductRepository();
  });

  Widget buildTestApp(Widget child) {
    return ProviderScope(
      overrides: [
        orderRepositoryProvider.overrideWith((ref) async => fakeOrderRepo),
        saleRepositoryProvider.overrideWith((ref) async => fakeSaleRepo),
        productRepositoryProvider.overrideWith((ref) async => fakeProductRepo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => QrOrderScannerDialog.show(context),
                child: const Text('Tarayıcıyı Aç'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders QR and Barcode scanner dialog with input controls',
      (tester) async {
    await tester.pumpWidget(buildTestApp(const SizedBox()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tarayıcıyı Aç'));
    await tester.pumpAndSettle();

    expect(find.text('Sipariş & Satış QR Okuyucu'), findsOneWidget);
    expect(find.text('Fiş QR kodunu veya barkodunu okutun'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Bul & Aç'), findsOneWidget);
  });

  testWidgets('shows error message when order is not found', (tester) async {
    await tester.pumpWidget(buildTestApp(const SizedBox()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tarayıcıyı Aç'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'SIP-BILINMEYEN');
    await tester.pump(); // Button enabled state rebuild
    await tester.tap(find.text('Bul & Aç'));
    await tester.pumpAndSettle();

    expect(
      find.text('"SIP-BILINMEYEN" koduna ait sipariş veya satış bulunamadı.'),
      findsOneWidget,
    );
  });

  testWidgets('resolves order|<id> format correctly', (tester) async {
    final testOrder = OrderEntity(
      id: 'ord-12345',
      orderNumber: 'SIP-001',
      customerId: 'cust-1',
      items: const [],
      status: 'preparing',
      createdAt: DateTime.now(),
      notes: 'Test Siparişi',
    );
    fakeOrderRepo.orders['ord-12345'] = testOrder;

    await tester.pumpWidget(buildTestApp(const SizedBox()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tarayıcıyı Aç'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'order|ord-12345');
    await tester.pump(); // Button enabled state rebuild
    await tester.tap(find.text('Bul & Aç'));
    await tester.pumpAndSettle();

    // Dialog kapandı ve sipariş detayını açtı
    expect(find.text('Sipariş & Satış QR Okuyucu'), findsNothing);
  });
}
