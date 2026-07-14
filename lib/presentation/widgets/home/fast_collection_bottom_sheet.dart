import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';

class FastCollectionBottomSheet extends ConsumerStatefulWidget {
  const FastCollectionBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const FastCollectionBottomSheet(),
      ),
    );
  }

  @override
  ConsumerState<FastCollectionBottomSheet> createState() => _FastCollectionBottomSheetState();
}

class _FastCollectionBottomSheetState extends ConsumerState<FastCollectionBottomSheet> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersControllerProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Hızlı Cari Tahsilat',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Müşteri ismi veya telefon yazın...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: customersAsync.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2))),
              error: (err, _) => Text('Hata: $err', style: const TextStyle(color: Colors.red)),
              data: (list) {
                final filtered = list.where((c) {
                  final matchesSearch = c.name.toLowerCase().contains(_searchQuery) ||
                                       c.phone.toLowerCase().contains(_searchQuery);
                  return matchesSearch;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Uyumlu müşteri bulunamadı.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, index) {
                    final customer = filtered[index];
                    final balance = customer.balance;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(customer.phone.isNotEmpty ? customer.phone : 'Telefon yok', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₺${balance.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: balance < 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF64748B)),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.pushNamed(
                          'customerCollect',
                          pathParameters: {'id': customer.id},
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
