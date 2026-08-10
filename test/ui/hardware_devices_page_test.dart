import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/presentation/pages/settings/hardware_test_page.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';

class _FakeHardwareDevicesNotifier extends HardwareDevicesNotifier {
  static int verifyCalls = 0;
  static int saveCalls = 0;

  @override
  Future<List<HardwareDevice>> build() async => const [
        HardwareDevice(
          id: 'scale-1',
          name: 'Kasa Terazisi',
          type: HardwareDeviceType.scale,
          connectionType: HardwareConnectionType.serial,
          configuration: {
            'serialPort': 'COM3',
            'baudRate': 9600,
            'isActive': true,
          },
          status: HardwareDeviceStatus.ready,
          lastMessage: 'Terazi bağlantısı hazır',
        ),
        HardwareDevice(
          id: 'printer-1',
          name: 'Kasa Yazıcısı',
          type: HardwareDeviceType.receiptPrinter,
          connectionType: HardwareConnectionType.windows,
          configuration: {'printerName': 'Test Printer'},
          status: HardwareDeviceStatus.unverified,
        ),
      ];

  @override
  Future<HardwareTestResult> verify(HardwareDevice device) async {
    verifyCalls++;
    return HardwareTestResult(
      success: true,
      message: 'Bağlantı hazır',
      elapsed: const Duration(milliseconds: 1),
      completedAt: DateTime(2026, 8, 10),
    );
  }

  @override
  Future<void> save(HardwareDevice device) async {
    saveCalls++;
  }
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

    expect(find.text('Aygıt Yöneticisi'), findsOneWidget);
    expect(find.text('Kasa Terazisi'), findsOneWidget);
    expect(find.text('Test başarılı'), findsWidgets);

    await tester.tap(find.byTooltip('Cihaz ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni cihaz ekle'), findsOneWidget);
    expect(find.textContaining('1/3'), findsOneWidget);
    expect(find.text('Fiş yazıcısı'), findsWidgets);
    expect(find.text('Terazi'), findsWidgets);
  });

  testWidgets('editing starts at settings and save does not force a test',
      (tester) async {
    _FakeHardwareDevicesNotifier.verifyCalls = 0;
    _FakeHardwareDevicesNotifier.saveCalls = 0;
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

    await tester.tap(find.text('Kasa Terazisi'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3/3'), findsOneWidget);
    expect(find.text('Bağlantıyı kontrol et'), findsOneWidget);
    expect(find.text('Ayarları kaydet'), findsOneWidget);

    await tester.tap(find.text('Ayarları kaydet'));
    await tester.pumpAndSettle();

    expect(_FakeHardwareDevicesNotifier.saveCalls, 1);
    expect(_FakeHardwareDevicesNotifier.verifyCalls, 0);
  });

  testWidgets('device filters separate printers from sales hardware',
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

    await tester.tap(find.text('Yazıcılar (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Kasa Yazıcısı'), findsOneWidget);
    expect(find.text('Kasa Terazisi'), findsNothing);

    await tester.tap(find.text('Satış donanımı (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Kasa Terazisi'), findsOneWidget);
    expect(find.text('Kasa Yazıcısı'), findsNothing);
  });

  testWidgets('add flow remains usable on a narrow mobile viewport',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
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
    await tester.tap(find.byTooltip('Cihaz ekle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(find.text('Windows'), findsWidgets);
    expect(find.text('TCP / Ağ'), findsWidgets);
    expect(find.text('Bluetooth'), findsNothing);
    expect(find.text('Dahili'), findsNothing);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Cihazı kaydet'), findsOneWidget);
    expect(find.text('Bağlantıyı kontrol et'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('android label printers do not offer an ESC/POS embedded path',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
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
    await tester.tap(find.byTooltip('Cihaz ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etiket yazıcısı').first);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth'), findsWidgets);
    expect(find.text('TCP / Ağ'), findsWidgets);
    expect(find.text('Dahili'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
