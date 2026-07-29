import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/widgets/branded_splash_screen.dart';

void main() {
  testWidgets('splash shows current startup status and progress',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(useGoogleFonts: false),
        home: const BrandedSplashScreen(
          status: 'Sistem kontrol ediliyor',
          detail: 'Veriler hazırlanıyor',
          progress: 0.42,
        ),
      ),
    );

    expect(find.text('Serenut OS'), findsOneWidget);
    expect(find.text('Sistem kontrol ediliyor'), findsOneWidget);
    expect(find.text('Veriler hazırlanıyor'), findsOneWidget);
    expect(find.text('%42'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('splash exposes retry action after a startup error',
      (tester) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(useGoogleFonts: false),
        home: BrandedSplashScreen(
          status: 'Sistem kontrol ediliyor',
          error: 'Bağlantı kurulamadı',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Başlatma tamamlanamadı'), findsOneWidget);
    expect(find.text('Bağlantı kurulamadı'), findsOneWidget);
    await tester.tap(find.text('Tekrar Dene'));
    expect(retried, isTrue);
  });
}
