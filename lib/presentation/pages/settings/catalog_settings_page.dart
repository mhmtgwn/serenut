import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

class CatalogSettingsPage extends ConsumerWidget {
  const CatalogSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider).valueOrNull;
    final categories = _decode(settings?.vatCategories);
    final productCategories = ref.watch(productCategoriesProvider);
    for (final name in productCategories) {
      if (!categories.any((item) =>
          item['name']?.toString().toLowerCase() == name.toLowerCase())) {
        categories.add({'name': name, 'rate': null, 'inferred': true});
      }
    }
    categories.sort((a, b) => (a['name'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['name'] ?? '').toString().toLowerCase()));
    return FullScreenSettingsPage(
      title: 'Ürün Kataloğu',
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Kategori ekle',
          onPressed: settings == null
              ? null
              : () => _editCategory(context, ref, categories: categories),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: POSColors.greenLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Kategori adı ve varsayılan KDV oranını buradan yönetin. '
                    'Bir kategoriyi mevcut başka bir kategoriyle aynı ada '
                    'çevirirseniz ürünler otomatik olarak aynı kategori altında toplanır.',
                  ),
                ),
                const SizedBox(height: 12),
                if (categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Henüz kategori tanımlanmamış.')),
                  )
                else
                  ...categories.map((category) => Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: POSColors.greenLight,
                            child: Icon(Icons.category_rounded,
                                color: POSColors.greenDark),
                          ),
                          title:
                              Text(category['name']?.toString() ?? 'Kategori'),
                          subtitle: Text(category['rate'] == null
                              ? 'KDV tanımlanmamış'
                              : 'KDV %${category['rate']}'),
                          trailing: const Icon(Icons.edit_rounded),
                          onTap: () => _editCategory(
                            context,
                            ref,
                            categories: categories,
                            original: category,
                          ),
                        ),
                      )),
              ],
            ),
    );
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    try {
      final decoded = jsonDecode(raw?.isNotEmpty == true ? raw! : '[]');
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
        ..sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
    } catch (_) {
      return [];
    }
  }

  static String _canonicalName(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  static Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref, {
    required List<Map<String, dynamic>> categories,
    Map<String, dynamic>? original,
  }) async {
    final name = TextEditingController(text: original?['name']?.toString());
    final vat =
        TextEditingController(text: original?['rate']?.toString() ?? '');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(original == null ? 'Kategori ekle' : 'Kategoriyi düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Kategori adı'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vat,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Varsayılan KDV (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    final newName = _canonicalName(name.text);
    final rate = int.tryParse(vat.text.trim());
    if (newName.isEmpty || rate == null || rate < 0 || rate > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Kategori adı ve KDV oranını kontrol edin.')),
      );
      return;
    }

    final oldName = original?['name']?.toString().trim();
    final updated = categories
        .where((item) => !identical(item, original))
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final duplicateIndex = updated.indexWhere(
      (item) => item['name']?.toString().toLowerCase() == newName.toLowerCase(),
    );
    final entry = {'name': newName, 'rate': rate};
    if (duplicateIndex >= 0) {
      updated[duplicateIndex] = entry;
    } else {
      updated.add(entry);
    }

    final repository = await ref.read(productRepositoryProvider.future);
    if (oldName != null && oldName.toLowerCase() != newName.toLowerCase()) {
      final products = await repository.findAll();
      for (final product in products.where(
        (item) => item.category.toLowerCase() == oldName.toLowerCase(),
      )) {
        await repository.update(product.copyWith(
          category: newName,
          vat: rate,
        ));
      }
    }
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings != null) {
      await ref.read(settingsNotifierProvider.notifier).updateSettings(
            settings.copyWith(vatCategories: jsonEncode(updated)),
          );
    }
    ref.invalidate(productsControllerProvider);
    ref.invalidate(productCategoriesProvider);
    ref.invalidate(productInventorySummaryProvider);
    final audit = await ref.read(auditServiceProvider.future);
    await audit.logEvent(
      eventType: original == null ? 'category_created' : 'category_updated',
      entityType: 'product_category',
      entityId: newName,
      oldValue: original == null ? null : jsonEncode(original),
      newValue: jsonEncode(entry),
      notes: 'Kategori ve varsayılan KDV ayarı değiştirildi.',
    );
  }
}
