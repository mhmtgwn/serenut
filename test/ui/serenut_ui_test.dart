import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/theme.dart';
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
}
