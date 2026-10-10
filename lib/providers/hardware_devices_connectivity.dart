part of 'hardware_devices_provider.dart';

extension HardwareDeviceOperations on HardwareDevicesNotifier {
  Future<String> _probe(HardwareDevice device) async {
    final config = device.configuration;
    switch (device.type) {
      case HardwareDeviceType.scale:
        final adapter = device.connectionType == HardwareConnectionType.serial
            ? SerialScaleAdapter(
                portName: config['serialPort'] as String? ?? '',
                baudRate:
                    HardwareDevicesNotifier._int(config['baudRate'], 9600),
                dataBits: HardwareDevicesNotifier._int(config['dataBits'], 8),
                stopBits: HardwareDevicesNotifier._int(config['stopBits'], 1),
                parity: config['parity'] as String? ?? 'none',
                defaultUnit: config['defaultUnit'] as String? ?? 'kg',
              )
            : TcpScaleAdapter(
                host: config['host'] as String? ?? '',
                port: HardwareDevicesNotifier._int(config['port'], 4001),
                defaultUnit: config['defaultUnit'] as String? ?? 'kg',
              );
        try {
          await adapter.connect().timeout(const Duration(seconds: 5));
          return 'Terazi bağlantısı hazır';
        } finally {
          await adapter.disconnect();
        }
      case HardwareDeviceType.paymentTerminal:
        final IPaymentTerminalAdapter terminal =
            device.connectionType == HardwareConnectionType.serial
                ? SerialPaymentTerminalAdapter(
                    portName: config['serialPort'] as String? ?? '',
                    baudRate:
                        HardwareDevicesNotifier._int(config['baudRate'], 9600),
                    vendor: config['vendor'] as String? ?? 'pax',
                    protocol: config['protocol'] as String? ?? 'pax_d230',
                  )
                : TcpPaymentTerminalAdapter(
                    host: config['host'] as String? ?? '',
                    port: HardwareDevicesNotifier._int(config['port'], 4100),
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
        await this._probePrinterConnection(device);
        return 'Fiş yazıcısı erişilebilir; fiziksel çıktı testi bekleniyor';
      case HardwareDeviceType.labelPrinter:
        await this._probePrinterConnection(device);
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
    final isGeneric = requested.toLowerCase() == 'varsayılan windows yazıcısı' ||
        requested.toLowerCase() == 'varsayılan yazıcı' ||
        requested.toLowerCase() == 'default';
    if (isGeneric && printers.isNotEmpty) {
      final preferred = printers.firstWhere((p) => p.isDefault, orElse: () => printers.first);
      return 'Windows varsayılan yazıcı kuyruğu hazır: ${preferred.name}';
    }
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
        await this._verifyWindowsPrinter(device);
      case HardwareConnectionType.tcp:
        final host = config['host']?.toString().trim() ?? '';
        final port = HardwareDevicesNotifier._int(config['port'], 9100);
        if (host.isEmpty) throw StateError('Yazıcı IP adresi boş.');
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 5),
        );
        await socket.close();
      case HardwareConnectionType.bluetooth:
        if (Platform.isWindows) {
          await this._verifyWindowsPrinter(device);
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
          scalePort: HardwareDevicesNotifier._int(config['port'], 4001),
          scaleSerialPort: config['serialPort'] as String? ?? '',
          scaleBaudRate: HardwareDevicesNotifier._int(config['baudRate'], 9600),
          scaleDataBits: HardwareDevicesNotifier._int(config['dataBits'], 8),
          scaleStopBits: HardwareDevicesNotifier._int(config['stopBits'], 1),
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
          posConnection: device.connectionType == HardwareConnectionType.serial
              ? 'serial'
              : 'tcp',
          posSerialPort: config['serialPort'] as String? ?? '',
          posBaudRate: HardwareDevicesNotifier._int(config['baudRate'], 9600),
          posBridgeHost: config['host'] as String? ?? '',
          posBridgePort: HardwareDevicesNotifier._int(config['port'], 4100),
          posVendor: config['vendor'] as String? ?? 'pax',
          posProtocol: config['protocol'] as String? ?? 'pax_d230',
        ));
        ref.invalidate(hardwareConfigProvider);
        return;
      case HardwareDeviceType.receiptPrinter:
        final settings = await this._settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                printerName: config['printerName'] as String? ?? device.name,
                printerIp: config['host'] as String? ?? '',
                printerPort: HardwareDevicesNotifier._int(config['port'], 9100),
                paperWidth:
                    HardwareDevicesNotifier._int(config['paperWidth'], 80),
                autoCutReceipt: config['autoCut'] as bool? ?? true,
                openCashDrawer: config['openDrawer'] as bool? ?? false,
                activeReceiptPrinterId: device.id,
                printCopies: HardwareDevicesNotifier._int(config['copies'], 1)
                    .clamp(1, 20)
                    .toInt(),
              ),
            );
        return;
      case HardwareDeviceType.labelPrinter:
        final settings = await this._settings();
        await ref.read(settingsNotifierProvider.notifier).updateSettings(
              settings.copyWith(
                labelPrinterEnabled: device.enabled,
                labelPrinterName: config['printerName'] as String? ?? '',
                labelPrinterIp: config['host'] as String? ?? '',
                labelPrinterPort:
                    HardwareDevicesNotifier._int(config['port'], 9100),
                labelPrinterLanguage: config['language'] as String? ?? 'tspl',
                labelWidthMm:
                    HardwareDevicesNotifier._int(config['labelWidthMm'], 50),
                labelHeightMm:
                    HardwareDevicesNotifier._int(config['labelHeightMm'], 30),
                labelGapMm:
                    HardwareDevicesNotifier._int(config['labelGapMm'], 2),
                labelAutoDetectGap:
                    config['autoDetectLabelGap'] as bool? ?? false,
                labelDpi: HardwareDevicesNotifier._int(config['dpi'], 203),
                labelPrinterCopies:
                    HardwareDevicesNotifier._int(config['copies'], 1)
                        .clamp(1, 20)
                        .toInt(),
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
          posConnection: 'tcp',
          posSerialPort: '',
          posBaudRate: 9600,
          posBridgeHost: '',
          posBridgePort: current.posBridgePort,
          posVendor: current.posVendor,
          posProtocol: current.posProtocol,
        ));
        ref.invalidate(hardwareConfigProvider);
        return;
      case HardwareDeviceType.receiptPrinter:
        final settings = await this._settings();
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
        final settings = await this._settings();
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
    final nonPrinters = (await _repository.getAll())
        .where((item) => !HardwareDevicesNotifier._isPrinter(item));
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
      return HardwareDevicesNotifier._fromPrinterProfile(profile, activeFor);
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
    await printing
        .saveDevice(HardwareDevicesNotifier._toPrinterProfile(device));
    if (!createRouteWhenMissing) return;
    for (final kind in HardwareDevicesNotifier._documentKinds(device.type)) {
      if (await printing.getRoute(kind) == null) {
        await this._savePrinterRoute(kind, device.id);
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
}
