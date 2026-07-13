// test/ui/sales_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/presentation/pages/sales_page.dart';
import 'package:serenutos/presentation/widgets/sales/catalog_panel.dart';
import 'package:serenutos/presentation/widgets/sales/cart_panel.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    InMemoryDb.reset();
    
    // Add dummy products
    InMemoryDb.products.addAll([
      ProductEntity(
        id: 'prod-1',
        name: 'Test Kola',
        description: 'Soğuk içecek',
        price: 25.0,
        quantity: 100,
        category: 'İçecek',
        vat: 18,
      ),
      ProductEntity(
        id: 'prod-2',
        name: 'Test Burger',
        description: 'Yiyecek',
        price: 90.0,
        quantity: 50,
        category: 'Yiyecek',
        vat: 8,
      ),
    ]);
    
    // Add dummy customer
    InMemoryDb.customers.add(
      CustomerEntity(
        id: 'cust-1',
        name: 'Ahmet Yilmaz',
        email: 'ahmet@gmail.com',
        phone: '555-555-5555',
        balance: -50.0, // debtor
        createdAt: DateTime.now(),
      ),
    );

    // Initialize SharedPreferences mock
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget createTestWidget() {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        productRepositoryProvider.overrideWith((ref) => InMemoryProductRepository()),
        customerRepositoryProvider.overrideWith((ref) => InMemoryCustomerRepository()),
        saleRepositoryProvider.overrideWith((ref) => InMemorySaleRepository()),
        settingsRepositoryProvider.overrideWith((ref) => InMemorySettingsRepository()),
      ],
      child: const MaterialApp(
        home: SalesPage(),
      ),
    );
  }

  void setupWideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
  }

  void resetScreen(WidgetTester tester) {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  group('SalesPage Widget Tests', () {
    testWidgets('SalesPage loads catalog products and category buttons correctly', (WidgetTester tester) async {
      setupWideScreen(tester);
      addTearDown(() => resetScreen(tester));

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Verify page layout and CatalogPanel components exist
      expect(find.byType(CatalogPanel), findsOneWidget);
      expect(find.byType(CartPanel), findsOneWidget);

      // Verify dummy products are displayed in catalog list
      expect(find.text('Test Kola'), findsOneWidget);
      expect(find.text('Test Burger'), findsOneWidget);
      expect(find.textContaining('25'), findsWidgets);
      expect(find.textContaining('90'), findsWidgets);
    });

    testWidgets('Adding product to cart updates total price and list', (WidgetTester tester) async {
      setupWideScreen(tester);
      addTearDown(() => resetScreen(tester));

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Tap on 'Test Kola' card to add it to the cart
      await tester.tap(find.text('Test Kola'));
      await tester.pump(const Duration(seconds: 1));

      // Verify product is in the cart
      // CartPanel shows item name and quantities
      expect(find.descendant(of: find.byType(CartPanel), matching: find.text('Test Kola')), findsOneWidget);
      
      // Total price on checkout section should match product price (25.0)
      expect(find.textContaining('25'), findsWidgets);
    });

    testWidgets('Product search filters product catalog list', (WidgetTester tester) async {
      setupWideScreen(tester);
      addTearDown(() => resetScreen(tester));

      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Verify both products are visible
      expect(find.text('Test Kola'), findsOneWidget);
      expect(find.text('Test Burger'), findsOneWidget);

      // Find the search icon and tap it to reveal TextField
      final searchIconFinder = find.byTooltip('Ara');
      expect(searchIconFinder, findsOneWidget);
      await tester.tap(searchIconFinder);
      await tester.pump(const Duration(milliseconds: 500));

      // Find the search textfield and enter 'Burger'
      final searchFinder = find.byType(TextField);
      expect(searchFinder, findsOneWidget);
      await tester.enterText(searchFinder, 'Burger');
      
      // Async pumping sequence to trigger the notifier, await future, and rebuild UI
      await tester.pump(); 
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // Verify Test Burger is visible while Test Kola is filtered out
      expect(find.text('Test Burger'), findsOneWidget);
      expect(find.text('Test Kola'), findsNothing);
    });
  });
}
