part of '../checkout_section.dart';

class _CustomerSelectionSheet extends ConsumerStatefulWidget {
  final CustomerEntity? initialSelected;
  final Function(CustomerEntity?) onCustomerChanged;
  final bool isDialog;

  const _CustomerSelectionSheet({
    required this.initialSelected,
    required this.onCustomerChanged,
    required this.isDialog,
  });

  @override
  ConsumerState<_CustomerSelectionSheet> createState() =>
      _CustomerSelectionSheetState();
}

class _CustomerSelectionSheetState
    extends ConsumerState<_CustomerSelectionSheet> {
  bool _isAdding = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  final ScrollController _scrollController = ScrollController();

  // Add Customer Form Key & Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(salesCustomersControllerProvider.notifier).loadNextPage();
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    if (widget.isDialog) {
      return Container(
        width: 450,
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isAdding ? _buildAddView() : _buildSelectionView(),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        maxWidth: 500,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isAdding ? _buildAddView() : _buildSelectionView(),
      ),
    );
  }

  Widget _buildSelectionView() {
    final customersAsync = ref.watch(salesCustomersControllerProvider);

    return Column(
      key: const ValueKey('selection_view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Müşteri Seç',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _kText),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'İsim veya telefon ile ara...',
                    hintStyle:
                        const TextStyle(color: _kTextSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: _kTextSecondary),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                    if (_searchDebounce?.isActive ?? false)
                      _searchDebounce!.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 300), () {
                      ref
                          .read(salesCustomerSearchQueryProvider.notifier)
                          .state = val;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => setState(() {
                _isAdding = true;
                _nameController.text = _searchQuery;
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text(
                'Yeni',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Flexible(
          child: customersAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hata: $err',
                  style: const TextStyle(color: _kRed, fontSize: 12)),
            ),
            data: (customersList) {
              final filtered = customersList;

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        const Text(
                          'Müşteri bulunamadı.',
                          style:
                              TextStyle(color: _kTextSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _isAdding = true;
                            _nameController.text = _searchQuery;
                          }),
                          icon: const Icon(Icons.person_add_rounded,
                              color: _kGreen),
                          label: Text(
                            '"$_searchQuery" Ekle',
                            style: const TextStyle(
                                color: _kGreen, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: filtered.length +
                    (ref
                            .read(salesCustomersControllerProvider.notifier)
                            .isLoadingMore
                        ? 1
                        : 0),
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, idx) {
                  if (idx == filtered.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(_kGreen),
                        ),
                      ),
                    );
                  }
                  final cust = filtered[idx];
                  final isDebt = cust.balance < 0;
                  final isSelected = widget.initialSelected?.id == cust.id;

                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _kGreenLight.withValues(alpha: 0.5)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? _kGreen : _kBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected
                            ? _kGreen
                            : (isDebt ? _kRedLight : _kGreenLight),
                        child: Text(
                          cust.name.isNotEmpty
                              ? cust.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isDebt ? _kRed : _kGreenDark),
                          ),
                        ),
                      ),
                      title: Text(
                        cust.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isSelected ? _kGreenDark : _kText,
                        ),
                      ),
                      subtitle: Text(
                        cust.phone.isEmpty ? 'Telefon yok' : cust.phone,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₺${cust.balance.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              color: isDebt ? _kRed : _kGreenDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle_rounded,
                                color: _kGreen, size: 18),
                          ],
                        ],
                      ),
                      onTap: () {
                        widget.onCustomerChanged(cust);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddView() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('add_view'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _isAdding = false),
              ),
              const Expanded(
                child: Text(
                  'Yeni Müşteri Ekle',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: _kText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Müşteri / Firma Adı *',
              hintText: 'Ad Soyad veya Firma Ünvanı',
              prefixIcon: const Icon(Icons.person_rounded,
                  size: 18, color: _kTextSecondary),
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
                borderSide: const BorderSide(color: _kGreen, width: 2),
              ),
              filled: true,
              fillColor: _kSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Ad zorunludur' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s\+\-]'))
            ],
            decoration: InputDecoration(
              labelText: 'Telefon Numarası',
              hintText: 'Örn: 0500 000 0000',
              prefixIcon: const Icon(Icons.phone_rounded,
                  size: 18, color: _kTextSecondary),
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
                borderSide: const BorderSide(color: _kGreen, width: 2),
              ),
              filled: true,
              fillColor: _kSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _isAdding = false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: const BorderSide(color: _kBorder),
                  ),
                  child: const Text(
                    'İptal',
                    style: TextStyle(
                        color: _kTextSecondary, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Kaydet ve Seç',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveCustomer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    try {
      final newCust = CustomerEntity(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: '',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      await ref
          .read(salesCustomersControllerProvider.notifier)
          .addCustomer(newCust);
      ref.invalidate(dashboardProvider);
      widget.onCustomerChanged(newCust);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newCust.name} eklendi ve seçildi.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Müşteri eklenirken hata: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
