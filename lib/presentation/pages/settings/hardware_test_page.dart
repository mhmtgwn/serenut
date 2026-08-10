import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';
import 'package:serenutos/infrastructure/services/printer_discovery_service.dart';
import 'package:serenutos/domain/hardware/scale_service.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/infrastructure/services/shared_hardware_service.dart';
import 'dart:convert';

class HardwareTestPage extends ConsumerWidget {
  const HardwareTestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(hardwareDevicesProvider);
    return FullScreenSettingsPage(
      title: 'Aygıt Yöneticisi',
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Bağlantıları yenile',
          onPressed: () => _refreshDevices(context, ref),
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Ortak yazıcılar',
          onPressed: () => _openSharedPrinters(context, ref),
          icon: const Icon(Icons.cloud_queue_rounded),
        ),
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
          onActivate: (device) => _activateDevice(context, ref, device),
          onTest: (device) => _testDevice(context, ref, device),
          onDelete: (device) => _deleteDevice(context, ref, device),
        ),
      ),
    );
  }

  Future<void> _openSharedPrinters(
    BuildContext context,
    WidgetRef ref,
  ) async {
    ref.invalidate(sharedHardwareDevicesProvider);
    final selected = await showDialog<SharedHardwareDevice>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final shared = ref.watch(sharedHardwareDevicesProvider);
          return AlertDialog(
            title: const Text('Ortak yazıcılar'),
            content: SizedBox(
              width: 520,
              child: shared.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text(
                  'Ortak donanımlar alınamadı. Bağlantınızı kontrol edip yeniden deneyin.\n$error',
                ),
                data: (items) {
                  final printers = items
                      .where((item) =>
                          !item.isLocal &&
                          (item.type == HardwareDeviceType.receiptPrinter ||
                              item.type == HardwareDeviceType.labelPrinter))
                      .toList(growable: false);
                  if (printers.isEmpty) {
                    return const Text(
                      'Başka bir açık cihaz tarafından paylaşılan yazıcı bulunamadı.',
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: printers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final printer = printers[index];
                      return ListTile(
                        enabled: printer.online,
                        leading: Icon(
                          printer.type == HardwareDeviceType.receiptPrinter
                              ? Icons.receipt_long_rounded
                              : Icons.label_rounded,
                        ),
                        title: Text(printer.name),
                        subtitle: Text(printer.online
                            ? 'Çevrimiçi · ${printer.connectionType}'
                            : 'Sahip cihaz çevrimdışı'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(dialogContext, printer),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Kapat'),
              ),
            ],
          );
        },
      ),
    );
    if (selected == null || !context.mounted) return;
    try {
      await ref
          .read(hardwareDevicesProvider.notifier)
          .activateSharedPrinter(selected);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${selected.name} varsayılan ortak yazıcı oldu.'),
        backgroundColor: kGreen,
      ));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString()),
        backgroundColor: kPink,
      ));
    }
  }

  Future<void> _refreshDevices(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(hardwareDevicesProvider.notifier).refreshConnections();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cihaz bağlantıları yenilendi.'),
        backgroundColor: kGreen,
      ));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bağlantılar yenilenemedi: $error'),
        backgroundColor: kPink,
      ));
    }
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
    PrintDocumentKind? kind;
    if (device.type == HardwareDeviceType.labelPrinter) {
      kind = await showDialog<PrintDocumentKind>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Test etiketi türü'),
          content: const Text(
            'Aynı fiziksel cihaz farklı tasarım profilleri kullanır. '
            'Fiziksel olarak sınanacak belgeyi seçin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                PrintDocumentKind.productLabel,
              ),
              child: const Text('Ürün etiketi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                PrintDocumentKind.orderLabel,
              ),
              child: const Text('Sipariş etiketi'),
            ),
          ],
        ),
      );
      if (kind == null || !context.mounted) return;
    }
    final result = await ref
        .read(hardwareDevicesProvider.notifier)
        .test(device, printKind: kind);
    if (!context.mounted) return;
    final physicalResult = await showDialog<bool>(
      context: context,
      builder: (_) => _TestResultDialog(result: result),
    );
    if (result.requiresPhysicalConfirmation && physicalResult != null) {
      await ref
          .read(hardwareDevicesProvider.notifier)
          .confirmPhysicalPrintTest(result, passed: physicalResult);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(physicalResult
            ? 'Yazıcı fiziksel olarak doğrulandı.'
            : 'Test reddedildi; cihaz kontrol edilmeli.'),
        backgroundColor: physicalResult ? kGreen : kPink,
      ));
    }
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
    try {
      await ref.read(hardwareDevicesProvider.notifier).remove(device);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${device.name} kaldırıldı.'),
        backgroundColor: kGreen,
      ));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cihaz kaldırılamadı: $error'),
        backgroundColor: kPink,
      ));
    }
  }

  Future<void> _activateDevice(
    BuildContext context,
    WidgetRef ref,
    HardwareDevice device,
  ) async {
    try {
      await ref.read(hardwareDevicesProvider.notifier).activate(device);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${device.name} aktif cihaz oldu.'),
        backgroundColor: kGreen,
      ));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cihaz aktifleştirilemedi: $error'),
        backgroundColor: kPink,
      ));
    }
  }
}

