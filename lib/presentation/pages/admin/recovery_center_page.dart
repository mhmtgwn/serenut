// lib/presentation/pages/admin/recovery_center_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/providers/recovery_provider.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/models/permission.dart';

class RecoveryCenterPage extends ConsumerStatefulWidget {
  const RecoveryCenterPage({super.key});

  @override
  ConsumerState<RecoveryCenterPage> createState() => _RecoveryCenterPageState();
}

class _RecoveryCenterPageState extends ConsumerState<RecoveryCenterPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _deletedItems = [];
  bool _isLoading = false;

  final List<Map<String, String>> _tabs = [
    {'id': 'product', 'label': 'Ürünler'},
    {'id': 'customer', 'label': 'Müşteriler'},
    {'id': 'sale', 'label': 'Satışlar'},
    {'id': 'order', 'label': 'Siparişler'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadDeletedItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    _loadDeletedItems();
  }

  Future<void> _loadDeletedItems() async {
    setState(() => _isLoading = true);
    try {
      final type = _tabs[_tabController.index]['id']!;
      final repo = ref.read(recoveryRepositoryProvider);
      final items = await repo.getDeletedItems(type);
      setState(() {
        _deletedItems = items;
      });
    } catch (_) {
      // Fail-safe
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _runPinGuardedAction(String actionTitle, void Function(String? approvedByUserId, String? approvedByUserName) action) {
    requirePermissionAccess(
      context,
      permission: Permission.settingsRecovery,
      title: actionTitle,
      requirePin: true,
      onGranted: (approvedByUserId, approvedByUserName) {
        if (mounted) {
          action(approvedByUserId, approvedByUserName);
        }
      },
    );
  }

  Future<void> _restoreItem(String type, String id, String name) async {
    _runPinGuardedAction('Kaydı Kurtar: $name', (approvedByUserId, approvedByUserName) async {
      setState(() => _isLoading = true);
      try {
        final repo = ref.read(recoveryRepositoryProvider);
        await repo.restore(type, id);
        
        try {
          final auditService = await ref.read(auditServiceProvider.future);
          await auditService.logSystemAction(
            'entity_restored',
            'Tur: $type, ID: $id, Name: $name',
            approvedByUserId: approvedByUserId,
            approvedByUserName: approvedByUserName,
          );
        } catch (_) {}

        // Invalidate corresponding controller to sync UI
        _invalidateControllerForType(type);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name başarıyla kurtarıldı.'), backgroundColor: const Color(0xFF10B981)),
        );
        _loadDeletedItems();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kurtarma hatası: $e'), backgroundColor: Colors.redAccent),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _purgeItem(String type, String id, String name) async {
    _runPinGuardedAction('Kaydı Kalıcı Olarak Sil: $name', (approvedByUserId, approvedByUserName) async {
      setState(() => _isLoading = true);
      try {
        final repo = ref.read(recoveryRepositoryProvider);
        await repo.purge(type, id);
        
        try {
          final auditService = await ref.read(auditServiceProvider.future);
          await auditService.logSystemAction(
            'entity_purged',
            'Tur: $type, ID: $id, Name: $name',
            approvedByUserId: approvedByUserId,
            approvedByUserName: approvedByUserName,
          );
        } catch (_) {}

        // Invalidate corresponding controller to sync UI
        _invalidateControllerForType(type);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name kalıcı olarak silindi (Purged).'), backgroundColor: Colors.orangeAccent),
        );
        _loadDeletedItems();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silme hatası: $e'), backgroundColor: Colors.redAccent),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    });
  }

  void _invalidateControllerForType(String type) {
    switch (type) {
      case 'product':
        ref.invalidate(productsControllerProvider);
        break;
      case 'customer':
        ref.invalidate(customersControllerProvider);
        break;
      case 'sale':
        ref.invalidate(salesControllerProvider);
        break;
      case 'order':
        ref.invalidate(ordersControllerProvider);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final hasAccess = currentUser != null && (
      currentUser.role == UserRole.sysadmin ||
      currentUser.role == UserRole.owner ||
      currentUser.role == UserRole.admin ||
      currentUser.hasPermission(Permission.settingsRecovery.value)
    );

    if (!hasAccess) {
      return const Scaffold(
        body: Center(
          child: Text('Bu sayfaya erişim yetkiniz bulunmuyor.'),
        ),
      );
    }

    const kDarkBackground = Color(0xFF0F172A); // Slate 900
    const kCardBg = Color(0xFF1E293B); // Slate 800
    const kBorderColor = Color(0xFF334155); // Slate 700
    const kAccentColor = Color(0xFFEF4444); // Red 500
    const kTextSecondary = Color(0xFF94A3B8); // Slate 400

    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: const Text(
          'Veri Kurtarma Merkezi',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: kCardBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadDeletedItems,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kAccentColor,
          labelColor: Colors.white,
          unselectedLabelColor: kTextSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: _tabs.map((t) => Tab(text: t['label'])).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(kAccentColor)))
          : _deletedItems.isEmpty
              ? const Center(
                  child: Text(
                    'Silinmiş (kurtarılabilir) kayıt bulunamadı.',
                    style: TextStyle(color: kTextSecondary, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  itemCount: _deletedItems.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final item = _deletedItems[index];
                    final type = _tabs[_tabController.index]['id']!;
                    final id = item['id'] as String;
                    final name = _getItemName(type, item);
                    final subtitle = _getItemSubtitle(type, item);
                    final deletedAtStr = item['deleted_at'] as String? ?? '';
                    final deletedAt = deletedAtStr.isNotEmpty ? DateTime.tryParse(deletedAtStr) : null;

                    return Card(
                      color: kCardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: kBorderColor),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle,
                                        style: const TextStyle(color: kTextSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (deletedAt != null)
                                  Text(
                                    DateFormat('dd.MM.yy HH:mm').format(deletedAt),
                                    style: const TextStyle(color: kTextSecondary, fontSize: 11),
                                  ),
                              ],
                            ),
                            const Divider(color: kBorderColor, height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kTextSecondary,
                                    side: const BorderSide(color: kBorderColor),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.delete_forever_rounded, size: 16, color: Colors.redAccent),
                                  label: const Text('Kalıcı Sil', style: TextStyle(fontSize: 12, color: Colors.white)),
                                  onPressed: () => _purgeItem(type, id, name),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981), // Emerald 500
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                                  label: const Text('Kurtar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () => _restoreItem(type, id, name),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _getItemName(String type, Map<String, dynamic> item) {
    switch (type) {
      case 'product':
        return item['name'] as String? ?? 'Bilinmeyen Ürün';
      case 'customer':
        return item['name'] as String? ?? 'Bilinmeyen Müşteri';
      case 'sale':
        return 'Satış: ${item['id']}';
      case 'order':
        return 'Sipariş: ${item['id']}';
      default:
        return 'Varlık';
    }
  }

  String _getItemSubtitle(String type, Map<String, dynamic> item) {
    switch (type) {
      case 'product':
        final cat = item['category'] as String? ?? '-';
        final price = item['price'] as double? ?? 0.0;
        return 'Kategori: $cat • Fiyat: ₺${price.toStringAsFixed(2)}';
      case 'customer':
        final phone = item['phone'] as String? ?? '-';
        final bal = item['balance'] as double? ?? 0.0;
        return 'Tel: $phone • Bakiye: ₺${bal.toStringAsFixed(2)}';
      case 'sale':
        final amt = item['total_amount'] as double? ?? 0.0;
        final method = item['payment_method'] as String? ?? '-';
        return 'Tutar: ₺${amt.toStringAsFixed(2)} • Yöntem: $method';
      case 'order':
        final status = item['status'] as String? ?? '-';
        final note = item['notes'] as String? ?? '';
        return 'Durum: $status ${note.isNotEmpty ? '• Not: $note' : ''}';
      default:
        return '';
    }
  }
}
