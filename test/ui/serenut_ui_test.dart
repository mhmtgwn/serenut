import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/presentation/widgets/serenut_ui.dart';

void main() {
  Widget app(Widget child, {double width = 390}) {
    return MaterialApp(
      theme: AppTheme.build(useGoogleFonts: false),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(body: SizedBox(width: width, child: child)),
      ),
    );
  }

  testWidgets('section header does not overflow on a narrow phone',
      (tester) async {
    await tester.pumpWidget(
      app(
        const Padding(
          padding: EdgeInsets.all(16),
          child: SerenutSectionHeader(
            eyebrow: 'SERENUT OS',
            title: 'Müşteriler',
            description: 'Cari hesapları ve iletişim bilgilerini yönetin.',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(onPressed: null, icon: Icon(Icons.refresh)),
                IconButton(onPressed: null, icon: Icon(Icons.settings)),
              ],
            ),
          ),
        ),
        width: 320,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Müşteriler'), findsOneWidget);
  });

  testWidgets('surface uses website card tokens', (tester) async {
    await tester.pumpWidget(app(const SerenutSurface(child: Text('Kart'))));

    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text('Kart'), matching: find.byType(Container))
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, POSColors.card);
    expect(decoration.borderRadius, BorderRadius.circular(AppRadii.md));
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('mobile POS header keeps search and filter collapsed',
      (tester) async {
    var searching = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(useGoogleFonts: false),
          home: StatefulBuilder(
            builder: (context, setState) => MediaQuery(
              data: const MediaQueryData(size: Size(336, 640)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 336,
                    child: PosHeader(
                      title: 'Ürünler',
                      isSearching: searching,
                      onSearchToggled: (value) =>
                          setState(() => searching = value),
                      searchController: TextEditingController(),
                      searchHint: 'Ürün ara',
                      onSearchChanged: (_) {},
                      filterWidget: const Text('Kategori filtresi'),
                      showSettings: false,
                      showStatusIndicator: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('SERENUT OS'), findsNothing);
    expect(find.text('Ürün ara'), findsNothing);
    expect(find.text('Kategori filtresi'), findsNothing);
    expect(find.byTooltip('Ara ve filtrele'), findsOneWidget);

    await tester.tap(find.byTooltip('Ara ve filtrele'));
    await tester.pump();

    expect(find.text('Ürün ara'), findsOneWidget);
    expect(find.text('Kategori filtresi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
