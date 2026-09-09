import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/presentation/widgets/sales/product_filter_sort_dialog.dart';

void main() {
  group('ProductFilterSortDialog Tests', () {
    final categories = ['Tatlı', 'İçecek', 'Kahve', 'Unlu Mamul'];

    testWidgets('renders dialog with sort and category options',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? appliedCategory;
      String? appliedSort;
      String? appliedStock;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ProductFilterSortDialog.show(
                    context: context,
                    initialCategory: null,
                    initialSort: null,
                    initialStock: null,
                    categories: categories,
                    onApply: ({
                      required category,
                      required sortBy,
                      required stockFilter,
                    }) {
                      appliedCategory = category;
                      appliedSort = sortBy;
                      appliedStock = stockFilter;
                    },
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      // Open the modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Sıralama ve Filtreleme'), findsOneWidget);

      // Verify Sort Options
      expect(find.text('En Çok Satanlar'), findsOneWidget);
      expect(find.text('Kategoriye Göre'), findsOneWidget);
      expect(find.text('Ürün Adı (A → Z)'), findsOneWidget);
      expect(find.text('Ürün Adı (Z → A)'), findsOneWidget);
      expect(find.text('Fiyat: Düşükten Yükseğe'), findsOneWidget);
      expect(find.text('Fiyat: Yüksekten Düşüğe'), findsOneWidget);

      // Verify Categories
      expect(find.text('Tatlı'), findsOneWidget);
      expect(find.text('İçecek'), findsOneWidget);
      expect(find.text('Kahve'), findsOneWidget);

      // Tap "En Çok Satanlar"
      await tester.tap(find.text('En Çok Satanlar'));
      await tester.pumpAndSettle();

      // Tap category "Tatlı"
      await tester.tap(find.text('Tatlı'));
      await tester.pumpAndSettle();

      // Tap "Uygula"
      await tester.tap(find.text('Uygula'));
      await tester.pumpAndSettle();

      // Modal should be closed
      expect(find.text('Sıralama ve Filtreleme'), findsNothing);

      // onApply must have received the chosen options
      expect(appliedSort, 'best_selling');
      expect(appliedCategory, 'Tatlı');
      expect(appliedStock, isNull);
    });

    testWidgets('allows sorting by Category and Name', (tester) async {
      String? appliedSort;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ProductFilterSortDialog.show(
                    context: context,
                    initialCategory: null,
                    initialSort: null,
                    initialStock: null,
                    categories: categories,
                    onApply: ({
                      required category,
                      required sortBy,
                      required stockFilter,
                    }) {
                      appliedSort = sortBy;
                    },
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Tap "Kategoriye Göre"
      await tester.tap(find.text('Kategoriye Göre'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Uygula'));
      await tester.pumpAndSettle();

      expect(appliedSort, 'category');
    });

    testWidgets('reset button clears active filters', (tester) async {
      String? appliedCategory = 'initial';
      String? appliedSort = 'initial';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ProductFilterSortDialog.show(
                    context: context,
                    initialCategory: 'Tatlı',
                    initialSort: 'best_selling',
                    initialStock: 'in_stock',
                    categories: categories,
                    onApply: ({
                      required category,
                      required sortBy,
                      required stockFilter,
                    }) {
                      appliedCategory = category;
                      appliedSort = sortBy;
                    },
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Reset button should be visible because initial filters are active
      expect(find.text('Sıfırla'), findsOneWidget);
      await tester.tap(find.text('Sıfırla'));
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.text('Uygula'));
      await tester.pumpAndSettle();

      expect(appliedCategory, isNull);
      expect(appliedSort, isNull);
    });
  });
}
