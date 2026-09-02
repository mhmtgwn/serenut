import 'dart:io';

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
import 'package:serenutos/infrastructure/services/device_hardware_profile_service.dart';
import 'package:serenutos/infrastructure/services/printer_discovery_service.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/infrastructure/printing/physical_print_test_service.dart';
import 'package:serenutos/infrastructure/services/shared_hardware_service.dart';

final deviceHardwareProfileServiceProvider =
    Provider<DeviceHardwareProfileService>((ref) {
  return DeviceHardwareProfileService(
    apiClient: ref.watch(apiClientProvider),
    licenseService: ref.watch(licenseServiceProvider),
  );
});

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

final sharedHardwarePresenceRuntimeProvider =
    Provider<SharedHardwarePresenceRuntime>((ref) {
  final runtime = SharedHardwarePresenceRuntime(
    service: ref.watch(sharedHardwareServiceProvider),
    loadDevices: () => ref.read(hardwareDevicesProvider.future),
  );
  ref.onDispose(runtime.dispose);
  return runtime;
});

class HardwareDevicesNotifier extends AsyncNotifier<List<HardwareDevice>> {
  static const _migrationKey = 'hardware_device_registry_migrated_v1';
  late HardwareDeviceRepository _repository;

  @override
  Future<List<HardwareDevice>> build() async {
    _repository = await ref.watch(hardwareDeviceRepositoryProvider.future);
    final legacyDevices = await _repository.getAll();
    final legacyPrinters = legacyDevices.where(_isPrinter).toList();
    if (legacyPrinters.isNotEmpty) {
      for (final printer in legacyPrinters) {
        await _savePrinter(printer, createRouteWhenMissing: true);
        await _repository.delete(printer.id);
      }
    }
    final devices = await _loadAll();
    if (devices.isNotEmpty) return devices;
    final remoteDevices = await _restoreRemoteProfile();
    if (remoteDevices.isNotEmpty) {
      for (final device in remoteDevices) {
        if (_isPrinter(device)) {
          await _savePrinter(device, createRouteWhenMissing: true);
        } else {
          await _repository.save(device);
          await _syncLegacy(device);
        }
      }
      return _loadAll();
    }
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_migrationKey) == true) return [];
    await _migrate(preferences);
    final migrated = await _repository.getAll();
    for (final printer in migrated.where(_isPrinter).toList()) {
      await _savePrinter(printer, createRouteWhenMissing: true);
      await _repository.delete(printer.id);
    }
    return _loadAll();
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
      final labelPrinterName = settings.labelPrinterName ?? '';
      final labelPrinterIp = settings.labelPrinterIp ?? '';
      devices.add(HardwareDevice(
        id: 'label-printer-primary',
        name:
            labelPrinterName.isNotEmpty ? labelPrinterName : 'Etiket Yazıcısı',
        type: HardwareDeviceType.labelPrinter,
        connectionType: labelPrinterIp.isNotEmpty
            ? HardwareConnectionType.tcp
            : _printerConnection(labelPrinterName),
        configuration: {
          'printerName': labelPrinterName,
          'host': labelPrinterIp,
          'port': settings.labelPrinterPort,
          'language': settings.labelPrinterLanguage,
          'labelWidthMm': settings.labelWidthMm,
          'labelHeightMm': settings.labelHeightMm,
          'labelGapMm': settings.labelGapMm,
          'autoDetectLabelGap': settings.labelAutoDetectGap,
          'dpi': settings.labelDpi,
          'copies': settings.labelPrinterCopies,
          'printableWidthDots': (settings.labelWidthMm * settings.labelDpi / 25.4).round(),
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
    if (_isPrinter(device)) {
      await _savePrinter(device, createRouteWhenMissing: true);
      state = AsyncData(await _loadAll());
      await _backupRemoteProfile(state.requireValue);
      return;
    }
    final existing = await _repository.getAll();
    final previous = existing.where((item) => item.id == device.id).firstOrNull;
    final siblings = existing
        .where((item) => item.type == device.type && item.id != device.id)
        .toList(growable: false);
    final wasActive =
        previous == null ? siblings.isEmpty : _isActiveNonPrinter(previous);
    final saved = device.copyWith(
      configuration: {
        ...device.configuration,
        'isActive': wasActive,
      },
    );
    await _repository.save(saved);
    if (wasActive) await _syncLegacy(saved);
    final current = await _repository.getAll();
    state = AsyncData(current);
    await _backupRemoteProfile(current);
  }

  Future<void> remove(HardwareDevice device) async {
    if (_isPrinter(device)) {
      final printing = ref.read(printingRepositoryProvider);
      final siblings = (await printing.getDevices())
          .where((item) =>
              item.id != device.id &&
              item.language == _printerLanguage(device.type) &&
              item.enabled)
          .toList(growable: false);
      for (final kind in _documentKinds(device.type)) {
        final route = await printing.getRoute(kind);
        if (route?.deviceId == device.id && siblings.isNotEmpty) {
          await _savePrinterRoute(kind, siblings.first.id);
        }
      }
      await printing.deleteDevice(device.id);
      final current = await _loadAll();
      state = AsyncData(current);
      await _backupRemoteProfile(current);
      return;
    }
    final siblings = (await _repository.getAll())
        .where((item) => item.type == device.type && item.id != device.id)
        .toList(growable: false);
    final wasActive = _isActiveNonPrinter(device);
    if (wasActive && siblings.isNotEmpty) {
      final replacement = siblings.first.copyWith(configuration: {
        ...siblings.first.configuration,
        'isActive': true,
      });
      await _repository.save(replacement);
      await _syncLegacy(replacement);
    } else {
      if (wasActive) await _disableLegacy(device);
    }
    await _repository.delete(device.id);
    final current = await _repository.getAll();
    state = AsyncData(current);
    await _backupRemoteProfile(current);
  }

  /// Makes an already registered device the active route for its type without
  /// deleting any sibling devices.
  Future<void> activate(HardwareDevice device) async {
    if (_isPrinter(device)) {
      await _savePrinter(device.copyWith(enabled: true));
      for (final kind in _documentKinds(device.type)) {
        await _savePrinterRoute(kind, device.id);
      }
      final current = await _loadAll();
      state = AsyncData(current);
      await _backupRemoteProfile(current);
      return;
    }
    final devices = await _repository.getAll();
    for (final sibling in devices.where(
      (item) => item.type == device.type && item.id != device.id,
    )) {
      await _repository.save(sibling.copyWith(configuration: {
        ...sibling.configuration,
        'isActive': false,
      }));
    }
    final active = device.copyWith(
      enabled: true,
      configuration: {...device.configuration, 'isActive': true},
    );
    await _syncLegacy(active);
    await _repository.save(active);
    final current = await _repository.getAll();
    state = AsyncData(current);
    await _backupRemoteProfile(current);
  }

  Future<void> activateSharedPrinter(SharedHardwareDevice remote) async {
    if (remote.type != HardwareDeviceType.receiptPrinter &&
        remote.type != HardwareDeviceType.labelPrinter) {
      throw StateError('Bu ortak donanım henüz uzaktan kullanılamaz.');
    }
    if (!remote.online) {
      throw StateError('Ortak yazıcının sahibi olan cihaz çevrimdışı.');
    }
    final kind = remote.type == HardwareDeviceType.receiptPrinter
        ? PrinterLanguage.escPos
        : PrinterLanguage.tspl;
    final now = DateTime.now();
    final localProfileId = 'shared:${remote.id}';
    await ref.read(printingRepositoryProvider).saveDevice(PrinterDeviceProfile(
          id: localProfileId,
          name: remote.name,
          language: kind,
          transport: PrinterTransportKind.cloudRelay,
          transportConfig: {
            'hardwareId': remote.id,
            'ownerConnection': remote.connectionType,
          },
          capabilities: remote.capabilities.isEmpty
              ? remote.type == HardwareDeviceType.receiptPrinter
                  ? const {'paperWidthMm': 58, 'printableWidthDots': 384}
                  : const {
                      'dpi': 203,
                      'mediaWidthMm': 50,
                      'mediaHeightMm': 30,
                      'gapMm': 2,
                      'printableWidthDots': 384,
                    }
              : remote.capabilities,
          enabled: true,
          lastTestedAt: remote.lastSeenAt,
          lastTestSucceeded: remote.online,
          lastTestMessage: 'Sahip cihaz üzerinden ortak kullanılıyor.',
          createdAt: now,
          updatedAt: now,
        ));
    for (final documentKind in _documentKinds(remote.type)) {
      await _savePrinterRoute(documentKind, localProfileId);
    }
    state = AsyncData(await _loadAll());
    await _backupRemoteProfile(state.requireValue);
  }

  Future<List<HardwareDevice>> _restoreRemoteProfile() async {
    try {
      return ref.read(deviceHardwareProfileServiceProvider).restore();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _backupRemoteProfile(List<HardwareDevice> devices) async {
    try {
      await ref.read(deviceHardwareProfileServiceProvider).backup(
            devices
                .where((device) =>
                    device.connectionType != HardwareConnectionType.cloud)
                .toList(growable: false),
          );
    } catch (_) {
      // Local hardware remains authoritative while offline; next edit retries.
    }
    try {
      await ref.read(sharedHardwareServiceProvider).publishPresence(
            devices
                .where((device) =>
                    device.connectionType != HardwareConnectionType.cloud)
                .toList(),
          );
      ref.invalidate(sharedHardwareDevicesProvider);
    } catch (_) {
      // Presence is retried by the worker startup and the next registry change.
    }
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

  Future<void> refreshConnections() async {
    final devices = await _loadAll();
    for (final device in devices) {
      if (device.type == HardwareDeviceType.barcodeScanner ||
          device.connectionType == HardwareConnectionType.cloud) {
        continue;
      }
      final result = await verify(device);
      if (_isPrinter(device)) {
        await _savePrinter(device.copyWith(
          status: result.success
              ? (device.status == HardwareDeviceStatus.ready
                  ? HardwareDeviceStatus.ready
                  : HardwareDeviceStatus.unverified)
              : HardwareDeviceStatus.offline,
          lastMessage: result.success
              ? 'Bağlantı erişilebilir. Fiziksel çıktı doğrulaması korunuyor.'
              : result.message,
          lastError: result.technicalDetail,
          clearLastError: result.success,
        ));
      } else {
        await _repository.save(device.copyWith(
          status: result.success
              ? HardwareDeviceStatus.ready
              : HardwareDeviceStatus.offline,
          lastTestedAt: result.completedAt,
          lastMessage: result.message,
          lastError: result.technicalDetail,
          clearLastError: result.success,
        ));
      }
    }
    state = AsyncData(await _loadAll());
    await _backupRemoteProfile(state.requireValue);
  }

  Future<HardwareTestResult> test(
    HardwareDevice device, {
    PrintDocumentKind? printKind,
  }) async {
    if (_isPrinter(device)) {
      await _savePrinter(device.copyWith(status: HardwareDeviceStatus.testing));
      state = AsyncData(await _loadAll());
      final started = DateTime.now();
      late HardwareTestResult result;
      try {
        final kind = device.type == HardwareDeviceType.receiptPrinter
            ? PrintDocumentKind.receipt
            : printKind ?? PrintDocumentKind.productLabel;
        if (device.type == HardwareDeviceType.labelPrinter &&
            kind != PrintDocumentKind.productLabel &&
            kind != PrintDocumentKind.orderLabel) {
          throw ArgumentError.value(kind, 'printKind', 'Etiket türü geçersiz.');
        }
        final dispatch =
            await ref.read(physicalPrintTestServiceProvider).dispatch(
                  deviceId: device.id,
                  kind: kind,
                );
        result = HardwareTestResult(
          success: true,
          message:
              'Test işi yazıcıya teslim edildi. Kâğıt üzerindeki sonucu doğrulayın.',
          elapsed: DateTime.now().difference(started),
          completedAt: DateTime.now(),
          requiresPhysicalConfirmation: true,
          printJobId: dispatch.jobId,
          deviceId: dispatch.deviceId,
          printKind: dispatch.kind.name,
        );
      } catch (error) {
        result = HardwareTestResult(
          success: false,
          message: 'Test çıktısı yazıcıya teslim edilemedi.',
          technicalDetail: error.toString(),
          elapsed: DateTime.now().difference(started),
          completedAt: DateTime.now(),
        );
      }
      await _savePrinter(device.copyWith(
        status: result.requiresPhysicalConfirmation
            ? HardwareDeviceStatus.unverified
            : result.success
                ? HardwareDeviceStatus.ready
                : HardwareDeviceStatus.error,
        lastTestedAt: result.completedAt,
        lastMessage: result.requiresPhysicalConfirmation
            ? 'Fiziksel çıktı doğrulaması bekleniyor.'
            : result.message,
        lastError: result.technicalDetail,
        clearLastError: result.success,
      ));
      final current = await _loadAll();
      state = AsyncData(current);
      await _backupRemoteProfile(current);
      return result;
    }
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
    final current = await _repository.getAll();
    state = AsyncData(current);
    await _backupRemoteProfile(current);
    return result;
  }

  Future<void> confirmPhysicalPrintTest(
    HardwareTestResult result, {
    required bool passed,
  }) async {
    if (!result.requiresPhysicalConfirmation ||
        result.printJobId == null ||
        result.deviceId == null ||
        result.printKind == null) {
      throw StateError('Fiziksel doğrulama bilgisi eksik.');
    }
    await ref.read(physicalPrintTestServiceProvider).confirm(
          PhysicalPrintTestDispatch(
            jobId: result.printJobId!,
            deviceId: result.deviceId!,
            kind: PrintDocumentKind.values.byName(result.printKind!),
            deliveredAt: result.completedAt,
          ),
          passed: passed,
        );
    state = AsyncData(await _loadAll());
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
        await _probePrinterConnection(device);
        return 'Fiş yazıcısı erişilebilir; fiziksel çıktı testi bekleniyor';
      case HardwareDeviceType.labelPrinter:
        await _probePrinterConnection(device);
        return 'Etiket yazıcısı erişilebilir; fiziksel ölçü testi bekleniyor';
      case HardwareDeviceType.barcodeScanner:
        final scanner = ref.read(scannerServiceProvider);
        await scanner.initialize();
        final scan =
            await scanner.scanStream.first.timeout(const Duration(seconds: 10));
        return 'Barkod okundu: ${scan.barcode}';
    }
  }

  Future<String> _verifyWindowsPrinter(HardwareDevice device) async {
    final requested =
        (device.configuration['printerName'] as String? ?? '').trim();
    if (requested.isEmpty) {
      throw StateError('Windows yazıcı adı boş bırakılamaz.');
    }
    final printers = await PrinterDiscoveryService().listWindowsPrinters();
    final matched = printers.any(
      (printer) => printer.name.toLowerCase() == requested.toLowerCase(),
    );
    if (!matched) {
      final available = printers.map((printer) => printer.name).join(', ');
      throw StateError(
        available.isEmpty
            ? 'Windows yazıcı listesi okunamadı. Yazıcı sürücüsünü ve Print Spooler hizmetini kontrol edin.'
            : '"$requested" Windows yazıcı listesinde bulunamadı. Mevcut yazıcılar: $available',
      );
    }
    return 'Windows yazıcı kuyruğu hazır: $requested';
  }

  Future<void> _probePrinterConnection(HardwareDevice device) async {
    final config = device.configuration;
    switch (device.connectionType) {
      case HardwareConnectionType.windows:
        await _verifyWindowsPrinter(device);
      case HardwareConnectionType.tcp:
        final host = config['host']?.toString().trim() ?? '';
        final port = _int(config['port'], 9100);
        if (host.isEmpty) throw StateError('Yazıcı IP adresi boş.');
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 5),
        );
        await socket.close();
      case HardwareConnectionType.bluetooth:
        if (Platform.isWindows) {
          await _verifyWindowsPrinter(device);
          break;
        }
        final address =
            (config['address'] ?? config['printerName'])?.toString() ?? '';
        if (address.isEmpty ||
            !await NativePrinterBridge.connectBluetoothDevice(address)) {
          throw StateError('Bluetooth yazıcıya bağlanılamadı.');
        }
      case HardwareConnectionType.embedded:
        if (!await NativePrinterBridge.hasSunmiPrinter()) {
          throw StateError('Gömülü yazıcı bulunamadı.');
        }
      case HardwareConnectionType.serial || HardwareConnectionType.keyboard:
        throw StateError('Bu bağlantı türü yazıcı için desteklenmiyor.');
      case HardwareConnectionType.cloud:
        throw StateError(
          'Ortak yazıcı sahibi cihaz üzerinden test edilmelidir.',
        );
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
        ref.invalidate(hardwareConfigProvider);
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
        ref.invalidate(hardwareConfigProvider);
        return;
      case HardwareDeviceType.receiptPrinter:
        final settings = await _settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                printerName: config['printerName'] as String? ?? device.name,
                printerIp: config['host'] as String? ?? '',
                printerPort: _int(config['port'], 9100),
                paperWidth: _int(config['paperWidth'], 80),
                autoCutReceipt: config['autoCut'] as bool? ?? true,
                openCashDrawer: config['openDrawer'] as bool? ?? false,
                activeReceiptPrinterId: device.id,
                printCopies: _int(config['copies'], 1).clamp(1, 20).toInt(),
              ),
            );
        return;
      case HardwareDeviceType.labelPrinter:
        final settings = await _settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                labelPrinterEnabled: device.enabled,
                labelPrinterName: config['printerName'] as String? ?? '',
                labelPrinterIp: config['host'] as String? ?? '',
                labelPrinterPort: _int(config['port'], 9100),
                labelPrinterLanguage: config['language'] as String? ?? 'tspl',
                labelWidthMm: _int(config['labelWidthMm'], 50),
                labelHeightMm: _int(config['labelHeightMm'], 30),
                labelGapMm: _int(config['labelGapMm'], 2),
                labelAutoDetectGap:
                    config['autoDetectLabelGap'] as bool? ?? false,
                labelDpi: _int(config['dpi'], 203),
                labelPrinterCopies:
                    _int(config['copies'], 1).clamp(1, 20).toInt(),
                activeLabelPrinterId: device.id,
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
        ref.invalidate(hardwareConfigProvider);
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
        ref.invalidate(hardwareConfigProvider);
        return;
      case HardwareDeviceType.receiptPrinter:
        final settings = await _settings();
        if (settings.activeReceiptPrinterId != device.id) return;
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
        if (settings.activeLabelPrinterId != device.id) return;
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

  Future<List<HardwareDevice>> _loadAll() async {
    final nonPrinters =
        (await _repository.getAll()).where((item) => !_isPrinter(item));
    final printing = ref.read(printingRepositoryProvider);
    final routes = <PrintDocumentKind, PrinterRoute?>{};
    for (final kind in PrintDocumentKind.values) {
      routes[kind] = await printing.getRoute(kind);
    }
    final printers = (await printing.getDevices()).map((profile) {
      final activeFor = routes.entries
          .where((entry) => entry.value?.deviceId == profile.id)
          .map((entry) => entry.key.name)
          .toList(growable: false);
      return _fromPrinterProfile(profile, activeFor);
    });
    return [...printers, ...nonPrinters];
  }

  bool _isActiveNonPrinter(HardwareDevice device) =>
      device.configuration['isActive'] as bool? ?? true;

  Future<void> _savePrinter(
    HardwareDevice device, {
    bool createRouteWhenMissing = false,
  }) async {
    final printing = ref.read(printingRepositoryProvider);
    await printing.saveDevice(_toPrinterProfile(device));
    if (!createRouteWhenMissing) return;
    for (final kind in _documentKinds(device.type)) {
      if (await printing.getRoute(kind) == null) {
        await _savePrinterRoute(kind, device.id);
      }
    }
  }

  Future<void> _savePrinterRoute(
    PrintDocumentKind kind,
    String deviceId,
  ) async {
    final printing = ref.read(printingRepositoryProvider);
    final profiles = await printing.getDesignProfiles(kind);
    final profile = profiles.where((item) => item.isDefault).firstOrNull ??
        profiles.firstOrNull;
    if (profile == null) {
      throw StateError('${kind.name} için tasarım profili bulunamadı.');
    }
    await printing.saveRoute(PrinterRoute(
      kind: kind,
      deviceId: deviceId,
      designProfileId: profile.id,
      updatedAt: DateTime.now(),
    ));
  }

  static bool _isPrinter(HardwareDevice device) =>
      device.type == HardwareDeviceType.receiptPrinter ||
      device.type == HardwareDeviceType.labelPrinter;

  static List<PrintDocumentKind> _documentKinds(HardwareDeviceType type) =>
      type == HardwareDeviceType.receiptPrinter
          ? const [PrintDocumentKind.receipt]
          : const [
              PrintDocumentKind.productLabel,
              PrintDocumentKind.orderLabel,
            ];

  static PrinterLanguage _printerLanguage(HardwareDeviceType type) =>
      type == HardwareDeviceType.receiptPrinter
          ? PrinterLanguage.escPos
          : PrinterLanguage.tspl;

  static PrinterTransportKind _transport(HardwareConnectionType connection) =>
      switch (connection) {
        HardwareConnectionType.embedded => PrinterTransportKind.embedded,
        HardwareConnectionType.windows => PrinterTransportKind.windowsSpooler,
        HardwareConnectionType.bluetooth => PrinterTransportKind.bluetooth,
        HardwareConnectionType.cloud => PrinterTransportKind.cloudRelay,
        _ => PrinterTransportKind.tcp,
      };

  static HardwareConnectionType _connection(PrinterTransportKind transport) =>
      switch (transport) {
        PrinterTransportKind.embedded => HardwareConnectionType.embedded,
        PrinterTransportKind.windowsSpooler => HardwareConnectionType.windows,
        PrinterTransportKind.usb => HardwareConnectionType.windows,
        PrinterTransportKind.bluetooth => HardwareConnectionType.bluetooth,
        PrinterTransportKind.tcp => HardwareConnectionType.tcp,
        PrinterTransportKind.cloudRelay => HardwareConnectionType.cloud,
      };

  static PrinterDeviceProfile _toPrinterProfile(HardwareDevice device) {
    final now = DateTime.now();
    final config = Map<String, Object?>.from(device.configuration)
      ..remove('activeFor');
    if (device.id.startsWith('shared:')) {
      config.putIfAbsent('hardwareId', () => device.id.substring(7));
    }
    final isLabel = device.type == HardwareDeviceType.labelPrinter;
    final labelWidthMm = _int(config['labelWidthMm'], 50);
    final labelDpi = _int(config['dpi'], 203);
    final calculatedLabelDots = (labelWidthMm * labelDpi / 25.4).round();
    final configuredPrintableDots = _int(config['printableWidthDots'], 0);
    final effectiveLabelDots =
        (configuredPrintableDots > 0 && configuredPrintableDots != 384)
            ? configuredPrintableDots
            : calculatedLabelDots;

    final capabilities = isLabel
        ? {
            'dpi': labelDpi,
            'mediaWidthMm': labelWidthMm,
            'mediaHeightMm': _int(config['labelHeightMm'], 30),
            'gapMm': _int(config['labelGapMm'], 2),
            'autoDetectGap': config['autoDetectLabelGap'] as bool? ?? false,
            'printableWidthDots': effectiveLabelDots,
            'direction': _int(config['printDirection'], 0),
            'raster': true,
          }
        : {
            'paperWidthMm': _int(config['paperWidth'], 58),
            'printableWidthDots':
                _int(config['paperWidth'], 58) <= 58 ? 384 : 576,
            'raster': true,
            'cutter': config['autoCut'] as bool? ?? false,
            'cashDrawer': config['openDrawer'] as bool? ?? false,
          };
    return PrinterDeviceProfile(
      id: device.id,
      name: device.name,
      language: _printerLanguage(device.type),
      transport: device.connectionType == HardwareConnectionType.bluetooth &&
              Platform.isWindows
          ? PrinterTransportKind.windowsSpooler
          : _transport(device.connectionType),
      transportConfig: config,
      capabilities: capabilities,
      enabled: device.enabled,
      lastTestedAt: device.lastTestedAt,
      lastTestSucceeded: switch (device.status) {
        HardwareDeviceStatus.ready => true,
        HardwareDeviceStatus.error || HardwareDeviceStatus.offline => false,
        _ => null,
      },
      lastTestMessage: device.lastError ?? device.lastMessage,
      createdAt: now,
      updatedAt: now,
    );
  }

  static HardwareDevice _fromPrinterProfile(
    PrinterDeviceProfile profile,
    List<String> activeFor,
  ) {
    final isLabel = profile.language == PrinterLanguage.tspl;
    final config = <String, Object?>{
      ...profile.transportConfig,
      'activeFor': activeFor,
      if (isLabel) ...{
        'language': 'tspl',
        'dpi': profile.capabilities['dpi'],
        'labelWidthMm': profile.capabilities['mediaWidthMm'],
        'labelHeightMm': profile.capabilities['mediaHeightMm'],
        'labelGapMm': profile.capabilities['gapMm'],
        'autoDetectLabelGap': profile.capabilities['autoDetectGap'],
        'printableWidthDots': profile.capabilities['printableWidthDots'],
        'printDirection': profile.capabilities['direction'],
      } else ...{
        'paperWidth': profile.capabilities['paperWidthMm'],
        'autoCut': profile.capabilities['cutter'],
        'openDrawer': profile.capabilities['cashDrawer'],
      },
    };
    return HardwareDevice(
      id: profile.id,
      name: profile.name,
      type: isLabel
          ? HardwareDeviceType.labelPrinter
          : HardwareDeviceType.receiptPrinter,
      connectionType: _connection(profile.transport),
      configuration: config,
      enabled: profile.enabled,
      status: profile.lastTestSucceeded == true
          ? HardwareDeviceStatus.ready
          : profile.lastTestSucceeded == false
              ? HardwareDeviceStatus.error
              : HardwareDeviceStatus.unverified,
      lastTestedAt: profile.lastTestedAt,
      lastMessage:
          profile.lastTestSucceeded == false ? null : profile.lastTestMessage,
      lastError:
          profile.lastTestSucceeded == false ? profile.lastTestMessage : null,
    );
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
