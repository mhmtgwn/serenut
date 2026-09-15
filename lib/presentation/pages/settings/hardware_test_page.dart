import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          onAddCloud: () => _openSharedPrinters(context, ref),
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
    final kind = device.type == HardwareDeviceType.labelPrinter
        ? PrintDocumentKind.productLabel
        : null;
    final result = await ref
        .read(hardwareDevicesProvider.notifier)
        .test(device, printKind: kind);
    if (!context.mounted) return;

    if (result.requiresPhysicalConfirmation && result.success) {
      await ref
          .read(hardwareDevicesProvider.notifier)
          .confirmPhysicalPrintTest(result, passed: true);
    }
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(
              result.success
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.success
                    ? '${device.name} bağlantısı başarılı (${result.elapsed.inMilliseconds} ms).'
                    : 'Test başarısız: ${result.message}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: result.success ? kGreen : kPink,
      ),
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

enum _DeviceFilter { all, localDevices, cloudPrinters, printers, salesHardware }

class _DeviceList extends StatefulWidget {
  final List<HardwareDevice> devices;
  final VoidCallback onAdd;
  final VoidCallback onAddCloud;
  final ValueChanged<HardwareDevice> onEdit;
  final ValueChanged<HardwareDevice> onActivate;
  final ValueChanged<HardwareDevice> onTest;
  final ValueChanged<HardwareDevice> onDelete;

  const _DeviceList({
    required this.devices,
    required this.onAdd,
    required this.onAddCloud,
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

    final localDevices = devices
        .where((d) => d.connectionType != HardwareConnectionType.cloud)
        .toList(growable: false);
    final cloudDevices = devices
        .where((d) => d.connectionType == HardwareConnectionType.cloud)
        .toList(growable: false);
    final allPrinters = devices
        .where(
          (d) =>
              d.type == HardwareDeviceType.receiptPrinter ||
              d.type == HardwareDeviceType.labelPrinter,
        )
        .toList(growable: false);
    final salesHardware = devices
        .where(
          (d) =>
              d.type != HardwareDeviceType.receiptPrinter &&
              d.type != HardwareDeviceType.labelPrinter,
        )
        .toList(growable: false);

    final visible = switch (_filter) {
      _DeviceFilter.all => devices,
      _DeviceFilter.localDevices => localDevices,
      _DeviceFilter.cloudPrinters => cloudDevices,
      _DeviceFilter.printers => allPrinters,
      _DeviceFilter.salesHardware => salesHardware,
    };

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 760 ? 2 : 1;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardExtent = 84.0 + (textScale - 1).clamp(0.0, 1.0) * 24;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HardwareHero(
            total: devices.length,
            ready: ready,
            attention: attention,
            onAdd: widget.onAdd,
            onAddCloud: widget.onAddCloud,
          ),
        ),
        if (devices.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
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
                      avatar: const Icon(Icons.print_rounded, size: 16),
                      label: Text('Yazıcılar (${allPrinters.length})'),
                      selected: _filter == _DeviceFilter.printers,
                      onSelected: (_) =>
                          setState(() => _filter = _DeviceFilter.printers),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.point_of_sale_rounded, size: 16),
                      label: Text('Satış donanımı (${salesHardware.length})'),
                      selected: _filter == _DeviceFilter.salesHardware,
                      onSelected: (_) =>
                          setState(() => _filter = _DeviceFilter.salesHardware),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.computer_rounded, size: 16),
                      label: Text('Cihaz donanımı (${localDevices.length})'),
                      selected: _filter == _DeviceFilter.localDevices,
                      onSelected: (_) =>
                          setState(() => _filter = _DeviceFilter.localDevices),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.cloud_done_rounded, size: 16),
                      label: Text('Bulut yazıcılar (${cloudDevices.length})'),
                      selected: _filter == _DeviceFilter.cloudPrinters,
                      onSelected: (_) =>
                          setState(() => _filter = _DeviceFilter.cloudPrinters),
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
        else if (_filter == _DeviceFilter.all) ...[
          // Bölüm 1: Yerel Cihaz Donanımları
          if (localDevices.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.devices_rounded,
                title: 'Bu Cihaza Bağlı Donanımlar',
                count: localDevices.length,
                subtitle:
                    'Terminale doğrudan (USB, COM, Dahili, Windows) veya yerel ağla bağlı aygıtlar',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: 10, bottom: 20),
              sliver: _buildDevicesLayout(localDevices, columns, cardExtent),
            ),
          ],
          // Bölüm 2: Bulut & Ortak Ağ Yazıcıları
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: Icons.cloud_done_rounded,
              title: 'Bulut ve Ortak Yazıcılar',
              count: cloudDevices.length,
              subtitle:
                  'Aynı işletmedeki diğer açık terminaller tarafından paylaşılan yazıcılar',
              action: TextButton.icon(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: widget.onAddCloud,
                icon: const Icon(Icons.add_link_rounded, size: 16),
                label: const Text('Ortak Yazıcı Bağla'),
              ),
            ),
          ),
          if (cloudDevices.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(top: 10, bottom: 24),
              sliver: _buildDevicesLayout(cloudDevices, columns, cardExtent),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 28),
                child: _EmptyCloudNotice(onConnect: widget.onAddCloud),
              ),
            ),
        ] else if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Bu grupta kayıtlı cihaz yok.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 16, bottom: 24),
            sliver: _buildDevicesLayout(visible, columns, cardExtent),
          ),
      ],
    );
  }

  Widget _buildDevicesLayout(
    List<HardwareDevice> items,
    int columns,
    double cardExtent,
  ) {
    if (columns <= 1) {
      return SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final device = items[index];
          return _DeviceCard(
            device: device,
            onEdit: () => widget.onEdit(device),
            onActivate: () => widget.onActivate(device),
            onTest: () => widget.onTest(device),
            onDelete: () => widget.onDelete(device),
          );
        },
      );
    }
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: cardExtent,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final device = items[index];
          return _DeviceCard(
            device: device,
            onEdit: () => widget.onEdit(device),
            onActivate: () => widget.onActivate(device),
            onTest: () => widget.onTest(device),
            onDelete: () => widget.onDelete(device),
          );
        },
        childCount: items.length,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final String subtitle;
  final Widget? action;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 450;
    final headerContent = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: kGreen.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: kGreen),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kTextPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: kBorderColor.withValues(alpha: .6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: kTextSecondary),
              ),
            ],
          ),
        ),
        if (action != null && !isCompact) action!,
      ],
    );

    if (action != null && isCompact) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headerContent,
            Align(alignment: Alignment.centerRight, child: action!),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: headerContent,
    );
  }
}

