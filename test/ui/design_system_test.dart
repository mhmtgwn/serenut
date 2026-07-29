import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/theme.dart';

void main() {
  group('Serenut design system', () {
    test('website and mobile share the same brand tokens', () {
      expect(POSColors.green, const Color(0xFF11875D));
      expect(POSColors.greenDark, const Color(0xFF086B48));
      expect(POSColors.surface, const Color(0xFFF5F7F5));
      expect(POSColors.text, const Color(0xFF19231F));
      expect(POSColors.border, const Color(0xFFDFE6E1));
    });

    test('global component themes use centralized tokens', () {
      final theme = AppTheme.build(useGoogleFonts: false);

      expect(theme.colorScheme.primary, POSColors.green);
      expect(theme.scaffoldBackgroundColor, POSColors.surface);
      expect(theme.cardTheme.color, POSColors.card);
      expect(theme.dialogTheme.backgroundColor, POSColors.card);
      expect(
        theme.navigationBarTheme.backgroundColor,
        POSColors.navBackground,
      );
    });

    testWidgets('standard controls inherit the application theme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(useGoogleFonts: false),
          home: const Scaffold(
            body: Column(
              children: [
                Card(child: Text('Kart')),
                TextField(),
                FilledButton(onPressed: null, child: Text('Kaydet')),
              ],
            ),
          ),
        ),
      );

      final context = tester.element(find.text('Kart'));
      expect(Theme.of(context).colorScheme.primary, POSColors.green);
      expect(Theme.of(context).scaffoldBackgroundColor, POSColors.surface);
    });
  });
}
