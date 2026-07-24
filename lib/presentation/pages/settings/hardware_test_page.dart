import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';

class HardwareTestPage extends ConsumerWidget {
  const HardwareTestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(hardwareDevicesProvider);
    return FullScreenSettingsPage(
      title: 'Cihazlar ve Donanım',
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Cihaz ekle',
          onPressed: () => _openEditor(context, ref),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          error: error,
          onRetry: () => ref.invalidate(hardwareDevicesProvider),
        ),
        data: (items) => _DeviceList(
          devices: items,
          onAdd: () => _openEditor(context, ref),
          onEdit: (device) => _openEditor(context, ref, device: device),
          onTest: (device) => _testDevice(context, ref, device),
          onDelete: (device) => _deleteDevice(context, ref, device),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    HardwareDevice? device,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeviceEditor(device: device),
    );
    if (saved == true) ref.invalidate(hardwareDevicesProvider);
  }

  Future<void> _testDevice(
    BuildContext context,
    WidgetRef ref,
    HardwareDevice device,
  ) async {
    final result =
        await ref.read(hardwareDevicesProvider.notifier).test(device);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _TestResultDialog(result: result),
    );
  }

  Future<void> _deleteDevice(
    BuildContext context,
    WidgetRef ref,
    HardwareDevice device,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cihaz kaldırılsın mı?'),
        content: Text(
          '${device.name} kayıtlı cihazlardan kaldırılacak. Bu işlem fiziksel cihazı etkilemez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await ref.read(hardwareDevicesProvider.notifier).remove(device);
  }
}

class _DeviceList extends StatelessWidget {
  final List<HardwareDevice> devices;
  final VoidCallback onAdd;
  final ValueChanged<HardwareDevice> onEdit;
  final ValueChanged<HardwareDevice> onTest;
  final ValueChanged<HardwareDevice> onDelete;

  const _DeviceList({
    required this.devices,
    required this.onAdd,
    required this.onEdit,
    required this.onTest,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ready = devices
        .where((device) => device.status == HardwareDeviceStatus.ready)
        .length;
    final attention = devices
        .where((device) =>
            device.status == HardwareDeviceStatus.error ||
            device.status == HardwareDeviceStatus.offline)
        .length;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _SummaryCard(
            total: devices.length,
            ready: ready,
            attention: attention,
            onAdd: onAdd,
          ),
        ),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyDevices(onAdd: onAdd),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 16, bottom: 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent >= 900
                    ? 3
                    : constraints.crossAxisExtent >= 580
                        ? 2
                        : 1;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 244,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final device = devices[index];
                      return _DeviceCard(
                        device: device,
                        onEdit: () => onEdit(device),
                        onTest: () => onTest(device),
                        onDelete: () => onDelete(device),
                      );
                    },
                    childCount: devices.length,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int total;
  final int ready;
  final int attention;
  final VoidCallback onAdd;

