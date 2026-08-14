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

class _OfflineHardwareDevicesNotifier extends HardwareDevicesNotifier {
  @override
  Future<List<HardwareDevice>> build() async => const [
        HardwareDevice(
          id: 'offline-printer',
          name: 'Uzun isimli ana kasa fiş yazıcısı',
          type: HardwareDeviceType.receiptPrinter,
          connectionType: HardwareConnectionType.tcp,
          configuration: {
            'host': '192.168.100.200',
            'port': 9100,
            'activeFor': ['receipt'],
          },
          status: HardwareDeviceStatus.offline,
          lastError: 'Yazıcıya son kontrolde bağlanılamadı.',
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

    expect(find.text('Aygıt Yöneticisi'), findsOneWidget);
    expect(find.text('Kasa Terazisi'), findsOneWidget);
    expect(find.text('Hazır'), findsWidgets);
    expect(find.byTooltip('Bağlantıları yenile'), findsOneWidget);
    expect(find.byTooltip('Ortak yazıcılar'), findsOneWidget);
    expect(find.byTooltip('Yönetici işlemleri'), findsNothing);

    await tester.tap(find.byTooltip('Aygıt ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni aygıt ekle'), findsOneWidget);
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

    expect(find.textContaining('3/3'), findsNothing);
    expect(find.textContaining('Aygıt ayarları'), findsOneWidget);
    expect(find.text('Genel bilgiler'), findsOneWidget);
    expect(find.text('Bağlantı'), findsOneWidget);
    expect(find.text('Donanım özellikleri'), findsOneWidget);
    expect(find.text('Bağlantıyı test et'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Aygıt ekle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(find.text('Windows'), findsWidgets);
    expect(find.text('TCP / Ağ'), findsWidgets);
    expect(find.text('Bluetooth'), findsWidgets);
    expect(find.text('Dahili'), findsNothing);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Aygıtı kaydet'), findsOneWidget);
    expect(find.text('Bağlantıyı test et'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(TextField).first);
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.pumpAndSettle();
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
    await tester.tap(find.byTooltip('Aygıt ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etiket yazıcısı').first);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth'), findsWidgets);
    expect(find.text('TCP / Ağ'), findsWidgets);
    expect(find.text('Dahili'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('embedded receipt printer explains its automatic connection',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
    await tester.tap(find.byTooltip('Aygıt ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dahili'));
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Uygulama bu cihazdaki dahili yazıcıyı otomatik olarak kullanır.',
      ),
      findsOneWidget,
    );
    expect(find.text('Donanım özellikleri'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('receipt copy count is validated instead of silently reset',
      (tester) async {
    _FakeHardwareDevicesNotifier.saveCalls = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
    await tester.tap(find.byTooltip('Aygıt ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dahili'));
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    final copies = find.widgetWithText(TextField, 'Yazdırılacak kopya sayısı');
    await tester.ensureVisible(copies);
    await tester.enterText(copies, '0');
    await tester.tap(find.text('Aygıtı kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Kopya sayısı 1-20 arasında olmalıdır.'), findsOneWidget);
    expect(_FakeHardwareDevicesNotifier.saveCalls, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('scale and POS TCP settings expose type-specific discovery',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> openFor(String typeLabel, String discoveryLabel) async {
      await tester.tap(find.byTooltip('Aygıt ekle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(typeLabel).first);
      await tester.tap(find.text('Devam et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TCP / Ağ'));
      await tester.tap(find.text('Devam et'));
      await tester.pumpAndSettle();
      expect(find.text(discoveryLabel), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
    }

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

    await openFor('Terazi', 'Aynı ağdaki terazileri bul');
    await openFor('Fiziksel POS', 'Aynı ağdaki POS Bridge’leri bul');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shared printers are discoverable from the add wizard',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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
    await tester.tap(find.byTooltip('Aygıt ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Ortak / Uzak'), findsOneWidget);
    await tester.tap(find.text('Ortak / Uzak'));
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Ortak cihazları bul'), findsOneWidget);
    expect(find.text('Bağlantıyı test et'), findsNothing);
    expect(find.text('Genel bilgiler'), findsNothing);
    expect(find.text('Donanım özellikleri'), findsNothing);
    expect(find.text('Ortak yazıcıyı kullan'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('manager and editor stay overflow-free on a compact scaled UI',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(320, 640);
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
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.25),
            ),
            child: child!,
          ),
          home: const HardwareTestPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Aygıt ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni aygıt ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(find.text('Aygıtı kaydet'), findsOneWidget);
    expect(find.text('Bağlantıyı test et'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('long device states stay overflow-free on a narrow viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hardwareDevicesProvider
              .overrideWith(_OfflineHardwareDevicesNotifier.new),
        ],
        child: const MaterialApp(home: HardwareTestPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Çevrimdışı'), findsOneWidget);
    expect(find.byTooltip('Yönetici işlemleri'), findsOneWidget);
    expect(find.byTooltip('Aygıt ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