enum _DeviceFilter { all, printers, salesHardware }

class _DeviceList extends StatefulWidget {
  final List<HardwareDevice> devices;
  final VoidCallback onAdd;
  final ValueChanged<HardwareDevice> onEdit;
  final ValueChanged<HardwareDevice> onActivate;
  final ValueChanged<HardwareDevice> onTest;
  final ValueChanged<HardwareDevice> onDelete;

  const _DeviceList({
    required this.devices,
    required this.onAdd,
    required this.onEdit,
    required this.onActivate,
    required this.onTest,
    required this.onDelete,
  });

  @override
  State<_DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<_DeviceList> {
  _DeviceFilter _filter = _DeviceFilter.all;

  @override
  Widget build(BuildContext context) {
    final devices = widget.devices;
    final ready = devices
        .where((device) => device.status == HardwareDeviceStatus.ready)
        .length;
    final attention = devices
        .where((device) =>
            device.status == HardwareDeviceStatus.error ||
            device.status == HardwareDeviceStatus.offline)
        .length;
    final visible = devices.where((device) {
      return switch (_filter) {
        _DeviceFilter.all => true,
        _DeviceFilter.printers =>
          device.type == HardwareDeviceType.receiptPrinter ||
              device.type == HardwareDeviceType.labelPrinter,
        _DeviceFilter.salesHardware =>
          device.type != HardwareDeviceType.receiptPrinter &&
              device.type != HardwareDeviceType.labelPrinter,
      };
    }).toList(growable: false);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HardwareHero(
            total: devices.length,
            ready: ready,
            attention: attention,
            onAdd: widget.onAdd,
          ),
        ),
        if (devices.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Tümü (${devices.length})'),
                    selected: _filter == _DeviceFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _DeviceFilter.all),
                  ),
                  ChoiceChip(
                    label: Text(
                      'Yazıcılar (${devices.where((device) => device.type == HardwareDeviceType.receiptPrinter || device.type == HardwareDeviceType.labelPrinter).length})',
                    ),
                    selected: _filter == _DeviceFilter.printers,
                    onSelected: (_) =>
                        setState(() => _filter = _DeviceFilter.printers),
                  ),
                  ChoiceChip(
                    label: Text(
                      'Satış donanımı (${devices.where((device) => device.type != HardwareDeviceType.receiptPrinter && device.type != HardwareDeviceType.labelPrinter).length})',
                    ),
                    selected: _filter == _DeviceFilter.salesHardware,
                    onSelected: (_) =>
                        setState(() => _filter = _DeviceFilter.salesHardware),
                  ),
                ],
              ),
            ),
          ),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyDevices(onAdd: widget.onAdd),
          )
        else if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Bu grupta kayıtlı cihaz yok.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 20, bottom: 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent >= 760 ? 2 : 1;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: 238,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final device = visible[index];
                      return _DeviceCard(
                        device: device,
                        onEdit: () => widget.onEdit(device),
                        onActivate: () => widget.onActivate(device),
                        onTest: () => widget.onTest(device),
                        onDelete: () => widget.onDelete(device),
                      );
                    },
                    childCount: visible.length,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _HardwareHero extends StatelessWidget {
  final int total;
  final int ready;
  final int attention;
  final VoidCallback onAdd;

  const _HardwareHero({
    required this.total,
    required this.ready,
    required this.attention,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF12352B), Color(0xFF1B5A48)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('İşletme donanımlarınız',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                  'Yazıcı, terazi ve POS bağlantılarını tek yerden yönetin.',
                  style: TextStyle(color: Color(0xFFCDE5DD), height: 1.35),
                ),
              ],
            ),
          ),
          _HeroMetric(value: '$total', label: 'Cihaz'),
          _HeroMetric(value: '$ready', label: 'Hazır'),
          _HeroMetric(
            value: '$attention',
            label: 'Kontrol',
            alert: attention > 0,
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF174B3D),
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Yeni aygıt'),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String value;
  final String label;
  final bool alert;

  const _HeroMetric({
    required this.value,
    required this.label,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: alert
            ? const Color(0xFFFFE1E5).withValues(alpha: .16)
            : Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFCDE5DD))),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final HardwareDevice device;
  final VoidCallback onEdit;
  final VoidCallback onActivate;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    required this.onEdit,
    required this.onActivate,
    required this.onTest,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = _statusPresentation(device.status);
    final activeFor = (device.configuration['activeFor'] as List?)
            ?.map((value) => value.toString())
            .toList(growable: false) ??
        const <String>[];
    final isPrinter = device.type == HardwareDeviceType.receiptPrinter ||
        device.type == HardwareDeviceType.labelPrinter;
    final isActive = isPrinter
        ? activeFor.isNotEmpty
        : device.configuration['isActive'] as bool? ?? true;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isActive ? kGreen : kBorderColor,
          width: isActive ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _typeColor(device.type).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_typeIcon(device.type),
                        color: _typeColor(device.type)),
                  ),
                  const Spacer(),
                  if (isActive) ...[
                    const _StatusBadge(label: 'Aktif', color: kGreen),
                    const SizedBox(width: 6),
                  ],
                  _StatusBadge(label: status.$1, color: status.$2),
                  PopupMenuButton<String>(
                    tooltip: 'Diğer işlemler',
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'activate') onActivate();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      if (!isActive)
                        const PopupMenuItem(
                            value: 'activate', child: Text('Aktif cihaz yap')),
                      const PopupMenuItem(
                          value: 'edit', child: Text('Düzenle')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Kaldır')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 4),
              Text(
                _deviceConfigurationSummary(device),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
              if (isPrinter && isActive) ...[
                const SizedBox(height: 4),
                Text(
                  _activeRouteLabel(activeFor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kGreen,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  device.lastMessage ??
                      device.lastError ??
                      'Bağlantı henüz doğrulanmadı.',
                  maxLines: 2,
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Ayarlar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
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
                          ? 'Bekleyin'
                          : 'Test et'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
  late final TextEditingController _labelWidth;
  late final TextEditingController _labelHeight;
  late final TextEditingController _labelGap;
  late final TextEditingController _labelCopies;
  late final TextEditingController _printableWidthDots;
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
  List<Map<String, String>> _bluetoothDevices = const [];
  List<DiscoveredPrinter> _discoveredPrinters = const [];
  List<String> _serialPorts = const [];
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
        text: config['port']?.toString() ?? _defaultPort(_type).toString());
    _serialPort =
        TextEditingController(text: config['serialPort']?.toString() ?? '');
    _baudRate =
        TextEditingController(text: config['baudRate']?.toString() ?? '9600');
    _printerName =
        TextEditingController(text: config['printerName']?.toString() ?? '');
    _labelWidth =
        TextEditingController(text: config['labelWidthMm']?.toString() ?? '50');
    _labelHeight = TextEditingController(
        text: config['labelHeightMm']?.toString() ?? '30');
    _labelGap =
        TextEditingController(text: config['labelGapMm']?.toString() ?? '2');
    _labelCopies =
        TextEditingController(text: config['copies']?.toString() ?? '1');
    _printableWidthDots = TextEditingController(
        text: config['printableWidthDots']?.toString() ?? '384');
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
    _printableWidthDots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.device != null;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 820),
        child: Material(
          color: const Color(0xFFF8FAF9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _typeColor(_type).withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_typeIcon(_type), color: _typeColor(_type)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              editing ? 'Aygıt ayarları' : 'Yeni cihaz ekle',
                              style: const TextStyle(
                                  fontSize: 21, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              editing
                                  ? '${_step + 1}/3 · ${_stepLabel(_step)} · ${deviceFriendlyIdentity(widget.device!)}'
                                  : '${_step + 1}/3 · ${_stepLabel(_step)}',
                              style: const TextStyle(
                                  fontSize: 12, color: kTextSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed:
                            _working ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: List.generate(3, (index) {
                      final selected = index == _step;
                      final completed = index < _step;
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFFE5F4EE)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? kGreen : kBorderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                completed
                                    ? Icons.check_circle_rounded
                                    : index == 0
                                        ? Icons.category_rounded
                                        : index == 1
                                            ? Icons.cable_rounded
                                            : Icons.tune_rounded,
                                size: 17,
                                color: selected || completed
                                    ? kGreen
                                    : kTextSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _stepLabel(index),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected
                                        ? kTextPrimary
                                        : kTextSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 22),
                  if (_step == 0) _typeStep(),
                  if (_step == 1) _connectionStep(),
                  if (_step == 2) _detailsStep(),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _InlineError(message: _error!),
                  ],
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (_step > (editing ? 1 : 0))
                        TextButton(
                          onPressed:
                              _working ? null : () => setState(() => _step--),
                          child: const Text('Geri'),
                        ),
                      if (_step == 2)
                        OutlinedButton.icon(
                          onPressed: _working ? null : _testDraft,
                          icon: const Icon(Icons.cable_rounded, size: 18),
                          label: const Text('Bağlantıyı kontrol et'),
                        ),
                      FilledButton(
                        onPressed: _working ? null : _continue,
                        child: _working
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_step < 2
                                ? 'Devam et'
                                : editing
                                    ? 'Ayarları kaydet'
                                    : 'Cihazı kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ne eklemek istiyorsunuz?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Aygıt türünü seçin; uygun bağlantıları biz göstereceğiz.',
            style: TextStyle(fontSize: 12, color: kTextSecondary)),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
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
                      _name.text = _typeLabel(type);
                      _port.text = _defaultPort(type).toString();
                    });
                  },
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _connectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_typeLabel(_type)} nasıl bağlı?',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Bilmiyorsanız en tanıdık seçeneği seçin.',
            style: TextStyle(fontSize: 12, color: kTextSecondary)),
        const SizedBox(height: 14),
        ..._connectionsFor(_type).map((connection) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SelectionCard(
                selected: connection == _connection,
                icon: _connectionIcon(connection),
                color: kGreen,
                title: _connectionLabel(connection),
                subtitle: _connectionDescription(connection),
                onTap: () => setState(() => _connection = connection),
              ),
            )),
      ],
    );
  }

  Widget _detailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_typeLabel(_type)} ayarları',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          '${_connectionLabel(_connection)} için gerekli alanları doldurun.',
          style: const TextStyle(fontSize: 12, color: kTextSecondary),
        ),
        const SizedBox(height: 16),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _dataBits,
                  decoration: const InputDecoration(labelText: 'Veri biti'),
                  items: const [7, 8]
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text('$value bit')))
                      .toList(),
                  onChanged: (value) => _dataBits = value ?? 8,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _stopBits,
                  decoration: const InputDecoration(labelText: 'Stop biti'),
                  items: const [1, 2]
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text('$value')))
                      .toList(),
                  onChanged: (value) => _stopBits = value ?? 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _parity,
                  decoration: const InputDecoration(labelText: 'Parite'),
                  items: const {
                    'none': 'Yok',
                    'even': 'Çift',
                    'odd': 'Tek',
                  }
                      .entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (value) => _parity = value ?? 'none',
                ),
              ),
            ],
          ),
        ],
        if (_type == HardwareDeviceType.scale) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _scaleUnit,
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
            label: Text(_discoveringWindows
                ? 'Windows yazıcıları okunuyor…'
                : 'Windows yazıcılarını bul'),
          ),
          if (_discoveredPrinters.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._discoveredPrinters
                .where((item) => item.kind == DiscoveredPrinterKind.windows)
                .map((printer) => RadioListTile<String>(
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
                      subtitle: Text(printer.isDefault
                          ? 'Varsayılan Windows yazıcısı'
                          : 'Windows yazıcı kuyruğu'),
                    )),
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
        if ((_type == HardwareDeviceType.receiptPrinter ||
                _type == HardwareDeviceType.labelPrinter) &&
            _connection == HardwareConnectionType.tcp) ...[
          OutlinedButton.icon(
            onPressed: _discoveringNetwork ? null : _discoverNetworkPrinters,
            icon: _discoveringNetwork
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar_rounded),
            label: Text(_discoveringNetwork
                ? 'Yerel ağ taranıyor…'
                : 'Aynı ağdaki yazıcıları bul'),
          ),
          if (_discoveredPrinters
              .any((item) => item.kind == DiscoveredPrinterKind.network)) ...[
            const SizedBox(height: 8),
            ..._discoveredPrinters
                .where((item) => item.kind == DiscoveredPrinterKind.network)
                .map((printer) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: printer.address ?? '',
                      groupValue: _host.text,
                      onChanged: (value) => setState(() {
                        _host.text = value ?? '';
                        _port.text = '${printer.port ?? 9100}';
                      }),
                      title: Text(printer.address ?? printer.name),
                      subtitle: const Text(
                        'Yazıcı adayı · Test çıktısıyla doğrulanacak',
                      ),
                    )),
          ],
          const SizedBox(height: 10),
        ],
        if (_connection == HardwareConnectionType.serial) ...[
          OutlinedButton.icon(
            onPressed: _discoverSerialPorts,
            icon: const Icon(Icons.usb_rounded),
            label: const Text('USB / COM aygıtlarını bul'),
          ),
          if (_serialPorts.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._serialPorts.map((port) => RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: port,
                  groupValue: _serialPort.text,
                  onChanged: (value) =>
                      setState(() => _serialPort.text = value ?? ''),
                  title: Text(port),
                  subtitle: const Text('Seri bağlantı noktası'),
                )),
            const SizedBox(height: 8),
          ],
        ],
        if ((_type == HardwareDeviceType.receiptPrinter ||
                _type == HardwareDeviceType.labelPrinter) &&
            _connection == HardwareConnectionType.bluetooth) ...[
          OutlinedButton.icon(
            onPressed: _discoveringBluetooth ? null : _discoverBluetooth,
            icon: _discoveringBluetooth
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching_rounded),
            label: Text(_discoveringBluetooth
                ? 'Yakındaki cihazlar aranıyor…'
                : 'Bluetooth cihazlarını tara'),
          ),
          if (_bluetoothDevices.isNotEmpty) ...[
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
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Seçilen Bluetooth yazıcı',
              helperText: 'Bağlantıda cihazın MAC adresi kullanılır.',
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
          const SizedBox(height: 8),
          const Text(
            'POS cihazı doğrudan bağlanmaz; seçilen banka/üretici SDK’sını kullanan Serenut POS Bridge bu IP ve portta çalışmalıdır.',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
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
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Fiş Sonunda Otomatik Kes'),
            value: _autoCut,
            onChanged: (val) => setState(() => _autoCut = val),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Kasa Çekmecesini Aç'),
            value: _openDrawer,
            onChanged: (val) => setState(() => _openDrawer = val),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _labelCopies,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Yazdırılacak kopya sayısı',
            ),
          ),
        ],
        if (_type == HardwareDeviceType.labelPrinter) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _labelLanguage,
            decoration: const InputDecoration(labelText: 'Yazıcı dili'),
            items: const [
              DropdownMenuItem(
                value: 'tspl',
                child: Text('TSPL / TSC uyumlu (önerilen)'),
              ),
              DropdownMenuItem(
                value: 'escpos',
                child: Text('ESC/POS (eski uyumluluk)'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _labelLanguage = value ?? 'tspl'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _labelWidth,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Etiket eni (mm)',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _labelHeight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Etiket boyu (mm)',
                  ),
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
          if (_labelLanguage == 'tspl') ...[
            const SizedBox(height: 4),
            SwitchListTile(
              title: const Text('Gap boşluğunu otomatik algıla'),
              subtitle: const Text(
                'Gaplı etiket kullanıldığında yazıcı sensörü etiket aralığını kalibre eder.',
              ),
              value: _autoDetectLabelGap,
              onChanged: (value) => setState(() => _autoDetectLabelGap = value),
              contentPadding: EdgeInsets.zero,
            ),
          ],
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
          TextField(
            controller: _printableWidthDots,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Basılabilir genişlik (nokta)',
              helperText: '58 mm / 203 DPI cihazlarda genellikle 384 noktadır.',
            ),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor: kGreen,
      ));
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
          ..._discoveredPrinters
              .where((item) => item.kind != DiscoveredPrinterKind.windows),
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
        found.addAll(await discovery.scanSubnet(subnet));
      }
      if (!mounted) return;
      setState(() {
        _discoveredPrinters = [
          ..._discoveredPrinters
              .where((item) => item.kind != DiscoveredPrinterKind.network),
          ...found,
        ];
        if (found.isEmpty) {
          _error = 'Aynı ağda RAW 9100 yazıcı adayı bulunamadı. '
              'Yazıcı farklı VLAN üzerindeyse IP adresini manuel girin.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Ağ taraması tamamlanamadı: $error');
    } finally {
      if (mounted) setState(() => _discoveringNetwork = false);
    }
  }

  void _discoverSerialPorts() {
    try {
      final ports = SerialScaleAdapter.availablePorts;
      setState(() {
        _serialPorts = ports;
        _error = ports.isEmpty
            ? 'USB / COM aygıtı bulunamadı. Sürücünün kurulu olduğunu kontrol edin.'
            : null;
        if (_serialPort.text.isEmpty && ports.isNotEmpty) {
          _serialPort.text = ports.first;
        }
      });
    } catch (error) {
      setState(() => _error = 'Seri portlar okunamadı: $error');
    }
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Cihaz adı gereklidir.';
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
    if (_type == HardwareDeviceType.labelPrinter) {
      final width = int.tryParse(_labelWidth.text);
      final height = int.tryParse(_labelHeight.text);
      final gap = int.tryParse(_labelGap.text);
      final copies = int.tryParse(_labelCopies.text);
      final printableDots = int.tryParse(_printableWidthDots.text);
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
      if (printableDots == null ||
          printableDots < 200 ||
          printableDots > 1200) {
        return 'Basılabilir genişlik 200-1200 nokta arasında olmalıdır.';
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
        'printableWidthDots': int.tryParse(_printableWidthDots.text) ?? 384,
        'printDirection': _printDirection,
        'copies': int.tryParse(_labelCopies.text) ?? 1,
        'autoCut': _autoCut,
        'openDrawer': _openDrawer,
      },
    );
  }
}

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
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: kTextPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11, height: 1.3, color: kTextSecondary)),
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

