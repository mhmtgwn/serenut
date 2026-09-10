// lib/presentation/widgets/common/customer_picker_widget.dart
//
// Tek bir ortak müşteri seçme widget'ı.
// Sipariş oluşturma (orders context) ve satış/checkout (sales context) tarafından
// ortak kullanılır. Provider bağımlılıkları CustomerPickerConfig üzerinden enjekte edilir.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/config/utils.dart';

// ─── Renk sabitleri ──────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kRed = Color(0xFFDC2626);
const _kSurface = POSColors.surface;
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

// ─────────────────────────────────────────────────────────────────────────────
/// Context yapılandırması — hangi provider ekosistemi kullanılacağını belirtir.
/// İki hazır fabrika metod: [orders] ve [sales].
// ─────────────────────────────────────────────────────────────────────────────
abstract class CustomerPickerConfig {
  AsyncValue<List<CustomerEntity>> watchCustomers(WidgetRef ref);
  CustomersController readController(WidgetRef ref);
  void updateSearchQuery(WidgetRef ref, String query);
  void onAfterSave(WidgetRef ref, CustomerEntity saved);

  factory CustomerPickerConfig.orders() = _OrdersCustomerPickerConfig;
  factory CustomerPickerConfig.sales() = _SalesCustomerPickerConfig;
}

class _OrdersCustomerPickerConfig implements CustomerPickerConfig {
  const _OrdersCustomerPickerConfig();

  @override
  AsyncValue<List<CustomerEntity>> watchCustomers(WidgetRef ref) =>
      ref.watch(ordersCustomersControllerProvider);

  @override
  CustomersController readController(WidgetRef ref) =>
      ref.read(ordersCustomersControllerProvider.notifier);

  @override
  void updateSearchQuery(WidgetRef ref, String query) {
    ref.read(ordersCustomerSearchQueryProvider.notifier).state = query;
  }

  @override
  void onAfterSave(WidgetRef ref, CustomerEntity saved) {}
}

class _SalesCustomerPickerConfig implements CustomerPickerConfig {
  const _SalesCustomerPickerConfig();

  @override
  AsyncValue<List<CustomerEntity>> watchCustomers(WidgetRef ref) =>
      ref.watch(salesCustomersControllerProvider);

  @override
  CustomersController readController(WidgetRef ref) =>
      ref.read(salesCustomersControllerProvider.notifier);

  @override
  void updateSearchQuery(WidgetRef ref, String query) {
    ref.read(salesCustomerSearchQueryProvider.notifier).state = query;
  }

  @override
  void onAfterSave(WidgetRef ref, CustomerEntity saved) {}
}

// ─────────────────────────────────────────────────────────────────────────────
/// Ortak müşteri seçme widget'ı.
///
/// Hem sipariş oluşturma adımı hem de satış/checkout bottom sheet tarafından
/// kullanılır. Tüm UI state'i (arama metni, "yeni ekle" modu) widget içinde
/// yönetilir; data ve aksiyonlar [CustomerPickerConfig] üzerinden sağlanır.
// ─────────────────────────────────────────────────────────────────────────────
class CustomerPickerWidget extends ConsumerStatefulWidget {
  /// Kullanılacak provider ekosistemi
  final CustomerPickerConfig config;

  /// Mevcut seçili müşteri (null = seçilmedi)
  final CustomerEntity? selectedCustomer;

  /// Bir müşteri seçildiğinde çağrılır
  final void Function(CustomerEntity customer) onSelected;

  /// Seçim kaldırıldığında çağrılır (null = kaldır butonu gizle)
  final VoidCallback? onCleared;

  /// Yeni müşteri kaydedilip seçildikten sonra ek aksiyon (örn: sonraki adıma geç)
  final void Function(CustomerEntity newCustomer)? onSavedAndSelected;

  /// [true] = sayfanın tamamını kaplayan liste modu (sipariş adımı)
  /// [false] = bottom sheet / dialog modu (checkout)
  final bool fullPageMode;

  const CustomerPickerWidget({
    super.key,
    required this.config,
    required this.onSelected,
    this.selectedCustomer,
    this.onCleared,
    this.onSavedAndSelected,
    this.fullPageMode = true,
  });

  @override
  ConsumerState<CustomerPickerWidget> createState() =>
      _CustomerPickerWidgetState();
}

