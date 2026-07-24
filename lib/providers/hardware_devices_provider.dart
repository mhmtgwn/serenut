import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/hardware/hardware_device_repository.dart';
import 'package:serenutos/domain/hardware/payment_terminal_service.dart';
import 'package:serenutos/domain/hardware/scale_service.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/repositories/shared_preferences_hardware_device_repository.dart';
import 'package:serenutos/providers/hardware_config_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

final hardwareDeviceRepositoryProvider =
    FutureProvider<HardwareDeviceRepository>((ref) async {
  return SharedPreferencesHardwareDeviceRepository(
    await SharedPreferences.getInstance(),
  );
});

final hardwareDevicesProvider =
    AsyncNotifierProvider<HardwareDevicesNotifier, List<HardwareDevice>>(
  HardwareDevicesNotifier.new,
);

class HardwareDevicesNotifier extends AsyncNotifier<List<HardwareDevice>> {
  static const _migrationKey = 'hardware_device_registry_migrated_v1';
  late HardwareDeviceRepository _repository;

  @override
  Future<List<HardwareDevice>> build() async {
    _repository = await ref.watch(hardwareDeviceRepositoryProvider.future);
    final devices = await _repository.getAll();
    if (devices.isNotEmpty) return devices;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_migrationKey) == true) return [];
    return _migrate(preferences);
  }

  Future<List<HardwareDevice>> _migrate(
    SharedPreferences preferences,
  ) async {
    final settings = await _settings();
    final hardware = await ref.read(hardwareConfigProvider.future);
    final devices = <HardwareDevice>[];
    if (settings.printerName?.isNotEmpty == true ||
        settings.printerIp?.isNotEmpty == true) {
      devices.add(HardwareDevice(
        id: 'receipt-printer-primary',
        name: settings.printerName?.isNotEmpty == true
            ? settings.printerName!
            : 'Fiş Yazıcısı',
        type: HardwareDeviceType.receiptPrinter,
        connectionType: _printerConnection(settings.printerName),
        configuration: {
          'printerName': settings.printerName ?? '',
          'host': settings.printerIp ?? '',
          'port': settings.printerPort,
          'paperWidth': settings.paperWidth,
        },
      ));
    }
    if (settings.labelPrinterEnabled) {
      devices.add(HardwareDevice(
        id: 'label-printer-primary',
        name: 'Etiket Yazıcısı',
        type: HardwareDeviceType.labelPrinter,
        connectionType: HardwareConnectionType.tcp,
        configuration: {
          'host': settings.labelPrinterIp ?? '',
          'port': settings.labelPrinterPort,
        },
      ));
    }
    if (hardware.hasScale) {
      devices.add(HardwareDevice(
        id: 'scale-primary',
        name: 'Terazi',
        type: HardwareDeviceType.scale,
        connectionType: hardware.scaleConnection == 'serial'
            ? HardwareConnectionType.serial
            : HardwareConnectionType.tcp,
        configuration: {
          'host': hardware.scaleHost,
          'port': hardware.scalePort,
          'serialPort': hardware.scaleSerialPort,
          'baudRate': hardware.scaleBaudRate,
          'dataBits': hardware.scaleDataBits,
          'stopBits': hardware.scaleStopBits,
          'parity': hardware.scaleParity,
          'defaultUnit': hardware.scaleDefaultUnit,
        },
      ));
    }
    if (hardware.hasPosBridge) {
      devices.add(HardwareDevice(
        id: 'payment-terminal-primary',
        name: 'Fiziksel POS',
        type: HardwareDeviceType.paymentTerminal,
        connectionType: HardwareConnectionType.tcp,
        configuration: {
          'host': hardware.posBridgeHost,
          'port': hardware.posBridgePort,
          'vendor': hardware.posVendor,
          'protocol': hardware.posProtocol,
        },
      ));
    }
    for (final device in devices) {
      await _repository.save(device);
    }
    await preferences.setBool(_migrationKey, true);
    return devices;
  }

  Future<void> save(HardwareDevice device) async {
    await _syncLegacy(device);
    for (final duplicate in (await _repository.getAll()).where(
      (item) => item.type == device.type && item.id != device.id,
    )) {
      await _repository.delete(duplicate.id);
    }
    await _repository.save(device);
    state = AsyncData(await _repository.getAll());
  }

  Future<void> remove(HardwareDevice device) async {
    await _disableLegacy(device);
    await _repository.delete(device.id);
    state = AsyncData(await _repository.getAll());
  }

  Future<HardwareTestResult> verify(HardwareDevice device) async {
    final started = DateTime.now();
    try {
      final message = await _probe(device);
      return HardwareTestResult(
        success: true,
        message: message,
        elapsed: DateTime.now().difference(started),
        completedAt: DateTime.now(),
      );
    } catch (error) {
      return HardwareTestResult(
        success: false,
        message: 'Cihaz doğrulanamadı',
        technicalDetail: error.toString(),
        elapsed: DateTime.now().difference(started),
        completedAt: DateTime.now(),
      );
    }
  }

  Future<HardwareTestResult> test(HardwareDevice device) async {
    await _repository.save(
      device.copyWith(status: HardwareDeviceStatus.testing),
    );
    state = AsyncData(await _repository.getAll());
    final result = await verify(device);
    await _repository.save(device.copyWith(
      status: result.success
          ? HardwareDeviceStatus.ready
          : HardwareDeviceStatus.error,
      lastTestedAt: result.completedAt,
      lastMessage: result.message,
      lastError: result.technicalDetail,
      clearLastError: result.success,
    ));
    state = AsyncData(await _repository.getAll());
    return result;
  }

  Future<String> _probe(HardwareDevice device) async {
    final config = device.configuration;
    switch (device.type) {
      case HardwareDeviceType.scale:
        final adapter = device.connectionType == HardwareConnectionType.serial
            ? SerialScaleAdapter(
                portName: config['serialPort'] as String? ?? '',
                baudRate: _int(config['baudRate'], 9600),
                dataBits: _int(config['dataBits'], 8),
                stopBits: _int(config['stopBits'], 1),
                parity: config['parity'] as String? ?? 'none',
                defaultUnit: config['defaultUnit'] as String? ?? 'kg',
              )
            : TcpScaleAdapter(
                host: config['host'] as String? ?? '',
                port: _int(config['port'], 4001),
                defaultUnit: config['defaultUnit'] as String? ?? 'kg',
              );
        try {
          await adapter.connect().timeout(const Duration(seconds: 5));
          return 'Terazi bağlantısı hazır';
        } finally {
          await adapter.disconnect();
        }
      case HardwareDeviceType.paymentTerminal:
        final terminal = TcpPaymentTerminalAdapter(
          host: config['host'] as String? ?? '',
          port: _int(config['port'], 4100),
          vendor: config['vendor'] as String? ?? 'generic',
          protocol: config['protocol'] as String? ?? 'vendor_sdk',
        );
        final result =
            await terminal.probe().timeout(const Duration(seconds: 8));
        if (!result.paired || !result.saleSupported) {
          throw 'Terminal yanıt verdi ancak satışa hazır değil.';
        }
        return '${result.vendor} ${result.model} satışa hazır';
      case HardwareDeviceType.receiptPrinter:
        final current = await _settings();
        final candidate = current.copyWith(
          printerName: config['printerName'] as String? ?? device.name,
          printerIp: config['host'] as String? ?? '',
          printerPort: _int(config['port'], 9100),
          paperWidth: _int(config['paperWidth'], 80),
        );
        await ref
            .read(printerServiceProvider)
            .testPrinterConnection(candidate)
            .timeout(const Duration(seconds: 8));
        return 'Fiş yazıcısı bağlantısı hazır';
      case HardwareDeviceType.labelPrinter:
        final host = device.configuration['host'] as String? ?? '';
        if (host.isEmpty) throw 'Etiket yazıcısı IP adresi eksik.';
        await ref
            .read(printerServiceProvider)
            .testConnection(host, _int(device.configuration['port'], 9100))
            .timeout(const Duration(seconds: 8));
        return 'Etiket yazıcısı bağlantısı hazır';
      case HardwareDeviceType.barcodeScanner:
        final scanner = ref.read(scannerServiceProvider);
        await scanner.initialize();
        final scan =
            await scanner.scanStream.first.timeout(const Duration(seconds: 10));
        return 'Barkod okundu: ${scan.barcode}';
    }
  }

  Future<void> _syncLegacy(HardwareDevice device) async {
    final current = await ref.read(hardwareConfigProvider.future);
    final config = device.configuration;
    switch (device.type) {
      case HardwareDeviceType.scale:
        await saveHardwareConfig(HardwareConfig(
          scaleConnection:
              device.connectionType == HardwareConnectionType.serial
                  ? 'serial'
                  : 'tcp',
          scaleHost: config['host'] as String? ?? '',
          scalePort: _int(config['port'], 4001),
          scaleSerialPort: config['serialPort'] as String? ?? '',
          scaleBaudRate: _int(config['baudRate'], 9600),
          scaleDataBits: _int(config['dataBits'], 8),
          scaleStopBits: _int(config['stopBits'], 1),
          scaleParity: config['parity'] as String? ?? 'none',
          scaleDefaultUnit: config['defaultUnit'] as String? ?? 'kg',
          posBridgeHost: current.posBridgeHost,
          posBridgePort: current.posBridgePort,
          posVendor: current.posVendor,
          posProtocol: current.posProtocol,
        ));
        return;
      case HardwareDeviceType.paymentTerminal:
        await saveHardwareConfig(HardwareConfig(
          scaleConnection: current.scaleConnection,
          scaleHost: current.scaleHost,
          scalePort: current.scalePort,
          scaleSerialPort: current.scaleSerialPort,
          scaleBaudRate: current.scaleBaudRate,
          scaleDataBits: current.scaleDataBits,
          scaleStopBits: current.scaleStopBits,
          scaleParity: current.scaleParity,
          scaleDefaultUnit: current.scaleDefaultUnit,
          posBridgeHost: config['host'] as String? ?? '',
          posBridgePort: _int(config['port'], 4100),
          posVendor: config['vendor'] as String? ?? 'generic',
          posProtocol: config['protocol'] as String? ?? 'vendor_sdk',
        ));
        return;
      case HardwareDeviceType.receiptPrinter:
        final settings = await _settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                printerName: config['printerName'] as String? ?? device.name,
                printerIp: config['host'] as String? ?? '',
                printerPort: _int(config['port'], 9100),
                paperWidth: _int(config['paperWidth'], 80),
              ),
            );
        return;
      case HardwareDeviceType.labelPrinter:
        final settings = await _settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                labelPrinterEnabled: device.enabled,
                labelPrinterIp: config['host'] as String? ?? '',
                labelPrinterPort: _int(config['port'], 9100),
              ),
            );
        return;
      case HardwareDeviceType.barcodeScanner:
        return;
    }
  }

  Future<void> _disableLegacy(HardwareDevice device) async {
    final current = await ref.read(hardwareConfigProvider.future);
    switch (device.type) {
      case HardwareDeviceType.scale:
        await saveHardwareConfig(HardwareConfig(
          scaleConnection: current.scaleConnection,
          scaleHost: '',
          scalePort: current.scalePort,
          scaleSerialPort: '',
          scaleBaudRate: current.scaleBaudRate,
          scaleDataBits: current.scaleDataBits,
          scaleStopBits: current.scaleStopBits,
          scaleParity: current.scaleParity,
          scaleDefaultUnit: current.scaleDefaultUnit,
          posBridgeHost: current.posBridgeHost,
          posBridgePort: current.posBridgePort,
          posVendor: current.posVendor,
          posProtocol: current.posProtocol,
        ));
        return;
      case HardwareDeviceType.paymentTerminal:
        await saveHardwareConfig(HardwareConfig(
          scaleConnection: current.scaleConnection,
          scaleHost: current.scaleHost,
          scalePort: current.scalePort,
          scaleSerialPort: current.scaleSerialPort,
          scaleBaudRate: current.scaleBaudRate,
          scaleDataBits: current.scaleDataBits,
          scaleStopBits: current.scaleStopBits,
          scaleParity: current.scaleParity,
          scaleDefaultUnit: current.scaleDefaultUnit,
          posBridgeHost: '',
          posBridgePort: current.posBridgePort,
          posVendor: current.posVendor,
          posProtocol: current.posProtocol,
        ));
        return;
      case HardwareDeviceType.receiptPrinter:
        final settings = await _settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                printerName: '',
                printerIp: '',
                printReceipt: false,
              ),
            );
        return;
      case HardwareDeviceType.labelPrinter:
        final settings = await _settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                labelPrinterEnabled: false,
                labelPrinterIp: '',
              ),
            );
        return;
      case HardwareDeviceType.barcodeScanner:
        return;
    }
  }

  Future<Settings> _settings() async {
    return (await ref.read(settingsRepositoryProvider.future)).getSettings();
  }

  static HardwareConnectionType _printerConnection(String? name) {
    if (name == 'sunmi') return HardwareConnectionType.embedded;
    if (name?.contains(':') == true) return HardwareConnectionType.bluetooth;
    return HardwareConnectionType.windows;
  }

  static int _int(Object? value, int fallback) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
