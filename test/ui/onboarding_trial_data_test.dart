import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_state.dart';
import 'package:serenutos/presentation/pages/onboarding/steps/step1_business_info.dart';

void main() {
  test('setup defaults to demo mode', () {
    const state = OnboardingState();

    expect(state.initialData.mode, SetupMode.demo);

    final restored = OnboardingState.fromJson(state.toJson());
    expect(restored.initialData.mode, SetupMode.demo);
  });

  test('standard setup choice survives serialization', () {
    const state = OnboardingState(
      initialData: InitialDataSetup(mode: SetupMode.standard),
    );

    final restored = OnboardingState.fromJson(state.toJson());
    expect(restored.initialData.mode, SetupMode.standard);
  });

  testWidgets('setup screen offers demo and standard installation modes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Step1BusinessInfo(
          initialData: const BusinessInfo(),
          initialSetup: const InitialDataSetup(),
          onComplete: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Demo ile başla'), findsOneWidget);
    expect(find.text('Kendi işletmemle başla'), findsOneWidget);
    expect(find.textContaining('Mehmet Güven'), findsOneWidget);
    expect(find.text('Müşteriyi sıfırla'), findsNothing);
  });
}
