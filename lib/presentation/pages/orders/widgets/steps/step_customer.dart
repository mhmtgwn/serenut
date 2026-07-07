part of '../order_creation_dialog.dart';

// Extracted Customer Step widgets for OrderCreationDialog
extension OrderCreationCustomerStep on OrderCreationDialogState {
  Widget _buildCustomerStep() {
    if (_isAddingCustomer) {
      return _buildAddCustomerForm();
    }

    final customersVal = ref.watch(customersControllerProvider);

    return customersVal.when(
      loading: () => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kGreen))),
      error: (err, _) => Center(child: Text('Müşteriler yüklenemedi: $err', style: const TextStyle(color: _kRed))),
      data: (customersList) {
        final filtered = customersList.where((c) {
          final query = _customerQuery.toLowerCase();
          return c.name.toLowerCase().contains(query) || c.phone.contains(query);
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Search and add button row
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isWide = constraints.maxWidth >= 500;
                  final searchField = TextField(
                    decoration: InputDecoration(
                      hintText: 'Müşteri ara (isim veya telefon)...',
                      prefixIcon: const Icon(Icons.search_rounded, color: _kTextSecondary),
                      suffixIcon: _customerQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => updateState(() => _customerQuery = ''),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) => updateState(() => _customerQuery = val),
                  );

                  final addBtn = ElevatedButton.icon(
                    onPressed: () => updateState(() {
                      _isAddingCustomer = true;
                      _newCustNameController.text = _customerQuery;
                      _newCustPhoneController.clear();
                      _newCustBalanceController.text = '0';
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreenLight,
                      foregroundColor: _kGreenDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: _kGreen.withValues(alpha: 0.3)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Yeni Müşteri Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
                  );

                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 12),
                        addBtn,
                      ],
                    );
                  } else {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchField,
                        const SizedBox(height: 10),
                        addBtn,
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              // Customer List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text(
                              'Aradığınız müşteri bulunamadı.',
                              style: TextStyle(color: _kTextSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final c = filtered[idx];
                          final isSel = _selectedCustomer?.id == c.id;
                          final isDebt = c.balance < 0;

                          return GestureDetector(
                            onTap: () => updateState(() => _selectedCustomer = c),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isSel ? _kGreen.withValues(alpha: 0.05) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel ? _kGreen : _kBorder,
                                  width: 1.5,
                                ),
                                boxShadow: isSel
                                    ? [BoxShadow(color: _kGreen.withValues(alpha: 0.08), blurRadius: 6)]
                                    : null,
                              ),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: isSel ? _kGreen : (isDebt ? _kRedLight : _kGreenLight),
                                  foregroundColor: isSel ? Colors.white : (isDebt ? _kRed : _kGreenDark),
                                  child: Text(
                                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                title: Text(
                                  c.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: _kText, fontSize: 13),
                                ),
                                subtitle: Text(
                                  c.phone.isNotEmpty ? c.phone : 'Telefon Yok',
                                  style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                                          ? const Icon(Icons.check_circle_rounded, color: _kGreen, size: 20)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddCustomerForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _addCustomerFormKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: _kTextSecondary),
                    onPressed: () => updateState(() => _isAddingCustomer = false),
                  ),
                  const Text(
                    'Yeni Müşteri Ekle',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kText),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Name Field
              TextFormField(
                controller: _newCustNameController,
                decoration: InputDecoration(
                  labelText: 'Müşteri Adı Soyadı *',
                  prefixIcon: const Icon(Icons.person_rounded, color: _kTextSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Lütfen ad soyad girin' : null,
              ),
              const SizedBox(height: 16),
              // Phone Field
              TextFormField(
                controller: _newCustPhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefon Numarası',
                  prefixIcon: const Icon(Icons.phone_rounded, color: _kTextSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: '5xx xxx xx xx',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
              ),
              const SizedBox(height: 16),
              // Starting Balance Field
              TextFormField(
                controller: _newCustBalanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Başlangıç Bakiyesi (₺)',
                  prefixIcon: const Icon(Icons.account_balance_wallet_rounded, color: _kTextSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  helperText: 'Negatif: Müşteri borçlu, Pozitif: Müşteri alacaklı',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d*')),
                ],
              ),
              const SizedBox(height: 32),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => updateState(() => _isAddingCustomer = false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('İptal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSavingCustomer ? null : _saveNewCustomer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSavingCustomer
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Kaydet ve Seç', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _saveNewCustomer() async {
    if (!_addCustomerFormKey.currentState!.validate()) return;
    updateState(() => _isSavingCustomer = true);

    try {
      final name = _newCustNameController.text.trim();
      final phone = _newCustPhoneController.text.trim();
      final balStr = _newCustBalanceController.text.replaceAll(',', '.').trim();
      final double balance = double.tryParse(balStr) ?? 0.0;

      final newCustomer = CustomerEntity(
        id: 'cust-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000).toString().padLeft(4, '0')}',
        name: name,
        email: '',
        phone: phone,
        balance: balance,
        createdAt: DateTime.now(),
      );

      // Save customer to local database
      await ref.read(customersControllerProvider.notifier).addCustomer(newCustomer);
      
      // If there's initial balance (either positive or negative), record initial ledger transaction
      if (balance != 0) {
        final txRepo = await ref.read(financialTransactionRepositoryProvider.future);
        final transactionId = 'trans-init-${DateTime.now().microsecondsSinceEpoch}';
        await txRepo.create(
          FinancialTransactionEntity(
            id: transactionId,
            type: 'initial_balance',
            customerId: newCustomer.id,
            amount: balance.abs(),
            paidAmount: balance > 0 ? balance : 0.0,
            debtAmount: balance < 0 ? balance.abs() : 0.0,
            date: DateTime.now(),
            referenceId: 'init',
            metadata: {'note': 'Başlangıç bakiyesi ayarı'},
          ),
        );
      }

      await ref.read(customersControllerProvider.notifier).refresh();

      if (mounted) {
        updateState(() {
          _selectedCustomer = newCustomer;
          _isAddingCustomer = false;
          _isSavingCustomer = false;
          _customerQuery = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Müşteri başarıyla kaydedildi.'), backgroundColor: _kGreen),
        );
      }
    } catch (e) {
      updateState(() => _isSavingCustomer = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Müşteri kaydedilirken hata: $e'), backgroundColor: _kRed),
        );
      }
    }
  }
}
