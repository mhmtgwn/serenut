import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/infrastructure/repositories/shared_preferences_hardware_device_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesHardwareDeviceRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = SharedPreferencesHardwareDeviceRepository(
      await SharedPreferences.getInstance(),
    );
  });

  test('device survives repository recreation with typed configuration',
      () async {
    final device = HardwareDevice(
      id: 'scale-1',
      name: 'Kasa Terazisi',
      type: HardwareDeviceType.scale,
      connectionType: HardwareConnectionType.serial,
      configuration: const {
        'serialPort': 'COM3',
        'baudRate': 9600,
      },
      status: HardwareDeviceStatus.ready,
      lastTestedAt: DateTime.utc(2026, 7, 24, 10, 30),
      lastMessage: 'Terazi bağlantısı hazır',
    );

    await repository.save(device);
    final recreated = SharedPreferencesHardwareDeviceRepository(
      await SharedPreferences.getInstance(),
    );
    final stored = await recreated.getAll();

    expect(stored, hasLength(1));
    expect(stored.single.id, 'scale-1');
    expect(stored.single.type, HardwareDeviceType.scale);
    expect(stored.single.connectionType, HardwareConnectionType.serial);
    expect(stored.single.configuration['serialPort'], 'COM3');
    expect(stored.single.status, HardwareDeviceStatus.ready);
    expect(stored.single.lastTestedAt, DateTime.utc(2026, 7, 24, 10, 30));
  });

  test('save updates the same device instead of creating a duplicate',
      () async {
    const device = HardwareDevice(
      id: 'printer-1',
      name: 'Eski ad',
      type: HardwareDeviceType.receiptPrinter,
      connectionType: HardwareConnectionType.tcp,
    );
    await repository.save(device);
    await repository.save(device.copyWith(
      name: 'Kasa Yazıcısı',
      status: HardwareDeviceStatus.ready,
    ));

    final stored = await repository.getAll();

    expect(stored, hasLength(1));
    expect(stored.single.name, 'Kasa Yazıcısı');
    expect(stored.single.status, HardwareDeviceStatus.ready);
  });

  test('delete only removes the requested device', () async {
    const first = HardwareDevice(
      id: 'first',
      name: 'Birinci',
      type: HardwareDeviceType.receiptPrinter,
      connectionType: HardwareConnectionType.tcp,
    );
    const second = HardwareDevice(
      id: 'second',
      name: 'İkinci',
      type: HardwareDeviceType.scale,
      connectionType: HardwareConnectionType.serial,
    );
    await repository.save(first);
    await repository.save(second);

    await repository.delete(first.id);

    final stored = await repository.getAll();
    expect(stored.map((device) => device.id), ['second']);
  });
}