class _TestResultDialog extends StatefulWidget {
  final HardwareTestResult result;

  const _TestResultDialog({required this.result});

  @override
  State<_TestResultDialog> createState() => _TestResultDialogState();
}

class _TestResultDialogState extends State<_TestResultDialog> {
  bool _confirmationEnabled = false;

  HardwareTestResult get result => widget.result;

  @override
  void initState() {
    super.initState();
    if (result.requiresPhysicalConfirmation) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _confirmationEnabled = true);
      });
    } else {
      _confirmationEnabled = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        result.requiresPhysicalConfirmation
            ? Icons.fact_check_rounded
            : result.success
                ? Icons.check_circle_rounded
                : Icons.error_rounded,
        color: result.requiresPhysicalConfirmation
            ? kOrange
            : result.success
                ? kGreen
                : kPink,
        size: 48,
      ),
      title: Text(result.requiresPhysicalConfirmation
          ? 'Çıktıyı kontrol edin'
          : result.success
              ? 'Bağlantı hazır'
              : 'Bağlantı kurulamadı'),
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
        if (result.requiresPhysicalConfirmation) ...[
          TextButton(
            onPressed: _confirmationEnabled
                ? () => Navigator.pop(context, false)
                : null,
            child: const Text('Hayır, hatalı'),
          ),
          FilledButton(
            onPressed: _confirmationEnabled
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('Evet, doğru'),
          ),
        ] else
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
            'Yazıcı, terazi veya POS bağlantınızı ekleyin. USB barkod okuyucular ve kamera ayrıca ayar gerektirmez.',
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
    HardwareDeviceStatus.ready => ('Test başarılı', kGreen),
    HardwareDeviceStatus.offline => ('Son kontrolde çevrimdışı', kOrange),
    HardwareDeviceStatus.error => ('Hata', kPink),
    HardwareDeviceStatus.disabled => ('Pasif', kTextSecondary),
  };
}