class _EmptyCloudNotice extends StatelessWidget {
  final VoidCallback onConnect;

  const _EmptyCloudNotice({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kTeal.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_outlined, color: kTeal, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bağlı bulut yazıcı yok',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Aynı işletmedeki diğer terminal veya bilgisayarların paylaştığı ortak yazıcıları kullanabilirsiniz.',
                  style: TextStyle(fontSize: 11, color: kTextSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onConnect,
            icon: const Icon(Icons.cloud_sync_rounded, size: 16),
            label:
                const Text('Ortak Yazıcı Bul', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _HardwareHero extends StatelessWidget {
  final int total;
  final int ready;
  final int attention;
  final VoidCallback onAdd;
  final VoidCallback onAddCloud;

  const _HardwareHero({
    required this.total,
    required this.ready,
    required this.attention,
    required this.onAdd,
    required this.onAddCloud,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final header = Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kGreen.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.devices_other_rounded,
                    color: kGreen, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aygıt & Donanım Merkezi',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Yerel donanım bağlantıları ve işletme bulut yazıcıları',
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

          final metrics = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompactDeviceMetric(value: '$total', label: 'Toplam'),
              const SizedBox(width: 8),
              _CompactDeviceMetric(
                value: '$ready',
                label: 'Hazır',
                positive: true,
              ),
              if (attention > 0) ...[
                const SizedBox(width: 8),
                _CompactDeviceMetric(
                  value: '$attention',
                  label: 'Sorun',
                  alert: true,
                ),
              ],
            ],
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: kBorderColor),
                ),
                onPressed: onAddCloud,
                icon: const Icon(Icons.cloud_sync_rounded,
                    size: 17, color: kTeal),
                label: const Text('Ortak Yazıcı',
                    style: TextStyle(fontSize: 12, color: kTextPrimary)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Aygıt ekle',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
                      message: 'Ortak yazıcılar',
                      child: IconButton.outlined(
                        onPressed: onAddCloud,
                        icon: const Icon(Icons.cloud_sync_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Hızlı ekle',
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
              const SizedBox(width: 16),
              metrics,
              const SizedBox(width: 14),
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
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .15)),
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
            style: const TextStyle(
                fontSize: 10,
                color: kTextSecondary,
                fontWeight: FontWeight.w600),
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
    final isCloud = device.connectionType == HardwareConnectionType.cloud;
    final typeColor = _typeColor(device.type);
    final hasError = device.lastError != null ||
        device.status == HardwareDeviceStatus.error ||
        device.status == HardwareDeviceStatus.offline;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? kGreen.withValues(alpha: .5) : kBorderColor,
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Sol: Cihaz İkonu & Aktiflik Rozeti
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: typeColor.withValues(alpha: .2),
                        ),
                      ),
                      child: Icon(_typeIcon(device.type),
                          color: typeColor, size: 21),
                    ),
                    if (isActive)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: kGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // 2. Orta: Cihaz Adı, Rol Rozeti ve Bağlantı Meta Bilgisi
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: kTextPrimary,
                              ),
                            ),
                          ),
                          if (isCloud) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: kTeal.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Bulut',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: kTeal,
                                ),
                              ),
                            ),
                          ],
                          if (isPrinter && activeFor.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: kGreen.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                activeFor
                                    .map((k) => switch (k) {
                                          'receipt' => 'Fiş',
                                          'productLabel' => 'Etiket',
                                          'orderLabel' => 'Sipariş',
                                          _ => k,
                                        })
                                    .join(' + '),
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: kGreen,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _deviceSubtitle(device),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: kTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (hasError) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 12, color: kPink),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                device.lastError ??
                                    device.lastMessage ??
                                    'Aygıt çevrimdışı veya yanıt vermiyor',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: kPink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // 3. Sağ: Durum Rozeti + Kompakt Test İkonu + Menü
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DeviceStatusPill(
                      label: status.$1,
                      color: status.$2,
                      isActive: isActive,
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Bağlantıyı test et',
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton.filledTonal(
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed:
                              device.status == HardwareDeviceStatus.testing
                                  ? null
                                  : onTest,
                          icon: device.status == HardwareDeviceStatus.testing
                              ? const SizedBox.square(
                                  dimension: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.play_arrow_rounded,
                                  size: 16),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded,
                          size: 18, color: kTextSecondary),
                      padding: EdgeInsets.zero,
                      tooltip: 'İşlemler',
                      onSelected: (value) {
                        if (value == 'test') onTest();
                        if (value == 'edit') onEdit();
                        if (value == 'activate') onActivate();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.tune_rounded, size: 18),
                            title: Text('Ayarlar & Düzenle'),
                          ),
                        ),
                        if (!isActive)
                          const PopupMenuItem(
                            value: 'activate',
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 18),
                              title: Text('Aktif cihaz yap'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.delete_outline_rounded,
                                color: kPink, size: 18),
                            title: Text('Kaldır',
                                style: TextStyle(color: kPink)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _deviceSubtitle(HardwareDevice device) {
  final parts = <String>[];
  final config = device.configuration;
  parts.add(_typeLabel(device.type));
  if (device.connectionType == HardwareConnectionType.tcp &&
      config['host'] != null) {
    parts.add('${config['host']}:${config['port'] ?? 9100}');
  } else if (device.connectionType == HardwareConnectionType.serial &&
      config['serialPort'] != null) {
    parts.add('${config['serialPort']}');
  } else if (device.connectionType == HardwareConnectionType.windows &&
      config['printerName'] != null) {
    parts.add('${config['printerName']}');
  } else if (device.connectionType == HardwareConnectionType.bluetooth &&
      config['printerName'] != null) {
    parts.add('${config['printerName']}');
  } else {
    parts.add(_connectionLabel(device.connectionType));
  }
  if (device.type == HardwareDeviceType.receiptPrinter) {
    final w = config['paperWidth'] ?? 58;
    parts.add('$w mm');
  } else if (device.type == HardwareDeviceType.labelPrinter) {
    final w = config['labelWidthMm'] ?? 50;
    final h = config['labelHeightMm'] ?? 30;
    parts.add('$w×$h mm');
  }
  return parts.join(' · ');
}

class _DeviceStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;

  const _DeviceStatusPill({
    required this.label,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
