import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/pages/onboarding/splash_screen.dart';

GoRouter _testRouter() => GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingSplashScreen(),
        ),
        GoRoute(
          path: '/onboarding/business',
          builder: (_, __) => const Scaffold(
            body: Text('İşletme kurulum adımı'),
          ),
        ),
        GoRoute(
          path: '/onboarding/license',
          builder: (_, __) => const Scaffold(
            body: Text('Lisans aktivasyon adımı'),
          ),
        ),
      ],
    );

Widget _testApp(GoRouter router) => MaterialApp.router(
      theme: AppTheme.build(useGoogleFonts: false),
      routerConfig: router,
    );

void main() {
  testWidgets('onboarding shows product identity and both activation paths',
      (tester) async {
    final router = _testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    expect(find.text('Serenut OS'), findsOneWidget);
    expect(find.text('Perakende Yönetim Sistemi'), findsOneWidget);
    expect(find.text('30 Gün Ücretsiz Dene'), findsOneWidget);
    expect(find.text('Lisans Anahtarı Gir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding actions navigate to business and license flows',
      (tester) async {
    final router = _testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_testApp(router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('30 Gün Ücretsiz Dene'));
    await tester.pumpAndSettle();
    expect(find.text('İşletme kurulum adımı'), findsOneWidget);

    router.go('/onboarding');
    await tester.pumpAndSettle();
    final licenseAction = find.text('Lisans Anahtarı Gir');
    await tester.ensureVisible(licenseAction);
    await tester.tap(licenseAction);
    await tester.pumpAndSettle();
    expect(find.text('Lisans aktivasyon adımı'), findsOneWidget);
  });
}