String deviceFriendlyIdentity(HardwareDevice device) =>
    '${_typeLabel(device.type)} · ${_connectionLabel(device.connectionType)}';

String _typeDescription(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter =>
        'Fiş, mutfak çıktısı ve kasa çekmecesi',
      HardwareDeviceType.labelPrinter => 'Ürün, raf ve sipariş etiketi',
      HardwareDeviceType.scale => 'Canlı ağırlık bilgisini satışa aktarır',
      HardwareDeviceType.paymentTerminal =>
        'Banka veya ödeme terminali bağlantısı',
      HardwareDeviceType.barcodeScanner =>
        'USB, dahili kamera veya el terminali',
    };

IconData _connectionIcon(HardwareConnectionType connection) =>
    switch (connection) {
      HardwareConnectionType.embedded => Icons.smartphone_rounded,
      HardwareConnectionType.windows => Icons.desktop_windows_rounded,
      HardwareConnectionType.bluetooth => Icons.bluetooth_rounded,
      HardwareConnectionType.serial => Icons.usb_rounded,
      HardwareConnectionType.tcp => Icons.lan_rounded,
      HardwareConnectionType.keyboard => Icons.keyboard_rounded,
      HardwareConnectionType.cloud => Icons.cloud_queue_rounded,
    };

