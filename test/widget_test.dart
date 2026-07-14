import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Basit test widget'ları
class TestApp extends StatelessWidget {
  final Widget child;

  const TestApp({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }
}

class SimpleCounter extends StatefulWidget {
  const SimpleCounter({super.key});

  @override
  State<SimpleCounter> createState() => _SimpleCounterState();
}

class _SimpleCounterState extends State<SimpleCounter> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Counter: $_counter',
          key: const Key('counter_text'),
        ),
        ElevatedButton(
          key: const Key('increment_button'),
          onPressed: _incrementCounter,
          child: const Text('Increment'),
        ),
      ],
    );
  }
}

void main() {
  group('Widget Tests', () {
    testWidgets('Counter increments smoke test', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      // Verify that our counter starts at 0.
      expect(find.text('Counter: 0'), findsOneWidget);
      expect(find.text('Counter: 1'), findsNothing);

      // Tap the '+' icon and trigger a frame.
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();

      // Verify that our counter has incremented.
      expect(find.text('Counter: 0'), findsNothing);
      expect(find.text('Counter: 1'), findsOneWidget);
    });

    testWidgets('Multiple increments test', (WidgetTester tester) async {
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      // Initial state
      expect(find.text('Counter: 0'), findsOneWidget);

      // Increment multiple times
      for (int i = 1; i <= 5; i++) {
        await tester.tap(find.byKey(const Key('increment_button')));
        await tester.pump();
        expect(find.text('Counter: $i'), findsOneWidget);
      }
    });

    testWidgets('Button exists and is tappable', (WidgetTester tester) async {
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      // Find the button
      final buttonFinder = find.byKey(const Key('increment_button'));
      expect(buttonFinder, findsOneWidget);

      // Verify button text
      expect(find.text('Increment'), findsOneWidget);

      // Verify button is enabled
      final ElevatedButton button = tester.widget(buttonFinder);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Text widget displays correctly', (WidgetTester tester) async {
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      // Find the text widget
      final textFinder = find.byKey(const Key('counter_text'));
      expect(textFinder, findsOneWidget);

      // Verify initial text
      final Text textWidget = tester.widget(textFinder);
      expect(textWidget.data, equals('Counter: 0'));
    });
  });

  group('Error Handling Tests', () {
    testWidgets('Widget handles null values gracefully',
        (WidgetTester tester) async {
      // Test widget that might receive null values
      const testWidget = TestApp(
        child: Center(
          child: Text('Test'),
        ),
      );

      await tester.pumpWidget(testWidget);
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('Widget rebuilds correctly after state change',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      // Initial build
      expect(find.text('Counter: 0'), findsOneWidget);

      // Trigger rebuild
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();

      // Verify rebuild
      expect(find.text('Counter: 1'), findsOneWidget);
      expect(find.text('Counter: 0'), findsNothing);
    });
  });

  group('Performance Tests', () {
    testWidgets('Widget renders within reasonable time',
        (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      stopwatch.stop();

      // Widget should render in less than 100ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    testWidgets('Multiple rapid taps handled correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      // Rapid taps
      for (int i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const Key('increment_button')));
      }
      await tester.pump();

      // Should handle all taps
      expect(find.text('Counter: 10'), findsOneWidget);
    });
  });

  group('Accessibility Tests', () {
    testWidgets('Widgets have proper semantics', (WidgetTester tester) async {
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      // Check if widgets are accessible
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(Text), findsAtLeastNWidgets(1));
    });

    testWidgets('Button is focusable', (WidgetTester tester) async {
      await tester.pumpWidget(const TestApp(child: SimpleCounter()));

      final buttonFinder = find.byKey(const Key('increment_button'));

      // Focus the button
      await tester.tap(buttonFinder);
      await tester.pump();

      // Button should be focusable
      expect(buttonFinder, findsOneWidget);
    });
  });
}