  const _SummaryCard({
    required this.total,
    required this.ready,
    required this.attention,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 18,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.devices_other_rounded, color: kGreen, size: 36),
            _Metric(value: '$total', label: 'Kayıtlı'),
            _Metric(value: '$ready', label: 'Hazır', color: kGreen),
            _Metric(
              value: '$attention',
              label: 'Dikkat gerekli',
              color: attention == 0 ? kTextSecondary : kPink,
            ),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Cihaz ekle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Metric({
    required this.value,
    required this.label,
    this.color = kTextPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: kTextSecondary)),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final HardwareDevice device;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    required this.onEdit,
    required this.onTest,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = _statusPresentation(device.status);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      _typeColor(device.type).withValues(alpha: .1),
                  foregroundColor: _typeColor(device.type),
                  child: Icon(_typeIcon(device.type)),
                ),
                const Spacer(),
                _StatusBadge(label: status.$1, color: status.$2),
                PopupMenuButton<String>(
                  tooltip: 'Diğer işlemler',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                    PopupMenuItem(value: 'delete', child: Text('Kaldır')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '${_typeLabel(device.type)} · ${_connectionLabel(device.connectionType)}',
              style: const TextStyle(fontSize: 12, color: kTextSecondary),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Text(
                device.lastMessage ??
                    device.lastError ??
                    'Bağlantı henüz doğrulanmadı.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: device.lastError == null ? kTextSecondary : kPink,
                ),
              ),
            ),
            if (device.lastTestedAt != null)
              Text(
                'Son test: ${DateFormat('dd.MM.yyyy HH:mm').format(device.lastTestedAt!)}',
                style: const TextStyle(fontSize: 10, color: kTextSecondary),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: device.status == HardwareDeviceStatus.testing
                    ? null
                    : onTest,
                icon: device.status == HardwareDeviceStatus.testing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(device.status == HardwareDeviceStatus.testing
                    ? 'Test ediliyor'
                    : 'Bağlantıyı test et'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceEditor extends ConsumerStatefulWidget {
  final HardwareDevice? device;

  const _DeviceEditor({this.device});

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
  String _vendor = 'generic';
  String _protocol = 'vendor_sdk';
  int _paperWidth = 80;
  int _step = 0;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final device = widget.device;
    _type = device?.type ?? HardwareDeviceType.receiptPrinter;
    _connection = device?.connectionType ?? _connectionsFor(_type).first;
    final config = device?.configuration ?? const <String, Object?>{};
    _name = TextEditingController(text: device?.name ?? _typeLabel(_type));
    _host = TextEditingController(text: config['host']?.toString() ?? '');
    _port = TextEditingController(
        text: config['port']?.toString() ?? _defaultPort(_type).toString());
    _serialPort =
        TextEditingController(text: config['serialPort']?.toString() ?? '');
    _baudRate =
        TextEditingController(text: config['baudRate']?.toString() ?? '9600');
    _printerName =
        TextEditingController(text: config['printerName']?.toString() ?? '');
    _vendor = config['vendor']?.toString() ?? 'generic';
    _protocol = config['protocol']?.toString() ?? 'vendor_sdk';
    _paperWidth = int.tryParse(config['paperWidth']?.toString() ?? '') ?? 80;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _serialPort.dispose();
    _baudRate.dispose();
    _printerName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kBorderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.device == null ? 'Yeni cihaz ekle' : 'Cihazı düzenle',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${_step + 1}/3 · ${_stepLabel(_step)}',
                style: const TextStyle(fontSize: 12, color: kTextSecondary),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: (_step + 1) / 3),
              const SizedBox(height: 22),
              if (_step == 0) _typeStep(),
              if (_step == 1) _connectionStep(),
              if (_step == 2) _detailsStep(),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _InlineError(message: _error!),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed:
                          _working ? null : () => setState(() => _step--),
                      child: const Text('Geri'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _working ? null : _continue,
                    child: _working
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_step < 2 ? 'Devam' : 'Doğrula ve kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeStep() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: HardwareDeviceType.values.map((type) {
        final selected = type == _type;
        return ChoiceChip(
          avatar: Icon(_typeIcon(type), size: 18),
          label: Text(_typeLabel(type)),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _type = type;
              _connection = _connectionsFor(type).first;
              _name.text = _typeLabel(type);
              _port.text = _defaultPort(type).toString();
            });
          },
        );
      }).toList(),
    );
  }

  Widget _connectionStep() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _connectionsFor(_type).map((connection) {
        return ChoiceChip(
          label: Text(_connectionLabel(connection)),
          selected: connection == _connection,
          onSelected: (_) => setState(() => _connection = connection),
        );
      }).toList(),
    );
  }

  Widget _detailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Cihaz adı',
            helperText: 'Örn. Kasa 1 fiş yazıcısı',
          ),
        ),
        const SizedBox(height: 12),
        if (_connection == HardwareConnectionType.tcp) ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  decoration: const InputDecoration(labelText: 'IP adresi'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
        ],
        if (_connection == HardwareConnectionType.serial) ...[
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _serialPort,
                  decoration: const InputDecoration(labelText: 'COM portu'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _baudRate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Baud'),
                ),
              ),
            ],
          ),
        ],
        if (_type == HardwareDeviceType.receiptPrinter &&
            _connection == HardwareConnectionType.windows) ...[
          TextField(
            controller: _printerName,
            decoration: const InputDecoration(
              labelText: 'Windows yazıcı adı',
              helperText: 'Windows yazıcı listesindeki adla aynı olmalıdır.',
            ),
          ),
        ],
        if (_type == HardwareDeviceType.receiptPrinter &&
            _connection == HardwareConnectionType.bluetooth) ...[
          TextField(
            controller: _printerName,
            decoration: const InputDecoration(
              labelText: 'Bluetooth cihaz kimliği',
              helperText: 'Önceden eşleştirilmiş yazıcının adı veya adresi.',
            ),
          ),
        ],
        if (_type == HardwareDeviceType.paymentTerminal) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _vendor,
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
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged: (value) => _vendor = value ?? 'generic',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _protocol,
            decoration: const InputDecoration(labelText: 'Protokol'),
            items: const [
              DropdownMenuItem(value: 'vendor_sdk', child: Text('Üretici SDK')),
              DropdownMenuItem(value: 'gmp3', child: Text('GMP-3')),
              DropdownMenuItem(value: 'ecr', child: Text('ECR')),
            ],
            onChanged: (value) => _protocol = value ?? 'vendor_sdk',
          ),
        ],
        if (_type == HardwareDeviceType.receiptPrinter) ...[
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 58, label: Text('58 mm')),
              ButtonSegment(value: 80, label: Text('80 mm')),
            ],
            selected: {_paperWidth},
            onSelectionChanged: (values) =>
                setState(() => _paperWidth = values.first),
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
    if (!result.success) {
      setState(() {
        _working = false;
        _error = '${result.message}\n${result.technicalDetail ?? ''}'.trim();
      });
      return;
    }
    await ref.read(hardwareDevicesProvider.notifier).save(device.copyWith(
          status: HardwareDeviceStatus.ready,
          lastTestedAt: result.completedAt,
          lastMessage: result.message,
          clearLastError: true,
        ));
    if (mounted) Navigator.pop(context, true);
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Cihaz adı gereklidir.';
    if (_connection == HardwareConnectionType.tcp) {
      if (_host.text.trim().isEmpty) return 'IP adresi gereklidir.';
      if (int.tryParse(_port.text) == null) return 'Port sayı olmalıdır.';
    }
    if (_connection == HardwareConnectionType.serial) {
      if (_serialPort.text.trim().isEmpty) return 'COM portu gereklidir.';
      if (int.tryParse(_baudRate.text) == null) {
        return 'Baud değeri sayı olmalıdır.';
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
        'dataBits': 8,
        'stopBits': 1,
        'parity': 'none',
        'defaultUnit': 'kg',
        'printerName': _connection == HardwareConnectionType.embedded
            ? 'sunmi'
            : _connection == HardwareConnectionType.bluetooth
                ? _printerName.text.trim()
                : _printerName.text.trim(),
        'paperWidth': _paperWidth,
        'vendor': _vendor,
        'protocol': _protocol,
      },
    );
  }
}