String _connectionDescription(HardwareConnectionType connection) =>
    switch (connection) {
      HardwareConnectionType.embedded =>
        'Sunmi gibi cihazın kendi üzerindeki donanım',
      HardwareConnectionType.windows =>
        'Windows’a kurulmuş veya USB ile bağlı yazıcı',
      HardwareConnectionType.bluetooth => 'Kablosuz eşleştirilen yakın aygıt',
      HardwareConnectionType.serial =>
        'USB dönüştürücü veya COM portu kullanan aygıt',
      HardwareConnectionType.tcp => 'Aynı ağdaki Ethernet veya Wi-Fi aygıtı',
      HardwareConnectionType.keyboard =>
        'Okutunca klavye gibi veri gönderen USB aygıt',
      HardwareConnectionType.cloud =>
        'Başka bir açık cihaz tarafından paylaşılan aygıt',
    };

String _typeLabel(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter => 'Fiş yazıcısı',
      HardwareDeviceType.labelPrinter => 'Etiket yazıcısı',
      HardwareDeviceType.scale => 'Terazi',
      HardwareDeviceType.paymentTerminal => 'Fiziksel POS',
      HardwareDeviceType.barcodeScanner => 'Barkod okuyucu',
    };

String _deviceConfigurationSummary(HardwareDevice device) {
  final config = device.configuration;
  int value(String key, int fallback) =>
      int.tryParse(config[key]?.toString() ?? '') ?? fallback;
  return switch (device.type) {
    HardwareDeviceType.receiptPrinter =>
      '${value('paperWidth', 58)} mm fiş · ${config['autoCut'] == true ? 'otomatik kesim' : 'kesimsiz'}',
    HardwareDeviceType.labelPrinter =>
      '${value('labelWidthMm', 50)}×${value('labelHeightMm', 30)} mm · ${value('dpi', 203)} DPI · ${(config['language'] ?? 'tspl').toString().toUpperCase()}',
    HardwareDeviceType.scale =>
      '${value('baudRate', 9600)} baud · ${(config['defaultUnit'] ?? 'kg').toString()}',
    HardwareDeviceType.paymentTerminal =>
      '${(config['vendor'] ?? 'generic').toString()} · ${(config['protocol'] ?? 'vendor_sdk').toString().toUpperCase()}',
    HardwareDeviceType.barcodeScanner => 'Okutma ile doğrulama',
  };
}

