part of '../hardware_test_page.dart';

class _DeviceEditor extends ConsumerStatefulWidget {
  final HardwareDevice? device;
  final bool desktopDialog;

  const _DeviceEditor({this.device, this.desktopDialog = false});

  @override
  ConsumerState<_DeviceEditor> createState() => _DeviceEditorState();
}

class _DeviceEditorState extends ConsumerState<_DeviceEditor> {
  late HardwareDeviceType _type;
  late HardwareConnectionType _connection;
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _serialPort;
  late final TextEditingController _baudRate;
  late final TextEditingController _printerName;
  late final TextEditingController _labelWidth;
  late final TextEditingController _labelHeight;
  late final TextEditingController _labelGap;
  late final TextEditingController _labelCopies;
  String _vendor = 'generic';
  String _protocol = 'vendor_sdk';
  int _dataBits = 8;
  int _stopBits = 1;
  String _parity = 'none';
  String _scaleUnit = 'kg';
  int _paperWidth = 80;
  String _labelLanguage = 'tspl';
  int _labelDpi = 203;
  int _printDirection = 0;
  bool _autoDetectLabelGap = false;
  bool _autoCut = true;
  bool _openDrawer = false;

  int _step = 0;
  bool _working = false;
  bool _discoveringBluetooth = false;
  bool _discoveringWindows = false;
  bool _discoveringNetwork = false;
  bool _discoveringShared = false;
  List<Map<String, String>> _bluetoothDevices = const [];
  List<DiscoveredPrinter> _discoveredPrinters = const [];
  List<DiscoveredSerialDevice> _serialDevices = const [];
  List<SharedHardwareDevice> _sharedDevices = const [];
  SharedHardwareDevice? _selectedSharedDevice;
  String? _error;
  HardwareTestResult? _draftTestResult;
  String? _verifiedFingerprint;