class _CustomerPickerWidgetState extends ConsumerState<CustomerPickerWidget> {
  // ── Local state ────────────────────────────────────────────────────────────
  bool _isAddingCustomer = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  final _scrollController = ScrollController();

  // Yeni müşteri form
  final _addFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      final notifier = widget.config.readController(ref);
      if (notifier.hasMoreData) {
        notifier.loadNextPage();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      widget.config.updateSearchQuery(ref, val);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
    widget.config.updateSearchQuery(ref, '');
  }

  Future<void> _saveNewCustomer() async {
    if (!(_addFormKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    try {
      final newCustomer = CustomerEntity(
        id: const Uuid().v4(),
        name: _nameController.text.toTurkishUpperCase,
        phone: _phoneController.text.trim(),
        email: '',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      await widget.config.readController(ref).addCustomer(newCustomer);

      _clearSearch();
      await widget.config.readController(ref).refresh();

      widget.config.onAfterSave(ref, newCustomer);
      widget.onSelected(newCustomer);
      widget.onSavedAndSelected?.call(newCustomer);

      if (mounted) {
        setState(() {
          _isAddingCustomer = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${newCustomer.name} eklendi ve seçildi.'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Müşteri eklenirken hata: $e'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isAddingCustomer) return _buildAddForm();

    final customersAsync = widget.config.watchCustomers(ref);
    final loadingMore = ref.watch(customerLoadingMoreProvider);
    final hasMore = widget.config.readController(ref).hasMoreData;
    final customers = customersAsync.valueOrNull ?? const <CustomerEntity>[];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Seçili müşteri banner ────────────────────────────────────────
        if (widget.selectedCustomer != null) ...[
          _buildSelectedBanner(widget.selectedCustomer!),
          const SizedBox(height: 12),
        ],

        // ── Arama + Yeni Müşteri satırı ──────────────────────────────────
        _buildSearchRow(),
        const SizedBox(height: 12),

        // ── Liste ────────────────────────────────────────────────────────
        Expanded(
          child: _buildList(
            customersAsync: customersAsync,
            customers: customers,
            loadingMore: loadingMore,
            hasMore: hasMore,
          ),
        ),
      ],
    );

    return widget.fullPageMode
        ? Padding(padding: const EdgeInsets.all(20), child: content)
        : content;
  }

  // ─── Search row ──────────────────────────────────────────────────────────
  Widget _buildSearchRow() {
    final searchField = TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Müşteri ara (isim veya telefon)...',
        hintStyle:
            const TextStyle(color: _kTextSecondary, fontSize: 13),
        prefixIcon:
            const Icon(Icons.search_rounded, color: _kTextSecondary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: _clearSearch,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGreen, width: 1.5),
        ),
        filled: true,
        fillColor: _kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      onChanged: _onSearchChanged,
    );

    final addBtn = ElevatedButton.icon(
      onPressed: () => setState(() {
        _isAddingCustomer = true;
        _nameController.text = _searchQuery;
        _phoneController.clear();
      }),
      style: ElevatedButton.styleFrom(
        backgroundColor: _kGreenLight,
        foregroundColor: _kGreenDark,
        elevation: 0,
        minimumSize: const Size(0, 42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _kGreen.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
      label: const Text('Yeni',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 480) {
        return Row(children: [
          Expanded(child: searchField),
          const SizedBox(width: 10),
          addBtn,
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        searchField,
        const SizedBox(height: 8),
        addBtn,
      ]);
    });
  }

  // ─── Customer list ───────────────────────────────────────────────────────
  Widget _buildList({
    required AsyncValue<List<CustomerEntity>> customersAsync,
    required List<CustomerEntity> customers,
    required bool loadingMore,
    required bool hasMore,
  }) {
    if (customersAsync.isLoading && customers.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(_kGreen)));
    }
    if (customersAsync.hasError && customers.isEmpty) {
      return Center(
        child: Text('Müşteriler yüklenemedi: ${customersAsync.error}',
            style: const TextStyle(color: _kRed),
            textAlign: TextAlign.center),
      );
    }
    if (customers.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.people_outline_rounded,
              size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('Aradığınız müşteri bulunamadı.',
              style: TextStyle(color: _kTextSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() {
              _isAddingCustomer = true;
              _nameController.text = _searchQuery;
            }),
            icon:
                const Icon(Icons.person_add_rounded, color: _kGreen),
            label: Text(
              _searchQuery.isNotEmpty
                  ? '"$_searchQuery" Ekle'
                  : 'Yeni Müşteri Ekle',
              style: const TextStyle(
                  color: _kGreen, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (scrollInfo.metrics.pixels >=
            scrollInfo.metrics.maxScrollExtent - 400) {
          if (hasMore && !loadingMore) {
            widget.config.readController(ref).loadNextPage();
          }
        }
        return false;
      },
      child: Stack(children: [
        ListView.builder(
          controller: _scrollController,
          itemCount: customers.length + (loadingMore ? 1 : 0),
          itemBuilder: (context, idx) {
            if (idx == customers.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(_kGreen))),
              );
            }
            return _buildCustomerTile(customers[idx]);
          },
        ),
        if (customersAsync.isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ]),
    );
  }

  // ─── Single customer tile ─────────────────────────────────────────────────
  Widget _buildCustomerTile(CustomerEntity c) {
    final isSel = widget.selectedCustomer?.id == c.id;
    final isDebt = c.balance < 0;

    return GestureDetector(
      onTap: () => widget.onSelected(c),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSel ? _kGreen.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? _kGreen : _kBorder,
            width: isSel ? 1.5 : 1,
          ),
          boxShadow: isSel
              ? [
                  BoxShadow(
                      color: _kGreen.withValues(alpha: 0.08),
                      blurRadius: 6)
                ]
              : null,
        ),
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor:
                isSel ? _kGreen : (isDebt ? const Color(0xFFFEE2E2) : _kGreenLight),
            foregroundColor:
                isSel ? Colors.white : (isDebt ? _kRed : _kGreenDark),
            child: Text(
              c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          title: Text(c.name.toTurkishUpperCase,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _kText,
                  fontSize: 13)),
          subtitle: Text(
            c.phone.isNotEmpty ? c.phone : 'Telefon Yok',
            style: const TextStyle(
                color: _kTextSecondary, fontSize: 11),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '₺${c.balance.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: isDebt ? _kRed : _kGreenDark,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              height: 20,
              child: isSel
                  ? const Icon(Icons.check_circle_rounded,
                      color: _kGreen, size: 20)
                  : null,
            ),
          ]),
        ),
      ),
    );
  }

  // ─── Selected customer banner ─────────────────────────────────────────────
  Widget _buildSelectedBanner(CustomerEntity c) {
    final isDebt = c.balance < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreen, width: 1.5),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration:
              const BoxDecoration(color: _kGreen, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: _kGreen,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('SEÇİLİ MÜŞTERİ',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _kText),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Text(
                    c.phone.isNotEmpty ? c.phone : 'Telefon Yok',
                    style: const TextStyle(
                        color: _kTextSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Bakiye: ₺${c.balance.abs().toStringAsFixed(2)}${isDebt ? ' (Borç)' : ''}',
                    style: TextStyle(
                        color: isDebt ? _kRed : _kGreenDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ]),
              ]),
        ),
        if (widget.onCleared != null)
          TextButton.icon(
            onPressed: widget.onCleared,
            icon: const Icon(Icons.close_rounded,
                size: 16, color: _kTextSecondary),
            label: const Text('Kaldır',
                style:
                    TextStyle(color: _kTextSecondary, fontSize: 12)),
          ),
      ]),
    );
  }

  // ─── Add customer form ────────────────────────────────────────────────────
  Widget _buildAddForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _addFormKey,
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: _kTextSecondary),
                    onPressed: () =>
                        setState(() => _isAddingCustomer = false),
                  ),
                  const Text('Yeni Müşteri Ekle',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _kText)),
                ]),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Müşteri / Firma Adı *',
                    hintText: 'Ad Soyad veya Firma Ünvanı',
                    prefixIcon: const Icon(Icons.person_rounded,
                        color: _kTextSecondary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _kGreen, width: 2),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Ad zorunludur'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Telefon Numarası',
                    hintText: 'Örn: 05xx xxx xx xx',
                    prefixIcon: const Icon(Icons.phone_rounded,
                        color: _kTextSecondary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _kGreen, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => setState(
                              () => _isAddingCustomer = false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('İptal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveNewCustomer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Text('Kaydet ve Seç',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }
}