String _activeRouteLabel(List<String> activeFor) {
  final labels = activeFor.map((kind) => switch (kind) {
        'receipt' => 'Fiş',
        'productLabel' => 'Ürün etiketi',
        'orderLabel' => 'Sipariş etiketi',
        _ => kind,
      });
  return 'Aktif rota: ${labels.join(', ')}';
}

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
      HardwareConnectionType.cloud => 'Ortak / Uzak',
    };

List<HardwareConnectionType> _connectionsFor(HardwareDeviceType type) {
  final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  return switch (type) {
    HardwareDeviceType.receiptPrinter => isWindows
        ? const [HardwareConnectionType.windows, HardwareConnectionType.tcp]
        : isAndroid
            ? const [
                HardwareConnectionType.embedded,
                HardwareConnectionType.bluetooth,
                HardwareConnectionType.tcp,
              ]
            : const [HardwareConnectionType.tcp],
    HardwareDeviceType.labelPrinter => isWindows
        ? const [HardwareConnectionType.windows, HardwareConnectionType.tcp]
        : isAndroid
            ? const [
                HardwareConnectionType.bluetooth,
                HardwareConnectionType.tcp,
              ]
            : const [HardwareConnectionType.tcp],
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

const _managedDeviceTypes = <HardwareDeviceType>[
  HardwareDeviceType.receiptPrinter,
  HardwareDeviceType.labelPrinter,
  HardwareDeviceType.scale,
  HardwareDeviceType.paymentTerminal,
];

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