  @override
  void initState() {
    super.initState();
    final device = widget.device;
    if (device != null) _step = 2;
    _type = device?.type ?? HardwareDeviceType.receiptPrinter;
    _connection = device?.connectionType ?? _connectionsFor(_type).first;
    final config = device?.configuration ?? const <String, Object?>{};
    _name = TextEditingController(text: device?.name ?? _typeLabel(_type));
    _host = TextEditingController(text: config['host']?.toString() ?? '');
    _port = TextEditingController(
      text: config['port']?.toString() ?? _defaultPort(_type).toString(),
    );
    _serialPort = TextEditingController(
      text: config['serialPort']?.toString() ?? '',
    );
    _baudRate = TextEditingController(
      text: config['baudRate']?.toString() ?? '9600',
    );
    _printerName = TextEditingController(
      text: config['printerName']?.toString() ?? '',
    );
    _labelWidth = TextEditingController(
      text: config['labelWidthMm']?.toString() ?? '50',
    );
    _labelHeight = TextEditingController(
      text: config['labelHeightMm']?.toString() ?? '30',
    );
    _labelGap = TextEditingController(
      text: config['labelGapMm']?.toString() ?? '2',
    );
    _labelCopies = TextEditingController(
      text: config['copies']?.toString() ?? '1',
    );
    _vendor = config['vendor']?.toString() ?? 'generic';
    _protocol = config['protocol']?.toString() ?? 'vendor_sdk';
    _dataBits = int.tryParse(config['dataBits']?.toString() ?? '') ?? 8;
    _stopBits = int.tryParse(config['stopBits']?.toString() ?? '') ?? 1;
    _parity = config['parity']?.toString() ?? 'none';
    _scaleUnit = config['defaultUnit']?.toString() ?? 'kg';
    _paperWidth = int.tryParse(config['paperWidth']?.toString() ?? '') ?? 58;
    _labelLanguage = config['language']?.toString() ?? 'tspl';
    _labelDpi = int.tryParse(config['dpi']?.toString() ?? '') ?? 203;
    _printDirection =
        int.tryParse(config['printDirection']?.toString() ?? '') ?? 0;
    _autoDetectLabelGap = config['autoDetectLabelGap'] as bool? ?? false;

    _autoCut = config['autoCut'] as bool? ?? true;
    _openDrawer = config['openDrawer'] as bool? ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _serialPort.dispose();
    _baudRate.dispose();
    _printerName.dispose();
    _labelWidth.dispose();
    _labelHeight.dispose();
    _labelGap.dispose();
    _labelCopies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.device != null;
    final content = Material(
      key: const ValueKey('hardware-device-editor'),
      color: const Color(0xFFF8FAF9),
      borderRadius: BorderRadius.circular(widget.desktopDialog ? 24 : 28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (!widget.desktopDialog) ...[
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: kBorderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.desktopDialog ? 28 : 18,
              widget.desktopDialog ? 24 : 14,
              widget.desktopDialog ? 20 : 10,
              16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _typeColor(_type).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_typeIcon(_type), color: _typeColor(_type)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing ? widget.device!.name : 'Yeni aygıt ekle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: kTextPrimary,
                        ),
                      ),
                      Text(
                        editing
                            ? 'Aygıt ayarları · ${deviceFriendlyIdentity(widget.device!)}'
                            : '${_step + 1}/3 · İşletmenize yeni bir donanım bağlayın',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: kTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: _working ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                widget.desktopDialog ? 28 : 18,
                20,
                widget.desktopDialog ? 28 : 18,
                28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!editing) ...[
                    _EditorProgress(step: _step),
                    const SizedBox(height: 24),
                  ],
                  if (_step == 0) _typeStep(),
                  if (_step == 1) _connectionStep(),
                  if (_step == 2) _detailsStep(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _InlineError(message: _error!),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.desktopDialog ? 28 : 18,
              14,
              widget.desktopDialog ? 28 : 18,
              16,
            ),
            child: _editorActions(editing),
          ),
        ],
      ),
    );

    if (widget.desktopDialog) return content;
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: SizedBox(
          height: availableHeight * .92,
          child: content,
        ),
      ),
    );
  }

  Widget _editorActions(bool editing) {
    final back = _step > (editing ? 1 : 0)
        ? TextButton.icon(
            onPressed: _working ? null : () => setState(() => _step--),
            icon: Icon(
              editing ? Icons.cable_rounded : Icons.arrow_back_rounded,
              size: 18,
            ),
            label: Text(editing ? 'Bağlantı seçimi' : 'Geri'),
          )
        : const SizedBox.shrink();
    final test = _step == 2 && _connection != HardwareConnectionType.cloud
        ? OutlinedButton.icon(
            onPressed: _working ? null : _testDraft,
            icon: const Icon(Icons.cable_rounded, size: 18),
            label: const Text('Bağlantıyı test et'),
          )
        : const SizedBox.shrink();
    final primary = FilledButton.icon(
      onPressed: _working ? null : _continue,
      icon: _working
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(_step < 2
              ? Icons.arrow_forward_rounded
              : _connection == HardwareConnectionType.cloud
                  ? Icons.link_rounded
                  : Icons.save_rounded),
      label: Text(_step < 2
          ? 'Devam et'
          : _connection == HardwareConnectionType.cloud
              ? 'Ortak yazıcıyı kullan'
              : editing
                  ? 'Ayarları kaydet'
                  : 'Aygıtı kaydet'),
    );
    return LayoutBuilder(builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth < 350 || textScale > 1.1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_step > (editing ? 1 : 0)) ...[
              back,
              const SizedBox(height: 4),
            ],
            if (_step == 2 && _connection != HardwareConnectionType.cloud) ...[
              test,
              const SizedBox(height: 8),
            ],
            primary,
          ],
        );
      }
      if (constraints.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_step > (editing ? 1 : 0))
              Align(alignment: Alignment.centerLeft, child: back),
            if (_step > (editing ? 1 : 0)) const SizedBox(height: 4),
            if (_step == 2 && _connection != HardwareConnectionType.cloud)
              Row(
                children: [
                  Expanded(child: test),
                  const SizedBox(width: 8),
                  Expanded(child: primary),
                ],
              )
            else
              primary,
          ],
        );
      }
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [back, test, primary],
      );
    });
  }

  Widget _typeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ne eklemek istiyorsunuz?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Aygıt türünü seçin; uygun bağlantıları biz göstereceğiz.',
          style: TextStyle(fontSize: 12, color: kTextSecondary),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 620
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _managedDeviceTypes.map((type) {
                final selected = type == _type;
                return SizedBox(
                  width: width,
                  child: _SelectionCard(
                    selected: selected,
                    icon: _typeIcon(type),
                    color: _typeColor(type),
                    title: _typeLabel(type),
                    subtitle: _typeDescription(type),
                    onTap: () {
                      setState(() {
                        _type = type;
                        _connection = _connectionsFor(type).first;
                        _selectedSharedDevice = null;
                        _sharedDevices = const [];
                        _discoveredPrinters = const [];
                        _name.text = _typeLabel(type);
                        _port.text = _defaultPort(type).toString();
                      });
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _connectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_typeLabel(_type)} nasıl bağlı?',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bilmiyorsanız en tanıdık seçeneği seçin.',
          style: TextStyle(fontSize: 12, color: kTextSecondary),
        ),
        const SizedBox(height: 14),
        ..._connectionsFor(_type).map((connection) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SelectionCard(
                selected: connection == _connection,
                icon: _connectionIcon(connection),
                color: kGreen,
                title: _connectionLabel(connection),
                subtitle: _connectionDescription(connection),
                onTap: () => _selectConnection(connection),
              ),
            )),
      ],
    );
  }

  void _selectConnection(HardwareConnectionType connection) {
    if (connection == _connection) return;
    setState(() {
      _connection = connection;
      _error = null;
      _draftTestResult = null;
      _verifiedFingerprint = null;
      _selectedSharedDevice = null;
      _sharedDevices = const [];
      _discoveredPrinters = const [];
      _bluetoothDevices = const [];
      _serialDevices = const [];
      if (connection == HardwareConnectionType.tcp) {
        _host.clear();
        _port.text = _defaultPort(_type).toString();
      } else if (connection == HardwareConnectionType.serial) {
        _serialPort.clear();
      } else if (connection == HardwareConnectionType.windows ||
          connection == HardwareConnectionType.bluetooth) {
        _printerName.clear();
      }
    });
  }

  Widget _detailsStep() {
    final sharedConnection = _connection == HardwareConnectionType.cloud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_typeLabel(_type)} ayarları',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '${_connectionLabel(_connection)} için gerekli alanları doldurun.',
          style: const TextStyle(fontSize: 12, color: kTextSecondary),
        ),
        if (!sharedConnection) ...[
          const SizedBox(height: 20),
          const _FormSectionTitle(
            icon: Icons.badge_outlined,
            title: 'Genel bilgiler',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Aygıt adı',
              helperText: 'Örn. Kasa 1 fiş yazıcısı',
            ),
          ),
        ],
        const SizedBox(height: 22),
        const _FormSectionTitle(
          icon: Icons.cable_rounded,
          title: 'Bağlantı',
        ),
        const SizedBox(height: 10),
        if (_connection == HardwareConnectionType.embedded)
          const _ConnectionNotice(
            icon: Icons.smartphone_rounded,
            message:
                'Uygulama bu cihazdaki dahili yazıcıyı otomatik olarak kullanır.',
          ),
        if (_connection == HardwareConnectionType.tcp) ...[
          _ResponsiveFieldRow(
            flexes: const [3, 1],
            children: [
              TextField(
                controller: _host,
                decoration: const InputDecoration(labelText: 'IP adresi'),
              ),
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
              ),
            ],
          ),
        ],
        if (_connection == HardwareConnectionType.serial) ...[
          _ResponsiveFieldRow(
            flexes: const [2, 1],
            children: [
              TextField(
                controller: _serialPort,
                decoration: const InputDecoration(labelText: 'COM portu'),
              ),
              TextField(
                controller: _baudRate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Baud'),
              ),
            ],
          ),

        ],
        if ((_type == HardwareDeviceType.receiptPrinter ||
                _type == HardwareDeviceType.labelPrinter) &&
            _connection == HardwareConnectionType.windows) ...[
          OutlinedButton.icon(
            onPressed: _discoveringWindows ? null : _discoverWindowsPrinters,
            icon: _discoveringWindows
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.manage_search_rounded),
            label: Text(
              _discoveringWindows
                  ? 'Windows yazıcıları okunuyor…'
                  : 'Windows yazıcılarını bul',
            ),
          ),
          if (_discoveredPrinters.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._discoveredPrinters
                .where((item) => item.kind == DiscoveredPrinterKind.windows)
                .map(
                  (printer) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: printer.name,
                    groupValue: _printerName.text,
                    onChanged: (value) => setState(() {
                      _printerName.text = value ?? '';
                      if (_name.text == _typeLabel(_type)) {
                        _name.text = printer.name;
                      }
                    }),
                    title: Text(printer.name),
                    subtitle: Text(
                      printer.isDefault
                          ? 'Varsayılan Windows yazıcısı'
                          : 'Windows yazıcı kuyruğu',
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _printerName,
            decoration: const InputDecoration(
              labelText: 'Windows yazıcı adı',
              helperText: 'Windows yazıcı listesindeki adla aynı olmalıdır.',
            ),
          ),
        ],
        if (_connection == HardwareConnectionType.tcp) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _discoveringNetwork ? null : _discoverNetworkPrinters,
            icon: _discoveringNetwork
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar_rounded),
            label: Text(
              _discoveringNetwork
                  ? 'Yerel ağ taranıyor…'
                  : 'Aynı ağdaki ${_networkDeviceLabel(_type)} bul',
            ),
          ),
          if (_discoveredPrinters.any(
            (item) => item.kind == DiscoveredPrinterKind.network,
          )) ...[
            const SizedBox(height: 8),
            ..._discoveredPrinters
                .where((item) => item.kind == DiscoveredPrinterKind.network)
                .map(
                  (printer) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: printer.address ?? '',
                    groupValue: _host.text,
                    onChanged: (value) => setState(() {
                      _host.text = value ?? '';
                      _port.text = '${printer.port ?? 9100}';
                    }),
                    title: Text(
                      '${_networkCandidateLabel(_type)} ${printer.address ?? printer.name}:${printer.port ?? _defaultPort(_type)}',
                    ),
                    subtitle: const Text(
                      'Açık port bulundu · Bağlantı testiyle doğrulanacak',
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 10),
        ],
        if (_connection == HardwareConnectionType.serial) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _discoverSerialPorts,
            icon: const Icon(Icons.usb_rounded),
            label: const Text('USB / COM aygıtlarını bul'),
          ),
          if (_serialDevices.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._serialDevices.map(
              (device) => RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: device.port,
                groupValue: _serialPort.text,
                onChanged: (value) =>
                    setState(() => _serialPort.text = value ?? ''),
                title: Text(device.name),
                subtitle: Text(device.port),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if ((_type == HardwareDeviceType.receiptPrinter ||
                _type == HardwareDeviceType.labelPrinter) &&
            _connection == HardwareConnectionType.bluetooth) ...[
          OutlinedButton.icon(
            onPressed: _usesWindowsBluetoothSpooler
                ? (_discoveringWindows ? null : _discoverWindowsPrinters)
                : (_discoveringBluetooth ? null : _discoverBluetooth),
            icon: (_usesWindowsBluetoothSpooler
                    ? _discoveringWindows
                    : _discoveringBluetooth)
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching_rounded),
            label: Text(
              _usesWindowsBluetoothSpooler
                  ? (_discoveringWindows
                      ? 'Windows yazıcıları okunuyor…'
                      : 'Eşleştirilmiş Bluetooth yazıcılarını bul')
                  : (_discoveringBluetooth
                      ? 'Yakındaki cihazlar aranıyor…'
                      : 'Bluetooth cihazlarını tara'),
            ),
          ),
          if (_usesWindowsBluetoothSpooler &&
              _discoveredPrinters.any(
                (item) => item.kind == DiscoveredPrinterKind.windows,
              )) ...[
            const SizedBox(height: 8),
            ..._discoveredPrinters
                .where((item) => item.kind == DiscoveredPrinterKind.windows)
                .map(
                  (printer) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: printer.name,
                    groupValue: _printerName.text,
                    onChanged: (value) => setState(() {
                      _printerName.text = value ?? '';
                      if (_name.text == _typeLabel(_type)) {
                        _name.text = printer.name;
                      }
                    }),
                    title: Text(printer.name),
                    subtitle: Text(
                      printer.isDefault
                          ? 'Varsayılan Windows yazıcısı'
                          : 'Eşleştirilmiş Windows yazıcı kuyruğu',
                    ),
                  ),
                ),
          ],
          if (!_usesWindowsBluetoothSpooler &&
              _bluetoothDevices.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._bluetoothDevices.map((device) {
              final address = device['address'] ?? '';
              final name = device['name'] ?? 'İsimsiz cihaz';
              return RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: address,
                groupValue: _printerName.text,
                onChanged: (value) => setState(() {
                  _printerName.text = value ?? '';
                }),
                title: Text(name, overflow: TextOverflow.ellipsis),
                subtitle: Text(address),
              );
            }),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _printerName,
            readOnly: !_usesWindowsBluetoothSpooler,
            decoration: InputDecoration(
              labelText: 'Seçilen Bluetooth yazıcı',
              helperText: _usesWindowsBluetoothSpooler
                  ? 'Yazıcı önce Windows Bluetooth ayarlarından eşleştirilmiş olmalıdır.'
                  : 'Bağlantıda cihazın MAC adresi kullanılır.',
            ),
          ),
        ],
        if ((_type == HardwareDeviceType.receiptPrinter ||
                _type == HardwareDeviceType.labelPrinter) &&
            _connection == HardwareConnectionType.cloud) ...[
          OutlinedButton.icon(
            onPressed: _discoveringShared ? null : _discoverSharedDevices,
            icon: _discoveringShared
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_rounded),
            label: Text(
              _discoveringShared
                  ? 'Ortak cihazlar aranıyor…'
                  : 'Ortak cihazları bul',
            ),
          ),
          if (_sharedDevices.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._sharedDevices.map(
              (device) => RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: device.id,
                groupValue: _selectedSharedDevice?.id,
                onChanged: device.online
                    ? (_) => setState(() {
                          _selectedSharedDevice = device;
                          _name.text = device.name;
                        })
                    : null,
                title: Text(device.name),
                subtitle: Text(
                  device.online
                      ? 'Çevrimiçi · ${device.connectionType}'
                      : 'Sahip cihaz çevrimdışı',
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Aynı işletme hesabındaki açık bir cihazın paylaştığı yazıcı kullanılır.',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
          ),
        ],
        if (!sharedConnection) ...[
          const SizedBox(height: 22),
          const _FormSectionTitle(
            icon: Icons.tune_rounded,
            title: 'Donanım özellikleri',
          ),
          const SizedBox(height: 10),
        ],
        if (_type == HardwareDeviceType.scale) ...[
          DropdownButtonFormField<String>(
            value: _scaleUnit,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Terazinin gönderdiği varsayılan birim',
            ),
            items: const [
              DropdownMenuItem(value: 'kg', child: Text('Kilogram (kg)')),
              DropdownMenuItem(value: 'g', child: Text('Gram (g)')),
            ],
            onChanged: (value) => _scaleUnit = value ?? 'kg',
          ),
        ],
        if (_type == HardwareDeviceType.paymentTerminal) ...[
          DropdownButtonFormField<String>(
            value: _vendor,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Üretici'),
            items: const {
              'generic': 'Genel POS',
              'beko_token': 'Beko / Token',
              'ingenico': 'Ingenico',
              'verifone_profilo': 'Verifone / Profilo',
              'hugin': 'Hugin',
              'vera': 'Vera',
            }
                .entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) => _vendor = value ?? 'generic',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _protocol,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Protokol'),
            items: const [
              DropdownMenuItem(value: 'vendor_sdk', child: Text('Üretici SDK')),
              DropdownMenuItem(value: 'gmp3', child: Text('GMP-3')),
              DropdownMenuItem(value: 'ecr', child: Text('ECR')),
            ],
            onChanged: (value) => _protocol = value ?? 'vendor_sdk',
          ),
          const SizedBox(height: 8),
          const Text(
            'POS cihazı doğrudan bağlanmaz; seçilen banka/üretici SDK’sını kullanan Serenut POS Bridge bu IP ve portta çalışmalıdır.',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
          ),
        ],
        if (_type == HardwareDeviceType.receiptPrinter &&
            !sharedConnection) ...[
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 58, label: Text('58 mm')),
              ButtonSegment(value: 80, label: Text('80 mm')),
            ],
            selected: {_paperWidth},
            onSelectionChanged: (values) =>
                setState(() => _paperWidth = values.first),
          ),
          const SizedBox(height: 12),
          _SettingsToggle(
            title: 'Fiş sonunda otomatik kes',
            value: _autoCut,
            onChanged: (val) => setState(() => _autoCut = val),
          ),
          const SizedBox(height: 8),
          _SettingsToggle(
            title: 'Kasa çekmecesini aç',
            value: _openDrawer,
            onChanged: (val) => setState(() => _openDrawer = val),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _labelCopies,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Yazdırılacak kopya sayısı',
              helperText: '1-20 arasında bir değer girin.',
            ),
          ),
        ],
        if (_type == HardwareDeviceType.labelPrinter && !sharedConnection) ...[
          _ResponsiveFieldRow(
            children: [
              TextField(
                controller: _labelWidth,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Etiket eni (mm)'),
              ),
              TextField(
                controller: _labelHeight,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Etiket boyu (mm)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelGap,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Etiketler arası boşluk (mm)',
              helperText:
                  '58 mm yazıcı genişliği ile etiketin gerçek en/boy ölçüsü aynı ayar değildir.',
            ),
          ),
          const SizedBox(height: 4),
          _SettingsToggle(
            title: 'Gap boşluğunu otomatik algıla',
            subtitle:
                'Gaplı etiket kullanıldığında yazıcı sensörü etiket aralığını kalibre eder.',
            value: _autoDetectLabelGap,
            onChanged: (value) => setState(() => _autoDetectLabelGap = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelCopies,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Her ürün için etiket adedi',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 203, label: Text('203 DPI')),
              ButtonSegment(value: 300, label: Text('300 DPI')),
            ],
            selected: {_labelDpi},
            onSelectionChanged: (values) =>
                setState(() => _labelDpi = values.first),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Normal yön')),
              ButtonSegment(value: 1, label: Text('Ters yön')),
            ],
            selected: {_printDirection},
            onSelectionChanged: (values) =>
                setState(() => _printDirection = values.first),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rulo üzerindeki tek etiketin gerçek en ve boy ölçüsünü girin. 58 mm cihaz, en fazla 58 mm medya kullanabildiğini belirtir; örneğin gerçek etiket 50×30 mm olabilir.',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
          ),
        ],
      ],
    );
  }

  Future<void> _continue() async {
    setState(() => _error = null);
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    await _saveDevice();
  }

  Future<void> _testDraft() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() => _working = true);
    final device = _buildDevice();
    final result =
        await ref.read(hardwareDevicesProvider.notifier).verify(device);
    if (!mounted) return;
    setState(() {
      _working = false;
      _draftTestResult = result;
      _verifiedFingerprint = result.success ? _fingerprint(device) : null;
      _error = result.success
          ? null
          : '${result.message}\n${result.technicalDetail ?? ''}'.trim();
    });
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: kGreen),
      );
    }
  }

  Future<void> _saveDevice() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() => _working = true);
    try {
      if (_connection == HardwareConnectionType.cloud) {
        await ref
            .read(hardwareDevicesProvider.notifier)
            .activateSharedPrinter(_selectedSharedDevice!);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      var device = _buildDevice().copyWith(
        status: HardwareDeviceStatus.unverified,
        lastMessage: 'Ayarlar kaydedildi; bağlantı doğrulaması bekleniyor.',
        clearLastError: true,
      );
      final result = _draftTestResult;
      if (result?.success == true &&
          _verifiedFingerprint == _fingerprint(device)) {
        final isPrinter = device.type == HardwareDeviceType.receiptPrinter ||
            device.type == HardwareDeviceType.labelPrinter;
        device = device.copyWith(
          status: isPrinter
              ? HardwareDeviceStatus.unverified
              : HardwareDeviceStatus.ready,
          lastTestedAt: result!.completedAt,
          lastMessage: isPrinter
              ? '${result.message}. Fiziksel çıktı testi bekleniyor.'
              : result.message,
          clearLastError: true,
        );
      }
      await ref.read(hardwareDevicesProvider.notifier).save(device);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'Cihaz ayarları kaydedilemedi: $error';
      });
    }
  }

  String _fingerprint(HardwareDevice device) => jsonEncode({
        'name': device.name,
        'type': device.type.name,
        'connection': device.connectionType.name,
        'configuration': device.configuration,
      });

  Future<void> _discoverBluetooth() async {
    setState(() {
      _discoveringBluetooth = true;
      _error = null;
    });
    try {
      final devices = await NativePrinterBridge.scanBluetoothDevices();
      if (!mounted) return;
      setState(() {
        _bluetoothDevices = devices;
        if (devices.isEmpty) {
          _error =
              'Cihaz bulunamadı. Bluetooth ve yakın cihaz izinlerini verip tekrar tarayın.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Bluetooth taraması başarısız: $error');
      }
    } finally {
      if (mounted) setState(() => _discoveringBluetooth = false);
    }
  }

  Future<void> _discoverWindowsPrinters() async {
    setState(() {
      _discoveringWindows = true;
      _error = null;
    });
    try {
      final printers = await PrinterDiscoveryService().listWindowsPrinters();
      if (!mounted) return;
      setState(() {
        _discoveredPrinters = [
          ..._discoveredPrinters.where(
            (item) => item.kind != DiscoveredPrinterKind.windows,
          ),
          ...printers,
        ];
        if (printers.isEmpty) {
          _error = 'Windows yazıcısı bulunamadı. Yazıcı sürücüsünü ve Print '
              'Spooler hizmetini kontrol edin.';
        } else if (_printerName.text.isEmpty) {
          final preferred =
              printers.where((item) => item.isDefault).firstOrNull ??
                  printers.first;
          _printerName.text = preferred.name;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Windows yazıcıları okunamadı: $error');
      }
    } finally {
      if (mounted) setState(() => _discoveringWindows = false);
    }
  }

  Future<void> _discoverNetworkPrinters() async {
    setState(() {
      _discoveringNetwork = true;
      _error = null;
    });
    try {
      final discovery = PrinterDiscoveryService();
      final subnets = await discovery.localIpv4Subnets();
      final found = <DiscoveredPrinter>[];
      for (final subnet in subnets.take(2)) {
        found.addAll(
          await discovery.scanSubnet(subnet, ports: [_defaultPort(_type)]),
        );
      }
      if (!mounted) return;
      setState(() {
        _discoveredPrinters = [
          ..._discoveredPrinters.where(
            (item) => item.kind != DiscoveredPrinterKind.network,
          ),
          ...found,
        ];
        if (found.isEmpty) {
          _error =
              'Aynı ağda ${_defaultPort(_type)} portunu kullanan ${_networkCandidateLabel(_type).toLowerCase()} bulunamadı. '
              'Cihaz farklı VLAN üzerindeyse IP adresini manuel girin.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Ağ taraması tamamlanamadı: $error');
    } finally {
      if (mounted) setState(() => _discoveringNetwork = false);
    }
  }

  Future<void> _discoverSerialPorts() async {
    try {
      final ports = SerialScaleAdapter.availablePorts;
      final devices = await PrinterDiscoveryService().listSerialDevices(ports);
      if (!mounted) return;
      setState(() {
        _serialDevices = devices;
        _error = devices.isEmpty
            ? 'USB / COM aygıtı bulunamadı. Sürücünün kurulu olduğunu kontrol edin.'
            : null;
        if (_serialPort.text.isEmpty && devices.isNotEmpty) {
          _serialPort.text = devices.first.port;
        }
      });
    } catch (error) {
      setState(() => _error = 'Seri portlar okunamadı: $error');
    }
  }

  Future<void> _discoverSharedDevices() async {
    setState(() {
      _discoveringShared = true;
      _error = null;
    });
    try {
      final devices = await ref.read(sharedHardwareServiceProvider).list();
      if (!mounted) return;
      final candidates = devices
          .where((device) => !device.isLocal && device.type == _type)
          .toList(growable: false);
      setState(() {
        _sharedDevices = candidates;
        if (candidates.isEmpty) {
          _error =
              'Başka bir açık cihaz tarafından paylaşılan ${_typeLabel(_type).toLowerCase()} bulunamadı.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Ortak cihazlar alınamadı. Bağlantınızı kontrol edin: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _discoveringShared = false);
    }
  }

  String? _validate() {
    if (_connection != HardwareConnectionType.cloud &&
        _name.text.trim().isEmpty) {
      return 'Aygıt adı gereklidir.';
    }
    if (_connection == HardwareConnectionType.tcp) {
      if (_host.text.trim().isEmpty) return 'IP adresi gereklidir.';
      final port = int.tryParse(_port.text);
      if (port == null || port < 1 || port > 65535) {
        return 'Port 1-65535 arasında olmalıdır.';
      }
    }
    if (_connection == HardwareConnectionType.serial) {
      if (_serialPort.text.trim().isEmpty) return 'COM portu gereklidir.';
      final baud = int.tryParse(_baudRate.text);
      if (baud == null || baud <= 0) {
        return 'Baud değeri sıfırdan büyük olmalıdır.';
      }
    }
    if (_connection == HardwareConnectionType.windows &&
        _printerName.text.trim().isEmpty) {
      return 'Windows yazıcı adı gereklidir.';
    }
    if (_connection == HardwareConnectionType.bluetooth &&
        _printerName.text.trim().isEmpty) {
      return 'Bluetooth cihaz kimliği gereklidir.';
    }
    if (_connection == HardwareConnectionType.cloud &&
        _selectedSharedDevice == null) {
      return 'Kullanılacak ortak cihazı seçin.';
    }
    if (_type == HardwareDeviceType.receiptPrinter &&
        _connection != HardwareConnectionType.cloud) {
      final copies = int.tryParse(_labelCopies.text);
      if (copies == null || copies < 1 || copies > 20) {
        return 'Kopya sayısı 1-20 arasında olmalıdır.';
      }
    }
    if (_type == HardwareDeviceType.labelPrinter &&
        _connection != HardwareConnectionType.cloud) {
      final width = int.tryParse(_labelWidth.text);
      final height = int.tryParse(_labelHeight.text);
      final gap = int.tryParse(_labelGap.text);
      final copies = int.tryParse(_labelCopies.text);
      if (width == null || width < 30 || width > 100) {
        return 'Etiket eni 30-100 mm arasında olmalıdır.';
      }
      if (height == null || height < 20 || height > 100) {
        return 'Etiket boyu 20-100 mm arasında olmalıdır.';
      }
      if (gap == null || gap < 0 || gap > 10) {
        return 'Etiket boşluğu 0-10 mm arasında olmalıdır.';
      }
      if (copies == null || copies < 1 || copies > 20) {
        return 'Etiket adedi 1-20 arasında olmalıdır.';
      }
    }
    return null;
  }

  HardwareDevice _buildDevice() {
    final id = widget.device?.id ??
        '${_type.name}-${DateTime.now().microsecondsSinceEpoch}';
    return HardwareDevice(
      id: id,
      name: _name.text.trim(),
      type: _type,
      connectionType: _connection,
      enabled: true,
      configuration: {
        'host': _host.text.trim(),
        'port': int.tryParse(_port.text) ?? _defaultPort(_type),
        'serialPort': _serialPort.text.trim(),
        'baudRate': int.tryParse(_baudRate.text) ?? 9600,
        'dataBits': _dataBits,
        'stopBits': _stopBits,
        'parity': _parity,
        'defaultUnit': _scaleUnit,
        'printerName': _connection == HardwareConnectionType.embedded
            ? 'sunmi'
            : _connection == HardwareConnectionType.bluetooth
                ? _printerName.text.trim()
                : _printerName.text.trim(),
        'paperWidth': _paperWidth,
        'vendor': _vendor,
        'protocol': _protocol,
        'language': _labelLanguage,
        'labelWidthMm': int.tryParse(_labelWidth.text) ?? 50,
        'labelHeightMm': int.tryParse(_labelHeight.text) ?? 30,
        'labelGapMm': int.tryParse(_labelGap.text) ?? 2,
        'autoDetectLabelGap': _labelLanguage == 'tspl' && _autoDetectLabelGap,
        'dpi': _labelDpi,
        'printableWidthDots': () {
          final resolvedWidth = int.tryParse(_labelWidth.text) ?? 50;
          final calcDots = (resolvedWidth * _labelDpi / 25.4).round();
          final maxNarrowDots = (48.0 * _labelDpi / 25.4).round();
          return resolvedWidth <= 54
              ? math.min(calcDots, maxNarrowDots)
              : calcDots;
        }(),
        'printDirection': _printDirection,
        'copies': int.tryParse(_labelCopies.text) ?? 1,
        'autoCut': _autoCut,
        'openDrawer': _openDrawer,
      },
    );
  }

  bool get _usesWindowsBluetoothSpooler =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      _connection == HardwareConnectionType.bluetooth;
}

class _EditorProgress extends StatelessWidget {
  final int step;

  const _EditorProgress({required this.step});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Semantics(
            label: '${step + 1}/3 · ${_stepLabel(step)}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(5, (index) {
                    if (index.isOdd) {
                      final connector = index ~/ 2;
                      return Expanded(
                        child: Container(
                          height: 2,
                          color: connector < step ? kGreen : kBorderColor,
                        ),
                      );
                    }
                    final item = index ~/ 2;
                    final active = item == step;
                    final complete = item < step;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: active ? 32 : 26,
                      height: active ? 32 : 26,
                      decoration: BoxDecoration(
                        color: active || complete ? kGreen : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: active || complete ? kGreen : kBorderColor,
                        ),
                      ),
                      child: Icon(
                        complete ? Icons.check_rounded : _stepIcon(item),
                        size: active ? 17 : 14,
                        color:
                            active || complete ? Colors.white : kTextSecondary,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                Text(
                  '${step + 1}/3 · ${_stepLabel(step)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
              ],
            ),
          );
        }
        return Row(
          children: List.generate(3, (index) {
            final active = index == step;
            final complete = index < step;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(right: index == 2 ? 0 : 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFE5F4EE) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? kGreen : kBorderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      complete ? Icons.check_circle_rounded : _stepIcon(index),
                      size: 18,
                      color: active || complete ? kGreen : kTextSecondary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _stepLabel(index),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? kTextPrimary : kTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _FormSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _FormSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: kGreen),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        title: Text(title),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(fontSize: 11, color: kTextSecondary),
              ),
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ConnectionNotice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kGreen.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kGreen.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: kGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                height: 1.35,
                fontSize: 12,
                color: kTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  final List<Widget> children;
  final List<int>? flexes;
  static const double breakpoint = 500;

  const _ResponsiveFieldRow({
    required this.children,
    this.flexes,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                children[index],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(
                flex: flexes != null && index < flexes!.length
                    ? flexes![index]
                    : 1,
                child: children[index],
              ),
            ],
          ],
        );
      },
    );
  }
}

IconData _stepIcon(int step) => switch (step) {
      0 => Icons.category_rounded,
      1 => Icons.cable_rounded,
      _ => Icons.tune_rounded,
    };

class _SelectionCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: .07) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? color : kBorderColor,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? color : kBorderColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

