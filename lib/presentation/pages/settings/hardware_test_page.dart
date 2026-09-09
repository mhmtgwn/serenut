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
import 'dart:math' as math;


part 'widgets/device_editor_sheet.dart';

class HardwareTestPage extends ConsumerWidget {
  const HardwareTestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(hardwareDevicesProvider);
    return FullScreenSettingsPage(
      title: 'Aygıtlar',
      useScrollView: false,
      actions: [
        _DeviceManagerToolbar(
          onRefresh: () => _refreshDevices(context, ref),
          onSharedPrinters: () => _openSharedPrinters(context, ref),
        ),
        IconButton(
          tooltip: 'Aygıt ekle',
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

  Future<void> _openSharedPrinters(BuildContext context, WidgetRef ref) async {
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
                      .where(
                        (item) =>
                            !item.isLocal &&
                            (item.type == HardwareDeviceType.receiptPrinter ||
                                item.type == HardwareDeviceType.labelPrinter),
                      )
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
                        subtitle: Text(
                          printer.online
                              ? 'Çevrimiçi · ${printer.connectionType}'
                              : 'Sahip cihaz çevrimdışı',
                        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selected.name} varsayılan ortak yazıcı oldu.'),
          backgroundColor: kGreen,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: kPink),
      );
    }
  }

  Future<void> _refreshDevices(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(hardwareDevicesProvider.notifier).refreshConnections();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cihaz bağlantıları yenilendi.'),
          backgroundColor: kGreen,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bağlantılar yenilenemedi: $error'),
          backgroundColor: kPink,
        ),
      );
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    HardwareDevice? device,
  }) async {
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final bool? saved;
    if (desktop) {
      saved = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .42),
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 820,
              maxHeight: 860,
            ),
            child: _DeviceEditor(device: device, desktopDialog: true),
          ),
        ),
      );
    } else {
      saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _DeviceEditor(device: device),
      );
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            physicalResult
                ? 'Yazıcı fiziksel olarak doğrulandı.'
                : 'Test reddedildi; cihaz kontrol edilmeli.',
          ),
          backgroundColor: physicalResult ? kGreen : kPink,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${device.name} kaldırıldı.'),
          backgroundColor: kGreen,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cihaz kaldırılamadı: $error'),
          backgroundColor: kPink,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${device.name} aktif cihaz oldu.'),
          backgroundColor: kGreen,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cihaz aktifleştirilemedi: $error'),
          backgroundColor: kPink,
        ),
      );
    }
  }
}

enum _DeviceManagerAction { refresh, sharedPrinters }

