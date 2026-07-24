import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/presentation/pages/settings/hardware_test_page.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';

class _FakeHardwareDevicesNotifier extends HardwareDevicesNotifier {
  @override
  Future<List<HardwareDevice>> build() async => const [
        HardwareDevice(
          id: 'scale-1',
          name: 'Kasa Terazisi',
          type: HardwareDeviceType.scale,
          connectionType: HardwareConnectionType.serial,
          status: HardwareDeviceStatus.ready,
          lastMessage: 'Terazi bağlantısı hazır',
        ),
      ];
}

void main() {
  testWidgets('renders persisted devices and opens the three-step add flow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hardwareDevicesProvider
              .overrideWith(_FakeHardwareDevicesNotifier.new),
        ],
        child: const MaterialApp(home: HardwareTestPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cihazlar ve Donanım'), findsOneWidget);
    expect(find.text('Kasa Terazisi'), findsOneWidget);
    expect(find.text('Hazır'), findsWidgets);

    await tester.tap(find.byTooltip('Cihaz ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni cihaz ekle'), findsOneWidget);
    expect(find.textContaining('1/3'), findsOneWidget);
    expect(find.text('Fiş yazıcısı'), findsWidgets);
    expect(find.text('Terazi'), findsWidgets);
  });
}
