import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Define multi-device viewport size matrix matching terminal and mobile devices
  final deviceMatrices = [
    {'name': 'Sunmi V2s Pocket POS', 'width': 320.0, 'height': 640.0},
    {'name': 'Standard Terminal Mobile', 'width': 360.0, 'height': 800.0},
    {'name': 'Sunmi Desktop / V2s Logic', 'width': 480.0, 'height': 800.0},
    {'name': 'Large Screen Tablet POS', 'width': 768.0, 'height': 1024.0},
  ];

  for (final device in deviceMatrices) {
    testWidgets('UI Firewall Stress Check - ${device['name']}', (WidgetTester tester) async {
      // Setup dynamic viewport parameters
      final double width = device['width'] as double;
      final double height = device['height'] as double;
      tester.view.physicalSize = Size(width * 3.0, height * 3.0);
      tester.view.devicePixelRatio = 3.0;

      // 🔴 Dynamic UI Overflow Listener: Interrupt & Fail Build on any render overflow message
      String? overflowMessage;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exception.toString().contains('overflow') || 
            details.toString().contains('A RenderFlex overflowed')) {
          overflowMessage = details.exception.toString();
        }
        originalOnError?.call(details);
      };

      // Mock UI widget incorporating long data sequences to test resilience
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: height,
              child: ListView(
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.person),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Extremely Long Customer Name That Will Wrap Or Overflow If Not Expanded Properly',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'extremely.long.customer.email.address.that.goes.on.and.on.and.on@example.com',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(
                          10,
                          (index) => Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Colors.grey[300],
                            child: Text('Preset Date Picker $index'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Verify no exceptions were recorded
      expect(tester.takeException(), isNull);
      // Assert that the overflow hook remained clean
      expect(overflowMessage, isNull, reason: '🔴 UI FIREWALL FAILURE: Layout overflow detected on ${device['name']}! Details: $overflowMessage');

      // Tear down device-specific viewport configurations
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });
    });
  }
}