class _DeviceManagerToolbar extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onSharedPrinters;

  const _DeviceManagerToolbar({
    required this.onRefresh,
    required this.onSharedPrinters,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Bağlantıları yenile',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Ortak yazıcılar',
            onPressed: onSharedPrinters,
            icon: const Icon(Icons.cloud_queue_rounded),
          ),
        ],
      );
    }
    return PopupMenuButton<_DeviceManagerAction>(
      tooltip: 'Yönetici işlemleri',
      onSelected: (action) {
        switch (action) {
          case _DeviceManagerAction.refresh:
            onRefresh();
          case _DeviceManagerAction.sharedPrinters:
            onSharedPrinters();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _DeviceManagerAction.refresh,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh_rounded),
            title: Text('Bağlantıları yenile'),
          ),
        ),
        PopupMenuItem(
          value: _DeviceManagerAction.sharedPrinters,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_queue_rounded),
            title: Text('Ortak yazıcılar'),
          ),
        ),
      ],
    );
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
        .where(
          (device) =>
              device.status == HardwareDeviceStatus.error ||
              device.status == HardwareDeviceStatus.offline,
        )
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
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Tümü (${devices.length})'),
                      selected: _filter == _DeviceFilter.all,
                      onSelected: (_) =>
                          setState(() => _filter = _DeviceFilter.all),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                        'Yazıcılar (${devices.where((device) => device.type == HardwareDeviceType.receiptPrinter || device.type == HardwareDeviceType.labelPrinter).length})',
                      ),
                      selected: _filter == _DeviceFilter.printers,
                      onSelected: (_) =>
                          setState(() => _filter = _DeviceFilter.printers),
                    ),
                    const SizedBox(width: 8),
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
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final cardExtent = 308.0 + (textScale - 1).clamp(0.0, 1.0) * 96;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: cardExtent,
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final header = Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kGreen.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.devices_other_rounded, color: kGreen),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bağlı aygıtlar',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Yazıcı, terazi, barkod okuyucu ve POS bağlantıları',
                      style: TextStyle(
                        color: kTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _CompactDeviceMetric(value: '$total', label: 'Toplam'),
              _CompactDeviceMetric(
                value: '$ready',
                label: 'Hazır',
                positive: true,
              ),
              if (attention > 0)
                _CompactDeviceMetric(
                  value: '$attention',
                  label: 'Sorun',
                  alert: true,
                ),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Aygıt ekle'),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$total toplam · $ready hazır${attention > 0 ? ' · $attention sorun' : ''}',
                        style: TextStyle(
                          color: attention > 0 ? kPink : kTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Cihaz ekle',
                      child: IconButton.filled(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 18),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _CompactDeviceMetric extends StatelessWidget {
  const _CompactDeviceMetric({
    required this.value,
    required this.label,
    this.alert = false,
    this.positive = false,
  });

  final String value;
  final String label;
  final bool alert;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = alert ? kPink : (positive ? kGreen : kTextPrimary);
    return Container(
      constraints: const BoxConstraints(minWidth: 62),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: kTextSecondary),
          ),
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
                    child: Icon(
                      _typeIcon(device.type),
                      color: _typeColor(device.type),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _StatusBadge(label: status.$1, color: status.$2),
                    ),
                  ),
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
                          value: 'activate',
                          child: Text('Aktif cihaz yap'),
                        ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Düzenle'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Kaldır'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isActive)
                    const _StatusBadge(label: 'Aktif', color: kGreen),
                  _StatusBadge(label: status.$1, color: status.$2),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary,
                ),
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
                  label: Text(
                    device.status == HardwareDeviceStatus.testing
                        ? 'Bağlantı kontrol ediliyor'
                        : 'Bağlantıyı test et',
                  ),
                ),
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
      title: Text(
        result.requiresPhysicalConfirmation
            ? 'Çıktıyı kontrol edin'
            : result.success
                ? 'Bağlantı hazır'
                : 'Bağlantı kurulamadı',
      ),
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
          const Icon(
            Icons.devices_other_rounded,
            size: 64,
            color: kTextSecondary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Henüz cihaz eklenmedi',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
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
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSecondary),
          ),
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

String _networkDeviceLabel(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter ||
      HardwareDeviceType.labelPrinter =>
        'yazıcıları',
      HardwareDeviceType.scale => 'terazileri',
      HardwareDeviceType.paymentTerminal => 'POS Bridge’leri',
      HardwareDeviceType.barcodeScanner => 'okuyucuları',
    };

String _networkCandidateLabel(HardwareDeviceType type) => switch (type) {
      HardwareDeviceType.receiptPrinter ||
      HardwareDeviceType.labelPrinter =>
        'Yazıcı adayı',
      HardwareDeviceType.scale => 'Terazi adayı',
      HardwareDeviceType.paymentTerminal => 'POS Bridge adayı',
      HardwareDeviceType.barcodeScanner => 'Okuyucu adayı',
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
  final labels = activeFor.map(
    (kind) => switch (kind) {
      'receipt' => 'Fiş',
      'productLabel' => 'Ürün etiketi',
      'orderLabel' => 'Sipariş etiketi',
      _ => kind,
    },
  );
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
        ? const [
            HardwareConnectionType.windows,
            HardwareConnectionType.bluetooth,
            HardwareConnectionType.tcp,
            HardwareConnectionType.cloud,
          ]
        : isAndroid
            ? const [
                HardwareConnectionType.embedded,
                HardwareConnectionType.bluetooth,
                HardwareConnectionType.tcp,
                HardwareConnectionType.cloud,
              ]
            : const [HardwareConnectionType.tcp, HardwareConnectionType.cloud],
    HardwareDeviceType.labelPrinter => isWindows
        ? const [
            HardwareConnectionType.windows,
            HardwareConnectionType.bluetooth,
            HardwareConnectionType.tcp,
            HardwareConnectionType.cloud,
          ]
        : isAndroid
            ? const [
                HardwareConnectionType.bluetooth,
                HardwareConnectionType.tcp,
                HardwareConnectionType.cloud,
              ]
            : const [HardwareConnectionType.tcp, HardwareConnectionType.cloud],
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
