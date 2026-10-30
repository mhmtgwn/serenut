// lib/presentation/pages/warehouse_details_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/presentation/widgets/hazelnut/warehouse_dialogs.dart';
import 'package:serenutos/presentation/widgets/hazelnut/warehouse_escrows_tab_view.dart';
import 'package:serenutos/providers/hazelnut_providers.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class WarehouseDetailsPage extends ConsumerStatefulWidget {
  final String warehouseId;
  const WarehouseDetailsPage({super.key, required this.warehouseId});

  @override
  ConsumerState<WarehouseDetailsPage> createState() => _WarehouseDetailsPageState();
}

class _WarehouseDetailsPageState extends ConsumerState<WarehouseDetailsPage>
    with SingleTickerProviderStateMixin {
  static final NumberFormat _numFormat = NumberFormat.decimalPattern('tr_TR');
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  late TabController _tabController;
  final TextEditingController _movementSearchCtrl = TextEditingController();

  String _movementFilter = 'ALL'; // ALL, IN, OUT, TRANSFER
  String _movementSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _movementSearchCtrl.addListener(() {
      setState(() {
        _movementSearchQuery = _movementSearchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _movementSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final whAsync = ref.watch(warehouseDetailProvider(widget.warehouseId));
    final movementsAsync = ref.watch(warehouseMovementsProvider(widget.warehouseId));
    final escrowsAsync = ref.watch(warehouseEscrowsProvider(widget.warehouseId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          whAsync.valueOrNull?.name ?? 'Depo Detayı',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (whAsync.valueOrNull != null) ...[
            IconButton(
              tooltip: 'Yenile',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(warehouseDetailProvider(widget.warehouseId));
                ref.invalidate(warehouseMovementsProvider(widget.warehouseId));
                ref.invalidate(warehouseEscrowsProvider(widget.warehouseId));
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Depo İşlemleri',
              onSelected: (val) {
                final wh = whAsync.valueOrNull!;
                switch (val) {
                  case 'edit':
                    WarehouseDialogs.showEditWarehouseDialog(context, ref, wh);
                    break;
                  case 'transfer':
                    WarehouseDialogs.showTransferDialog(context, ref, wh);
                    break;
                  case 'dispatch':
                    WarehouseDialogs.showDispatchDialog(context, ref, wh);
                    break;
                  case 'delete':
                    WarehouseDialogs.showDeleteWarehouseDialog(
                      context,
                      ref,
                      wh,
                      onDeleted: () {
                        if (mounted) Navigator.pop(context);
                      },
                    );
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.edit_outlined, size: 20),
                    title: Text('Depo Bilgilerini Düzenle'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'transfer',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.swap_horiz_rounded, size: 20, color: Colors.blue),
                    title: Text('Depolar Arası Transfer'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'dispatch',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.arrow_upward_rounded, size: 20, color: _kRed),
                    title: Text('Depodan Mal Çıkışı'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_outline_rounded, size: 20, color: _kRed),
                    title: Text('Depoyu Sil / Arşive Al', style: TextStyle(color: _kRed)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: whAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Hata: $err', style: const TextStyle(color: _kRed))),
        data: (wh) {
          if (wh == null) {
            return const Center(child: Text('Depo bulunamadı veya silinmiş.'));
          }

          final escrows = escrowsAsync.valueOrNull ?? [];
          final escrowKgSum = escrows.fold<double>(0.0, (acc, e) => acc + e.remainingKg);
          final ownedStockKg = (wh.currentStockKg - escrowKgSum).clamp(0.0, double.infinity);
          final occupancyRatio = wh.capacityKg > 0 ? (wh.currentStockKg / wh.capacityKg).clamp(0.0, 1.0) : 0.0;

          return Column(
            children: [
              // ── Depo Özet & İşlem Kartı ────────────────────────────────
              _buildWarehouseSummaryCard(context, wh, escrowKgSum, ownedStockKg, occupancyRatio),

              // ── Tab Bar ───────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: _kGreenDark,
                  labelColor: _kGreenDark,
                  unselectedLabelColor: _kTextSecondary,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long_rounded, size: 18),
                          const SizedBox(width: 8),
                          const Text('Depo Ekstresi (Hareketler)'),
                          if (movementsAsync.valueOrNull != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: POSColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${movementsAsync.valueOrNull!.length}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.handshake_rounded, size: 18),
                          const SizedBox(width: 8),
                          const Text('Depodaki Emanetler'),
                          if (escrows.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: POSColors.amberLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${escrows.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: POSColors.amberDark,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Tab İçerikleri ────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMovementsTab(movementsAsync),
                    WarehouseEscrowsTabView(
                      escrowsAsync: escrowsAsync,
                      escrowKgSum: escrowKgSum,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ── Üst Depo Bilgi & Aksiyon Kartı ─────────────────────────────────────────
  Widget _buildWarehouseSummaryCard(
    BuildContext context,
    WarehouseEntity wh,
    double escrowKgSum,
    double ownedStockKg,
    double occupancyRatio,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kGreenLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warehouse_rounded, color: _kGreenDark, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            wh.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kText),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: wh.isActive ? _kGreenLight : _kRedLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            wh.isActive ? 'Aktif' : 'Pasif',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: wh.isActive ? _kGreenDark : _kRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (wh.location != null && wh.location!.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: _kTextSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              wh.location!,
                              style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Düzenle'),
                    onPressed: () => WarehouseDialogs.showEditWarehouseDialog(context, ref, wh),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Transfer'),
                    onPressed: () => WarehouseDialogs.showTransferDialog(context, ref, wh),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                    label: const Text('Mal Çıkışı'),
                    onPressed: () => WarehouseDialogs.showDispatchDialog(context, ref, wh),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('Toplam Fiziksel Stok', '${_numFormat.format(wh.currentStockKg)} kg', _kGreenDark),
              _buildStat('Emanet Fındık', '${_numFormat.format(escrowKgSum)} kg', POSColors.amberDark),
              _buildStat('Serbest / Öz Stok', '${_numFormat.format(ownedStockKg)} kg', Colors.blue.shade700),
              _buildStat('Ortalama Randıman', '${wh.averageRendiment.toStringAsFixed(1)} R', _kText),
              _buildStat('Kapasite', wh.capacityKg > 0 ? '${_numFormat.format(wh.capacityKg)} kg' : 'Sınırsız', _kTextSecondary),
            ],
          ),
          if (wh.capacityKg > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: occupancyRatio,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                  occupancyRatio > 0.9 ? _kRed : (occupancyRatio > 0.7 ? POSColors.amber : _kGreen),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Kalan Boş Kapasite: ${_numFormat.format((wh.capacityKg - wh.currentStockKg).clamp(0.0, double.infinity))} kg',
                  style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                ),
                Text(
                  'Doluluk Oranı: %${(occupancyRatio * 100).toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kTextSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// ── Tab 1: Depo Hareketleri (Ekstre) ────────────────────────────────────────
  Widget _buildMovementsTab(AsyncValue<List<WarehouseHazelnutMovementEntity>> movementsAsync) {
    return movementsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hareketler yüklenemedi: $e')),
      data: (movements) {
        final filtered = movements.where((m) {
          if (_movementFilter == 'IN' && !m.movementType.contains('IN')) return false;
          if (_movementFilter == 'OUT' && !m.movementType.contains('OUT')) return false;
          if (_movementFilter == 'TRANSFER' && !m.movementType.contains('TRANSFER')) return false;

          if (_movementSearchQuery.isNotEmpty) {
            final desc = (m.description ?? '').toLowerCase();
            final typeLabel = _movementTypeLabel(m.movementType).toLowerCase();
            final qtyStr = m.quantityKg.toString();
            final matches = desc.contains(_movementSearchQuery) ||
                typeLabel.contains(_movementSearchQuery) ||
                qtyStr.contains(_movementSearchQuery);
            if (!matches) return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            // Filtre Barı
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _movementSearchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Açıklama, sevk no veya türe göre ara...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _movementSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () => _movementSearchCtrl.clear(),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      _buildFilterChip('Tümü', 'ALL'),
                      _buildFilterChip('Girişler', 'IN'),
                      _buildFilterChip('Çıkışlar', 'OUT'),
                      _buildFilterChip('Transferler', 'TRANSFER'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Liste
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 10),
                          Text(
                            movements.isEmpty
                                ? 'Bu depoda henüz bir hareket kaydedilmemiş.'
                                : 'Arama kriterlerine uygun hareket bulunamadı.',
                            style: const TextStyle(color: _kTextSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final m = filtered[index];
                        final isIncoming = m.movementType.contains('IN');
                        final isTransfer = m.movementType.contains('TRANSFER');

                        Color iconBg;
                        Color iconColor;
                        IconData iconData;

                        if (isTransfer) {
                          iconBg = Colors.blue.withValues(alpha: 0.12);
                          iconColor = Colors.blue.shade700;
                          iconData = Icons.swap_horiz_rounded;
                        } else if (isIncoming) {
                          iconBg = _kGreenLight;
                          iconColor = _kGreenDark;
                          iconData = Icons.arrow_downward_rounded;
                        } else {
                          iconBg = _kRedLight;
                          iconColor = _kRed;
                          iconData = Icons.arrow_upward_rounded;
                        }

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: iconBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(iconData, color: iconColor, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _movementTypeLabel(m.movementType),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
                                    ),
                                    if (m.description != null && m.description!.isNotEmpty)
                                      Text(
                                        m.description!,
                                        style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                                      ),
                                    Text(
                                      _dateFormat.format(m.createdAt),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isIncoming ? '+' : '-'}${_numFormat.format(m.quantityKg)} kg',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isIncoming ? _kGreenDark : _kRed,
                                    ),
                                  ),
                                  Text(
                                    '${m.rendiment.toStringAsFixed(1)} Randıman',
                                    style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                                  ),
                                  Text(
                                    'Bakiye: ${_numFormat.format(m.balanceKgAfter)} kg',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _movementFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: _kGreenLight,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? _kGreenDark : _kTextSecondary,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _movementFilter = value);
        }
      },
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
      ],
    );
  }

  String _movementTypeLabel(String type) {
    switch (type) {
      case 'ESCROW_IN':
        return 'Müşteri Emanet Girişi';
      case 'PURCHASE_IN':
        return 'Doğrudan Alım Girişi';
      case 'TRANSFER_IN':
        return 'Depo Transfer Girişi';
      case 'SALE_OUT':
        return 'Fabrika Satış / Çıkış';
      case 'TRANSFER_OUT':
        return 'Depo Transfer Çıkışı';
      case 'RETURN_OUT':
        return 'İade / Diğer Çıkış';
      default:
        return type;
    }
  }
}
