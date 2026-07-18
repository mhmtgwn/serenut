import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/services/customer_search_service.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    InMemoryDb.reset();

    // Seed 60 alphabetical customers starting with A..L so Mehmet is not in the first 50
    for (int i = 1; i <= 60; i++) {
      final prefixChar = String.fromCharCode(65 + (i % 12)); // A to L
      final name = '$prefixChar-Customer-$i';
      InMemoryDb.customers.add(
        CustomerEntity(
          id: 'cust-$i',
          name: name,
          email: 'customer$i@example.com',
          phone: '555000${i.toString().padLeft(4, "0")}',
          balance: 0.0,
          createdAt: DateTime.now(),
        ),
      );
    }

    // Add target test customers
    InMemoryDb.customers.add(
      CustomerEntity(
        id: 'cust-target-1',
        name: 'Mehmet Yılmaz',
        email: 'mehmet@example.com',
        phone: '5551234567',
        balance: 0.0,
        createdAt: DateTime.now(),
      ),
    );

    InMemoryDb.customers.add(
      CustomerEntity(
        id: 'cust-target-2',
        name: 'Müşerref Aksoy',
        email: 'muserref@example.com',
        phone: '5559998888',
        balance: 0.0,
        createdAt: DateTime.now(),
      ),
    );

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget createTestWidget() {
    final customerRepo = InMemoryCustomerRepository();
    final searchService = CustomerSearchService(customerRepo);

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        customerRepositoryProvider.overrideWith((ref) => customerRepo),
        customerSearchServiceProvider.overrideWith((ref) => searchService),
        productRepositoryProvider
            .overrideWith((ref) => InMemoryProductRepository()),
        orderRepositoryProvider
            .overrideWith((ref) => InMemoryOrderRepository()),
        settingsRepositoryProvider
            .overrideWith((ref) => InMemorySettingsRepository()),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OrderCreationDialog(),
        ),
      ),
    );
  }

  group('OrderCreationDialog Customer Step UI Tests', () {
    testWidgets(
        'Entering search term triggers query provider & refreshes list dynamically',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Verify that initial state loads A-Customer etc.
      expect(find.textContaining('Customer'), findsWidgets);

      // Verify Mehmet is NOT in the initial view (due to 50-limit pagination and alphabetical ordering A..L)
      expect(find.text('Mehmet Yılmaz'), findsNothing);

      // Find the Customer Search TextField
      final searchFieldFinder = find.byType(TextField);
      expect(searchFieldFinder, findsOneWidget);

      // Enter 'Mehmet'
      await tester.enterText(searchFieldFinder, 'Mehmet');
      await tester.pump(); // Trigger onChanged timer

      // Advance time past the 300ms debounce
      await tester.pump(const Duration(milliseconds: 400));

      // Let Riverpod notifier state update and rebuild UI
      await tester.pumpAndSettle();

      // Mehmet should now be visible!
      expect(find.text('Mehmet Yılmaz'), findsOneWidget);
      // Alphabetical 'A' customers should be filtered out
      expect(find.textContaining('A-Customer'), findsNothing);

      // Enter Mehmet's phone number
      await tester.enterText(searchFieldFinder, '5551234567');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Mehmet Yılmaz'), findsOneWidget);

      // Enter Müşerref's phone number
      await tester.enterText(searchFieldFinder, '5559998888');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Müşerref should be visible!
      expect(find.text('Müşerref Aksoy'), findsOneWidget);
      expect(find.text('Mehmet Yılmaz'), findsNothing);

      // Clear with the actual UI action. The field is rebuilt after each
      // provider result, so enterText('') may target an already-empty visual
      // field and does not model what a user does here.
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Reset to original paginated list
      expect(find.textContaining('Customer'), findsWidgets);
      expect(find.text('Müşerref Aksoy'), findsNothing);
    });
  });
}