class _TestResultDialog extends StatelessWidget {
  final HardwareTestResult result;

  const _TestResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        result.success ? Icons.check_circle_rounded : Icons.error_rounded,
        color: result.success ? kGreen : kPink,
        size: 48,
      ),
      title: Text(result.success ? 'Bağlantı hazır' : 'Bağlantı kurulamadı'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(result.message, textAlign: TextAlign.center),
          if (result.technicalDetail != null) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Teknik ayrıntı'),
              tilePadding: EdgeInsets.zero,
              children: [SelectableText(result.technicalDetail!)],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${result.elapsed.inMilliseconds} ms',
            style: const TextStyle(fontSize: 11, color: kTextSecondary),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyDevices({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.devices_other_rounded,
              size: 64, color: kTextSecondary),
          const SizedBox(height: 16),
          const Text('Henüz cihaz eklenmedi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'Yazıcı, terazi, POS veya barkod okuyucunuzu ekleyin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextSecondary),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('İlk cihazı ekle'),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPink.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: kPink),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: kPink))),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _LoadError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: kPink, size: 48),
          const SizedBox(height: 12),
          const Text('Cihazlar yüklenemedi'),
          const SizedBox(height: 6),
          Text('$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}

(String, Color) _statusPresentation(HardwareDeviceStatus status) {
  return switch (status) {
    HardwareDeviceStatus.unverified => ('Doğrulanmadı', kTextSecondary),
    HardwareDeviceStatus.testing => ('Test ediliyor', kBlue),
    HardwareDeviceStatus.ready => ('Hazır', kGreen),
    HardwareDeviceStatus.offline => ('Çevrimdışı', kOrange),
    HardwareDeviceStatus.error => ('Hata', kPink),
    HardwareDeviceStatus.disabled => ('Pasif', kTextSecondary),
  };
}

String _typeLabel(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter => 'Fiş yazıcısı',
      HardwareDeviceType.labelPrinter => 'Etiket yazıcısı',
      HardwareDeviceType.scale => 'Terazi',
      HardwareDeviceType.paymentTerminal => 'Fiziksel POS',
      HardwareDeviceType.barcodeScanner => 'Barkod okuyucu',
    };

IconData _typeIcon(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter => Icons.print_rounded,
      HardwareDeviceType.labelPrinter => Icons.label_rounded,
      HardwareDeviceType.scale => Icons.scale_rounded,
      HardwareDeviceType.paymentTerminal => Icons.credit_card_rounded,
      HardwareDeviceType.barcodeScanner => Icons.qr_code_scanner_rounded,
    };

Color _typeColor(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter => kBlue,
      HardwareDeviceType.labelPrinter => kTeal,
      HardwareDeviceType.scale => kGreen,
      HardwareDeviceType.paymentTerminal => kOrange,
      HardwareDeviceType.barcodeScanner => kPurple,
    };

String _connectionLabel(HardwareConnectionType connection) =>
    switch (connection) {
      HardwareConnectionType.embedded => 'Dahili',
      HardwareConnectionType.windows => 'Windows',
      HardwareConnectionType.bluetooth => 'Bluetooth',
      HardwareConnectionType.serial => 'COM / USB',
      HardwareConnectionType.tcp => 'TCP / Ağ',
      HardwareConnectionType.keyboard => 'USB klavye',
    };

List<HardwareConnectionType> _connectionsFor(HardwareDeviceType type) {
  return switch (type) {
    HardwareDeviceType.receiptPrinter => const [
        HardwareConnectionType.windows,
        HardwareConnectionType.tcp,
        HardwareConnectionType.bluetooth,
        HardwareConnectionType.embedded,
      ],
    HardwareDeviceType.labelPrinter => const [HardwareConnectionType.tcp],
    HardwareDeviceType.scale => const [
        HardwareConnectionType.serial,
        HardwareConnectionType.tcp,
      ],
    HardwareDeviceType.paymentTerminal => const [HardwareConnectionType.tcp],
    HardwareDeviceType.barcodeScanner => const [
        HardwareConnectionType.keyboard,
        HardwareConnectionType.embedded,
      ],
  };
}

int _defaultPort(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter ||
      HardwareDeviceType.labelPrinter =>
        9100,
      HardwareDeviceType.scale => 4001,
      HardwareDeviceType.paymentTerminal => 4100,
      HardwareDeviceType.barcodeScanner => 0,
    };

String _stepLabel(int step) => switch (step) {
      0 => 'Cihaz türü',
      1 => 'Bağlantı yöntemi',
      _ => 'Bağlantı bilgileri ve doğrulama',
    };
