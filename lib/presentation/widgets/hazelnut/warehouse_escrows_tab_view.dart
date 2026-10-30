// lib/presentation/widgets/hazelnut/warehouse_escrows_tab_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/presentation/pages/customer_details_page.dart';

const _kGreenDark = POSColors.greenDark;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class WarehouseEscrowsTabView extends ConsumerStatefulWidget {
  final AsyncValue<List<CustomerHazelnutEscrowEntity>> escrowsAsync;
  final double escrowKgSum;

  const WarehouseEscrowsTabView({
    super.key,
    required this.escrowsAsync,
    required this.escrowKgSum,
  });

  @override
  ConsumerState<WarehouseEscrowsTabView> createState() => _WarehouseEscrowsTabViewState();
}

class _WarehouseEscrowsTabViewState extends ConsumerState<WarehouseEscrowsTabView> {
  static final NumberFormat _numFormat = NumberFormat.decimalPattern('tr_TR');
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  final TextEditingController _escrowSearchCtrl = TextEditingController();
  String _escrowSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _escrowSearchCtrl.addListener(() {
      setState(() {
        _escrowSearchQuery = _escrowSearchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _escrowSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.escrowsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Emanetler yüklenemedi: $e')),
      data: (escrows) {
        final filtered = escrows.where((e) {
          if (_escrowSearchQuery.isNotEmpty) {
            final name = (e.customerName ?? '').toLowerCase();
            final phone = (e.customerPhone ?? '').toLowerCase();
            final receipt = (e.receiptNo ?? '').toLowerCase();
            final notes = (e.notes ?? '').toLowerCase();
            final matches = name.contains(_escrowSearchQuery) ||
                phone.contains(_escrowSearchQuery) ||
                receipt.contains(_escrowSearchQuery) ||
                notes.contains(_escrowSearchQuery);
            if (!matches) return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            // Emanet Arama & Bilgi
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _escrowSearchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Müşteri adı, telefon, fiş no veya nota göre ara...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _escrowSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () => _escrowSearchCtrl.clear(),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: POSColors.amberLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: POSColors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.handshake_rounded, size: 16, color: POSColors.amberDark),
                        const SizedBox(width: 6),
                        Text(
                          '${escrows.length} Emanet Kaydı • Toplam ${_numFormat.format(widget.escrowKgSum)} kg',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: POSColors.amberDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Emanet Listesi
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.handshake_outlined, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 10),
                          Text(
                            escrows.isEmpty
                                ? 'Bu depoda şu anda emanet fındık bulunmuyor.'
                                : 'Arama kriterlerine uygun emanet kaydı bulunamadı.',
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
                        final esc = filtered[index];
                        final customerDisplayName =
                            esc.customerName ?? 'Müşteri #${esc.customerId.substring(0, 8)}';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: POSColors.amberLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.person_rounded, color: POSColors.amberDark, size: 20),
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
                                            customerDisplayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: _kText,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: POSColors.surfaceMuted,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Fiş #${esc.receiptNo ?? '-'}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: _kTextSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        if (esc.customerPhone != null && esc.customerPhone!.isNotEmpty) ...[
                                          const Icon(Icons.phone_outlined, size: 12, color: _kTextSecondary),
                                          const SizedBox(width: 4),
                                          Text(
                                            esc.customerPhone!,
                                            style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          _dateFormat.format(esc.createdAt),
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    if (esc.notes != null && esc.notes!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Not: ${esc.notes}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: _kTextSecondary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${_numFormat.format(esc.remainingKg)} kg',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: _kGreenDark,
                                    ),
                                  ),
                                  Text(
                                    '${esc.rendiment.toStringAsFixed(1)} Randıman',
                                    style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                                  ),
                                  if (esc.remainingKg != esc.netKg)
                                    Text(
                                      'İlk: ${_numFormat.format(esc.netKg)} kg',
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => CustomerDetailsPage(customerId: esc.customerId),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Müşteri Kartı',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 10,
                                            color: Colors.blue.shade700,
                                          ),
                                        ],
                                      ),
                                    ),
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
}
