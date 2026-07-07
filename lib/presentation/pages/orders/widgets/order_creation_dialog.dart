// lib/presentation/pages/orders/widgets/order_creation_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart' show paymentServiceProvider;
import 'package:serenutos/presentation/widgets/sales/barcode_scanner_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

part 'steps/step_customer.dart';
part 'steps/step_product_selection.dart';
part 'steps/step_cart_summary.dart';
part 'steps/step_checkout.dart';

// Color and layout constants
const _kGreen      = Color(0xFF16A34A);
const _kGreenDark  = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber      = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kAmberDark  = Color(0xFFB45309);
const _kRed        = Color(0xFFDC2626);
const _kRedLight   = Color(0xFFFEE2E2);
const _kSurface    = Color(0xFFF8FAFC);
const _kText       = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder     = Color(0xFFE2E8F0);

class OrderCreationDialog extends ConsumerStatefulWidget {
  final OrderEntity? existingOrder;
  const OrderCreationDialog({super.key, this.existingOrder});

  @override
  ConsumerState<OrderCreationDialog> createState() => OrderCreationDialogState();
}

class OrderCreationDialogState extends ConsumerState<OrderCreationDialog> {
  int _activeStep = 0;

  // Step 1: Customer Selection
  CustomerEntity? _selectedCustomer;
  String _customerQuery = '';
  bool _isAddingCustomer = false;
  final _addCustomerFormKey = GlobalKey<FormState>();
  final _newCustNameController = TextEditingController();
  final _newCustPhoneController = TextEditingController();
  final _newCustBalanceController = TextEditingController();
  bool _isSavingCustomer = false;

  // Step 2: Product Catalog
  final Map<ProductEntity, double> _cart = {};
  String _productQuery = '';
  String _selectedCategory = 'Tümü';
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _isProductSearching = false;
  final _productSearchController = TextEditingController();
  final ScrollController _productScrollController = ScrollController();

  // Step 3: Cart Review
  DateTime _expectedDelivery = DateTime.now().add(const Duration(days: 1));
  final _notesController = TextEditingController();

  // Step 4: Checkout
  String _paymentMethod = '';
  double _paidAmount = 0.0;
  final TextEditingController _cashSplitController = TextEditingController();
  final TextEditingController _cardSplitController = TextEditingController();
  final TextEditingController _debtSplitController = TextEditingController();
  bool _printReceipt = true;
  int _printCopies = 1;
  bool _printLabel = false;
  int _labelCopies = 1;
  bool _isSubmitting = false;

  String _barcodeBuffer = '';
  DateTime? _lastBufferTime;

  void updateState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _productScrollController.addListener(_onProductScroll);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings != null) {
      _printCopies = settings.printCopies;
    }
    _loadLabelPrinterSettings();
    _initExistingOrder();
    
    // Reset product filters when opening the order creation dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ordersProductSearchQueryProvider.notifier).state = '';
      ref.read(ordersProductCategoryFilterProvider.notifier).state = null;
    });
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_activeStep != 1) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final now = DateTime.now();
    if (_lastBufferTime != null) {
      final diff = now.difference(_lastBufferTime!).inMilliseconds;
      if (diff > 80) {
        _barcodeBuffer = '';
      }
    }
    _lastBufferTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_barcodeBuffer.length >= 3) {
        final code = _barcodeBuffer;
        _barcodeBuffer = '';
        _onBarcodeScanned(code);
        return true;
      }
      _barcodeBuffer = '';
    } else {
      String? char = event.character;
      if (char == null) {
        final label = event.logicalKey.keyLabel;
        if (label.length == 1 && RegExp(r'[a-zA-Z0-9-]').hasMatch(label)) {
          char = label;
        }
      }
      if (char != null && char.length == 1) {
        _barcodeBuffer += char;
      }
    }
    return false;
  }

  void _onBarcodeScanned(String barcode) {
    _productSearchController.clear();
    setState(() {
      _productQuery = '';
    });
    ref.read(productsControllerProvider).whenData((productsList) {
      _handleBarcodeSubmit(barcode, productsList);
    });
  }

  void _initExistingOrder() {
    if (widget.existingOrder != null) {
      final order = widget.existingOrder!;
      _notesController.text = order.notes ?? '';
      _expectedDelivery = order.expectedDeliveryDate ?? DateTime.now().add(const Duration(days: 1));
      
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final customers = ref.read(customersControllerProvider).value;
        if (customers != null) {
          setState(() {
            _selectedCustomer = customers.firstWhere(
              (c) => c.id == order.customerId,
              orElse: () => CustomerEntity(
                id: order.customerId,
                name: 'Bilinmeyen Müşteri',
                email: '',
                phone: '',
                balance: 0.0,
                createdAt: DateTime.now(),
              ),
            );
          });
        }

        final products = ref.read(productsControllerProvider).value;
        if (products != null) {
          setState(() {
            for (final item in order.items) {
              final productId = item['product_id']?.toString() ?? '';
              final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
              final product = products.firstWhere(
                (p) => p.id == productId,
                orElse: () => ProductEntity(
                  id: productId,
                  name: item['product_name']?.toString() ?? productId,
                  description: '',
                  price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
                  quantity: 0,
                  category: '',
                ),
              );
              _cart[product] = qty;
            }
          });
        }
        
        await _loadExistingPaymentInfo();
      });
    }
  }

  Future<void> _loadExistingPaymentInfo() async {
    if (widget.existingOrder == null) return;
    final order = widget.existingOrder!;
    try {
      final repo = await ref.read(financialTransactionRepositoryProvider.future);
      final transactions = await repo.getByCustomerId(order.customerId);
      FinancialTransactionEntity? orderTx;
      for (final t in transactions) {
        if (t.referenceId == order.id && t.type == 'sale') {
          orderTx = t;
          break;
        }
      }
      if (orderTx != null) {
        setState(() {
          final total = orderTx!.amount;
          final paid = orderTx.paidAmount;
          final debt = orderTx.debtAmount;
          if (paid == total) {
            _paymentMethod = 'cash';
            _paidAmount = total;
          } else if (paid == 0) {
            _paymentMethod = 'debt';
            _paidAmount = 0.0;
          } else {
            _paymentMethod = 'karma';
            _cashSplitController.text = paid.toStringAsFixed(2);
            _cardSplitController.text = '0.00';
            _debtSplitController.text = debt.toStringAsFixed(2);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading existing payment info: $e');
    }
  }

  Future<void> _loadLabelPrinterSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _printLabel = prefs.getBool('label_printer_enabled') ?? false;
        _labelCopies = prefs.getInt('label_printer_copies') ?? 1;
      });
    } catch (e) {
      debugPrint('Error loading label printer settings: $e');
    }
  }

  Future<void> _saveLabelPrinterSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('label_printer_enabled', _printLabel);
      await prefs.setInt('label_printer_copies', _labelCopies);
    } catch (e) {
      debugPrint('Error saving label printer settings: $e');
    }
  }

  void _onProductScroll() {
    if (_productScrollController.position.pixels >= _productScrollController.position.maxScrollExtent - 200) {
      ref.read(productsControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  void dispose() {
    _productScrollController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _newCustNameController.dispose();
    _newCustPhoneController.dispose();
    _newCustBalanceController.dispose();
    _notesController.dispose();
    _cashSplitController.dispose();
    _cardSplitController.dispose();
    _debtSplitController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  double get _totalAmount {
    double sum = 0;
    _cart.forEach((p, qty) => sum += p.price * qty);
    return sum;
  }

  // Karma split fields getters
  double get _karmaCash => double.tryParse(_cashSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaCard => double.tryParse(_cardSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaDebt => _selectedCustomer != null
      ? (double.tryParse(_debtSplitController.text.replaceAll(',', '.')) ?? 0.0)
      : 0.0;

  double get _karmaTotal => _karmaCash + _karmaCard + _karmaDebt;
  double get _karmaRemainder => (_totalAmount - _karmaTotal).clamp(0.0, double.infinity);
  bool get _karmaValid => _totalAmount > 0 && (_karmaTotal - _totalAmount).abs() < 0.01;

  void _nextStep() {
    if (_activeStep < 3) {
      setState(() => _activeStep++);
      if (_activeStep == 1) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _barcodeFocusNode.requestFocus();
        });
      }
    }
  }

  void _prevStep() {
    if (_activeStep > 0) {
      setState(() => _activeStep--);
      if (_activeStep == 1) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _barcodeFocusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _handleBarcodeSubmit(String barcode, List<ProductEntity> productsList) async {
    if (barcode.trim().isEmpty) return;
    
    final repository = await ref.read(productRepositoryProvider.future);
    
    // 1. Direct ID / SKU match
    var matched = await repository.findById(barcode.trim());
    
    // 2. Search by name/exact matches
    if (matched == null) {
      final results = await repository.searchByName(barcode.trim());
      if (results.isNotEmpty) {
        matched = results.first;
      }
    }

    if (matched != null) {
      setState(() {
        // Find existing instance in the cart or create new entry
        final existingKey = _cart.keys.firstWhere(
          (p) => p.id == matched!.id,
          orElse: () => matched!,
        );
        _cart[existingKey] = (_cart[existingKey] ?? 0.0) + 1.0;
      });
      _barcodeController.clear();
      _barcodeFocusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${matched.name} siparişe eklendi.'),
          backgroundColor: _kGreen,
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barkod ile eşleşen ürün bulunamadı: $barcode'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _barcodeFocusNode.requestFocus();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Close button & compact stepper header
            Container(
              color: _kSurface,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _kText, size: 22),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Expanded(
                    child: _buildStepperHeader(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _kBorder),
            // Step Body
            Expanded(
              child: _buildStepBody(),
            ),
            const Divider(height: 1, color: _kBorder),
            // Bottom Action bar
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = [
      {'icon': Icons.person_outline_rounded},
      {'icon': Icons.grid_view_rounded},
      {'icon': Icons.shopping_basket_outlined},
      {'icon': Icons.payments_outlined},
    ];

    return Container(
      color: _kSurface,
      padding: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final step = entry.value;
          final isCompleted = idx < _activeStep;
          final isCurrent = idx == _activeStep;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Step Bubble
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCurrent ? _kGreen : (isCompleted ? _kGreenLight : Colors.white),
                  shape: BoxShape.circle,
                  border: Border.all(color: isCurrent || isCompleted ? _kGreen : _kBorder),
                ),
                child: Icon(
                  isCompleted ? Icons.check_circle_rounded : (step['icon'] as IconData),
                  size: 16,
                  color: isCurrent ? Colors.white : (isCompleted ? _kGreenDark : _kTextSecondary),
                ),
              ),
              if (idx < 3)
                Container(
                  width: 20,
                  height: 2,
                  color: isCompleted ? _kGreen : _kBorder,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_activeStep) {
      case 0:
        return _buildCustomerStep();
      case 1:
        return _buildProductStep();
      case 2:
        return _buildCartStep();
      case 3:
        return _buildCheckoutStep();
      default:
        return const SizedBox.shrink();
    }
  }

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
                              onPressed: () => setState(() => _customerQuery = ''),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) => setState(() => _customerQuery = val),
                  );

                  final addBtn = ElevatedButton.icon(
                    onPressed: () => setState(() {
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
                            onTap: () => setState(() => _selectedCustomer = c),
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
                    onPressed: () => setState(() => _isAddingCustomer = false),
                    icon: const Icon(Icons.arrow_back_rounded, color: _kTextSecondary),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Yeni Müşteri Ekle',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kText),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newCustNameController,
                decoration: InputDecoration(
                  labelText: 'Müşteri Adı / Unvan *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Müşteri adı zorunludur' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newCustPhoneController,
                decoration: InputDecoration(
                  labelText: 'Telefon Numarası',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newCustBalanceController,
                decoration: InputDecoration(
                  labelText: 'Devreden Bakiye (Pozitif Alacak, Negatif Borç)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                  helperText: 'Eğer müşterinin önceden borcu varsa negatif (-100 vb.) girin.',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _isAddingCustomer = false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSavingCustomer ? null : _saveCustomerInline,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    child: _isSavingCustomer
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Kaydet ve Seç', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveCustomerInline() async {
    if (!(_addCustomerFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isSavingCustomer = true);

    try {
      final name = _newCustNameController.text.trim();
      final phone = _newCustPhoneController.text.trim();
      final balance = double.tryParse(_newCustBalanceController.text.trim().replaceAll(',', '.')) ?? 0.0;

      final newCust = CustomerEntity(
        id: const Uuid().v4(),
        name: name,
        phone: phone,
        email: '',
        balance: balance,
        createdAt: DateTime.now(),
      );

      await ref.read(customersControllerProvider.notifier).addCustomer(newCust);
      await ref.read(customersControllerProvider.notifier).refresh();

      // Find the newly added customer in the reloaded list to have matching object reference if needed
      final updatedList = ref.read(customersControllerProvider).value ?? [];
      final createdCust = updatedList.firstWhere((c) => c.id == newCust.id, orElse: () => newCust);

      setState(() {
        _selectedCustomer = createdCust;
        _isAddingCustomer = false;
        _isSavingCustomer = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newCust.name} eklendi ve seçildi.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSavingCustomer = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Müşteri eklenirken hata oluştu: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showCategoryBottomSheet(BuildContext context, List<String> categories) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kategori Filtrele',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildCategoryModalChip(
                        ctx,
                        label: 'Tümü',
                        isSelected: _selectedCategory == 'Tümü',
                        onTap: () {
                          setState(() => _selectedCategory = 'Tümü');
                          ref.read(ordersProductCategoryFilterProvider.notifier).state = null;
                          Navigator.pop(ctx);
                        },
                      ),
                      ...categories.map((cat) {
                        return _buildCategoryModalChip(
                          ctx,
                          label: cat,
                          isSelected: _selectedCategory == cat,
                          onTap: () {
                            setState(() => _selectedCategory = cat);
                            ref.read(ordersProductCategoryFilterProvider.notifier).state = cat;
                            Navigator.pop(ctx);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryModalChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _kGreen : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kGreen : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF475569),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildProductStep() {
    final productsVal = ref.watch(productsControllerProvider);
    final categories = ref.watch(productCategoriesProvider);

    return productsVal.when(
      loading: () => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kGreen))),
      error: (err, _) => Center(child: Text('Ürünler yüklenemedi: $err', style: const TextStyle(color: _kRed))),
      data: (productsList) {
        final filtered = productsList;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Search & Category toggle filter bar (like Sales screen catalog)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    if (_isProductSearching) ...[
                      Expanded(
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _productSearchController,
                            decoration: const InputDecoration(
                              hintText: 'Ürün ara...',
                              hintStyle: TextStyle(color: _kTextSecondary, fontSize: 13),
                              prefixIcon: Icon(Icons.search_rounded, color: _kTextSecondary, size: 18),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                            ),
                            style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
                            onChanged: (val) {
                              setState(() => _productQuery = val);
                              ref.read(productSearchQueryProvider.notifier).state = val;
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: _kRed),
                        onPressed: () {
                          setState(() {
                            _isProductSearching = false;
                            _productQuery = '';
                            _productSearchController.clear();
                          });
                          ref.read(productSearchQueryProvider.notifier).state = '';
                        },
                      ),
                    ] else ...[
                      IconButton(
                        icon: const Icon(Icons.search_rounded, color: _kGreen),
                        tooltip: 'Ara',
                        onPressed: () {
                          setState(() {
                            _isProductSearching = true;
                          });
                        },
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => _showCategoryBottomSheet(context, categories),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9), // Slate 100
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.filter_list_rounded, size: 16, color: _kGreenDark),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _selectedCategory == 'Tümü'
                                        ? 'Kategori: Tümü'
                                        : 'Kategori: $_selectedCategory',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _kText,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _kTextSecondary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    // Photo Camera scanner
                    IconButton(
                      onPressed: () {
                        BarcodeScannerDialog.show(
                          context,
                          onBarcodeScanned: (code) {
                            _handleBarcodeSubmit(code, productsList);
                          },
                        );
                      },
                      icon: const Icon(Icons.photo_camera_rounded, color: _kGreen),
                      tooltip: 'Kamera Tarayıcı',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _kBorder),
              const SizedBox(height: 12),
              // Grid View
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text(
                              'Eşleşen ürün bulunamadı.',
                              style: TextStyle(color: _kTextSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: _productScrollController,
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final p = filtered[idx];
                          final qtyInCart = _cart[p] ?? 0;
                          final outOfStock = p.quantity <= 0; // Allowed negative stock sales
                          final isLowStock = p.quantity <= 5;
                          final Color badgeBgColor = outOfStock
                              ? _kRedLight
                              : (isLowStock ? _kAmberLight : _kGreenLight);
                          final Color badgeTextColor = outOfStock
                              ? _kRed
                              : (isLowStock ? const Color(0xFF854D0E) : _kGreenDark);
                          final Color borderColor = qtyInCart > 0
                              ? _kGreen
                              : (outOfStock
                                  ? _kRed.withValues(alpha: 0.25)
                                  : (isLowStock ? _kAmber.withValues(alpha: 0.35) : _kBorder));

                          return AnimatedOpacity(
                            opacity: outOfStock ? 0.85 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: borderColor,
                                  width: qtyInCart > 0 ? 2.0 : ((outOfStock || isLowStock) ? 1.5 : 1.0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: qtyInCart > 0
                                        ? _kGreen.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  onTap: () => setState(() => _cart[p] = qtyInCart + 1.0),
                                  borderRadius: BorderRadius.circular(14),
                                  splashColor: _kGreenLight,
                                  highlightColor: _kGreenLight.withValues(alpha: 0.5),
                                  child: Padding(
                                    padding: const EdgeInsets.all(11),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                p.category.toUpperCase(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  color: _kTextSecondary,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.6,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: badgeBgColor,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                outOfStock
                                                    ? 'Tükendi'
                                                    : (isLowStock ? '${p.quantity} adet' : '${p.quantity}'),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: badgeTextColor,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Spacer(),
                                        Text(
                                          p.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: _kText,
                                            height: 1.25,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '₺${p.price % 1 == 0 ? p.price.toInt() : p.price.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15,
                                                  color: _kGreenDark,
                                                  letterSpacing: -0.3,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            qtyInCart == 0
                                                ? Container(
                                                    width: 32,
                                                    height: 32,
                                                    decoration: BoxDecoration(
                                                      color: _kGreen,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: const Icon(
                                                      Icons.add_rounded,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                  )
                                                : GestureDetector(
                                                    onTap: () {}, // Swallows taps on the controller container to prevent card onTap trigger
                                                    child: Container(
                                                      height: 32,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: _kGreen, width: 1.5),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          GestureDetector(
                                                            onTap: () => setState(() {
                                                              if (qtyInCart - 1.0 <= 0.0001) {
                                                                _cart.remove(p);
                                                              } else {
                                                                _cart[p] = qtyInCart - 1.0;
                                                              }
                                                            }),
                                                            child: const Padding(
                                                              padding: EdgeInsets.symmetric(horizontal: 6),
                                                              child: Icon(Icons.remove_rounded, color: _kRed, size: 14),
                                                            ),
                                                          ),
                                                          _InlineQuantityField(
                                                            quantity: qtyInCart,
                                                            hasBorder: false,
                                                            onChanged: (val) => setState(() {
                                                              if (val <= 0.0001) {
                                                                _cart.remove(p);
                                                              } else {
                                                                _cart[p] = val;
                                                              }
                                                            }),
                                                            onRemove: () => setState(() => _cart.remove(p)),
                                                          ),
                                                          GestureDetector(
                                                            onTap: () => setState(() => _cart[p] = qtyInCart + 1.0),
                                                            child: const Padding(
                                                              padding: EdgeInsets.symmetric(horizontal: 6),
                                                              child: Icon(Icons.add_rounded, color: _kGreen, size: 14),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
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

  Widget _buildCartStep() {
    if (_cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_basket_outlined, size: 72, color: Colors.grey[200]),
            const SizedBox(height: 16),
            const Text(
              'Sipariş sepetiniz boş.',
              style: TextStyle(color: _kTextSecondary, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final itemListWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sepetteki Ürünler',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kText),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _cart.length,
          itemBuilder: (context, idx) {
            final p = _cart.keys.elementAt(idx);
            final qty = _cart[p]!;
            final lineTotal = p.price * qty;

            return Card(
              color: _kSurface,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: _kBorder)),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('₺${p.price.toStringAsFixed(2)} x ${_formatQuantity(qty)} = ₺${lineTotal.toStringAsFixed(2)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              if (qty - 1.0 <= 0.0001) {
                                _cart.remove(p);
                              } else {
                                _cart[p] = qty - 1.0;
                              }
                            }),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.remove_rounded, color: _kRed, size: 16),
                            ),
                          ),
                          _InlineQuantityField(
                            quantity: qty,
                            hasBorder: false,
                            onChanged: (val) => setState(() {
                              if (val <= 0.0001) {
                                _cart.remove(p);
                              } else {
                                _cart[p] = val;
                              }
                            }),
                            onRemove: () => setState(() => _cart.remove(p)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _cart[p] = qty + 1.0),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.add_rounded, color: _kGreen, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 20),
                      onPressed: () => setState(() => _cart.remove(p)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );

    final formConfigWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Teslimat Tarihi ve Notlar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        const Text('Tahmini Teslimat Tarihi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _kTextSecondary)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _expectedDelivery,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (date != null) setState(() => _expectedDelivery = date);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: _kBorder),
              borderRadius: BorderRadius.circular(10),
              color: _kSurface,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('dd.MM.yyyy').format(_expectedDelivery), style: const TextStyle(fontWeight: FontWeight.bold)),
                const Icon(Icons.calendar_month_rounded, color: _kGreen),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Sipariş Notu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _kTextSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Sipariş notları...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Sipariş Toplamı:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('₺${_totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _kGreenDark)),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: itemListWidget),
                ),
                const VerticalDivider(width: 24, color: _kBorder),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(child: formConfigWidget),
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                itemListWidget,
                const Divider(height: 32, color: _kBorder),
                formConfigWidget,
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildCheckoutStep() {
    final isKarma = _paymentMethod == 'karma';

    final leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Sipariş Bilgileri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        _buildSummaryRow(
          icon: Icons.person_outline_rounded,
          label: 'Seçilen Müşteri',
          value: _selectedCustomer?.name ?? 'Müşteri Seçilmedi',
        ),
        if (_selectedCustomer != null)
          _buildSummaryRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Müşteri Bakiyesi',
            value: '₺${_selectedCustomer!.balance.abs().toStringAsFixed(2)} ${_selectedCustomer!.balance < 0 ? "(Borçlu)" : "(Alacaklı)"}',
            valueColor: _selectedCustomer!.balance < 0 ? _kRed : _kGreenDark,
          ),
        _buildSummaryRow(
          icon: Icons.calendar_month_outlined,
          label: 'Teslimat Tarihi',
          value: DateFormat('dd.MM.yyyy').format(_expectedDelivery),
        ),
        if (_notesController.text.trim().isNotEmpty)
          _buildSummaryRow(
            icon: Icons.notes_rounded,
            label: 'Not',
            value: _notesController.text.trim(),
          ),
      ],
    );

    final rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Ödeme Yöntemi Seçin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
        const SizedBox(height: 12),
        // Totals box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isKarma && _karmaTotal > 0)
                Text(
                  'Kalan: ₺${_karmaRemainder.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _karmaValid ? _kGreenDark : _kRed,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                const SizedBox.shrink(),
              Text(
                '₺${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: _kGreenDark,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Karma Split Input Fields (if karma selected)
        if (isKarma) ...[
          _buildKarmaFields(),
          const SizedBox(height: 12),
        ],
        // Payment button choices
        _buildPaymentSelectionGrid(),
        const SizedBox(height: 16),
        // Receipt & Label Printer Controls (Minimal Style)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Receipt printer icon button
              IconButton(
                onPressed: () => setState(() => _printReceipt = !_printReceipt),
                icon: Icon(
                  _printReceipt ? Icons.print_rounded : Icons.print_disabled_rounded,
                  color: _printReceipt ? _kGreen : _kTextSecondary,
                  size: 20,
                ),
                tooltip: _printReceipt ? 'Fiş Yazdırma Açık' : 'Fiş Yazdırma Kapalı',
                style: IconButton.styleFrom(
                  backgroundColor: _printReceipt ? _kGreenLight : Colors.white,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _printReceipt ? _kGreen.withValues(alpha: 0.3) : _kBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _InlineCopyCountField(
                value: _printCopies,
                isEnabled: _printReceipt,
                onChanged: (val) {
                  setState(() => _printCopies = val);
                },
              ),
              const SizedBox(width: 24),
              // Label printer icon button
              IconButton(
                onPressed: () {
                  setState(() => _printLabel = !_printLabel);
                  _saveLabelPrinterSettings();
                },
                icon: Icon(
                  _printLabel ? Icons.label_rounded : Icons.label_outline_rounded,
                  color: _printLabel ? _kGreen : _kTextSecondary,
                  size: 20,
                ),
                tooltip: _printLabel ? 'Etiket Yazıcı Açık' : 'Etiket Yazıcı Kapalı',
                style: IconButton.styleFrom(
                  backgroundColor: _printLabel ? _kGreenLight : Colors.white,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _printLabel ? _kGreen.withValues(alpha: 0.3) : _kBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _InlineCopyCountField(
                value: _labelCopies,
                isEnabled: _printLabel,
                onChanged: (val) {
                  setState(() => _labelCopies = val);
                  _saveLabelPrinterSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: leftCol),
                ),
                const VerticalDivider(width: 24, color: _kBorder),
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: rightCol),
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                leftCol,
                const Divider(height: 32, color: _kBorder),
                rightCol,
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSummaryRow({required IconData icon, required String label, required String value, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _kTextSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 12))),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor ?? _kText)),
        ],
      ),
    );
  }

  Widget _buildKarmaFields() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _karmaValid ? _kGreen.withValues(alpha: 0.4) : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split_rounded, size: 14, color: _kTextSecondary),
              const SizedBox(width: 6),
              const Text('Karma Ödeme Dağılımı', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_karmaValid)
                const Text('✓ Tamam', style: TextStyle(fontSize: 11, color: _kGreenDark, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildSplitField(
                  controller: _cashSplitController,
                  label: 'Nakit',
                  icon: Icons.payments_rounded,
                  color: _kGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSplitField(
                  controller: _cardSplitController,
                  label: 'Kart',
                  icon: Icons.credit_card_rounded,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSplitField(
                  controller: _debtSplitController,
                  label: 'Vadeli',
                  icon: Icons.account_balance_wallet_rounded,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSplitField({required TextEditingController controller, required String label, required IconData icon, required Color color}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
        prefixIcon: Icon(icon, color: color, size: 16),
        prefixText: '₺',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildPaymentSelectionGrid() {
    final methods = [
      {'id': 'cash', 'label': 'Nakit', 'icon': Icons.payments_rounded, 'color': _kGreen},
      {'id': 'card', 'label': 'Kart', 'icon': Icons.credit_card_rounded, 'color': Colors.blue},
      {'id': 'debt', 'label': 'Vadeli (Borç)', 'icon': Icons.account_balance_wallet_rounded, 'color': Colors.orange},
      {'id': 'karma', 'label': 'Karma (Split)', 'icon': Icons.call_split_rounded, 'color': Colors.purple},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double aspectRatio = constraints.maxWidth > 400 ? 2.4 : 3.0;

        return GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: aspectRatio,
          physics: const NeverScrollableScrollPhysics(),
          children: methods.map((m) {
            final isSel = _paymentMethod == m['id'];
            final color = m['color'] as Color;

            return InkWell(
              onTap: () {
                setState(() {
                  _paymentMethod = m['id'] as String;
                  if (_paymentMethod == 'cash' || _paymentMethod == 'card') {
                    _paidAmount = _totalAmount;
                  } else if (_paymentMethod == 'debt') {
                    _paidAmount = 0.0;
                  } else if (_paymentMethod == 'karma') {
                    _cashSplitController.clear();
                    _cardSplitController.clear();
                    _debtSplitController.clear();
                  }
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSel ? color : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSel ? color : _kBorder),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      m['icon'] as IconData,
                      color: isSel ? Colors.white : color,
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m['label'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isSel ? Colors.white : _kText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBottomActionBar() {
    final nextDisabled = _isNextDisabled();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          _activeStep > 0
              ? OutlinedButton.icon(
                  onPressed: _prevStep,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Geri'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                )
              : OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  child: const Text('Kapat'),
                ),
          // Next / Confirm button
          _activeStep < 3
              ? ElevatedButton.icon(
                  onPressed: nextDisabled ? null : _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Devam Et', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : ElevatedButton.icon(
                  onPressed: _isSubmitting || _paymentMethod.isEmpty || (_paymentMethod == 'karma' && !_karmaValid)
                      ? null
                      : _submitOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(widget.existingOrder != null ? 'Siparişi Güncelle' : 'Siparişi Onayla', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
        ],
      ),
    );
  }

  bool _isNextDisabled() {
    if (_activeStep == 0) return _selectedCustomer == null || _isAddingCustomer;
    if (_activeStep == 1) return _cart.isEmpty;
    return false;
  }

  Future<void> _submitOrder() async {
    setState(() => _isSubmitting = true);

    try {
      final itemsList = _cart.entries.map((e) => {
        'product_id': e.key.id,
        'quantity': e.value,
        'unit_price': e.key.price,
        'tax': e.key.vat ?? 0.0,
        'total_price': e.value * e.key.price,
      }).toList();

      final isEdit = widget.existingOrder != null;
      final String orderId = isEdit
          ? widget.existingOrder!.id
          : 'ord-${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(10000).toString().padLeft(4, '0')}';

      final currentUser = ref.read(currentUserProvider);
      final cashierName = currentUser?.name ?? 'Kasiyer';

      final newOrder = OrderEntity(
        id: orderId,
        customerId: _selectedCustomer!.id,
        status: isEdit ? widget.existingOrder!.status : 'created',
        createdAt: isEdit ? widget.existingOrder!.createdAt : DateTime.now(),
        expectedDeliveryDate: _expectedDelivery,
        actualDeliveryDate: isEdit ? widget.existingOrder!.actualDeliveryDate : null,
        items: itemsList,
        notes: _notesController.text.trim(),
        createdBy: isEdit ? widget.existingOrder!.createdBy : cashierName,
      );

      // Process customer balance ledger
      double finalPaid = _totalAmount;
      if (_paymentMethod == 'debt') {
        finalPaid = 0.0;
      } else if (_paymentMethod == 'karma') {
        finalPaid = _karmaCash + _karmaCard;
      }
      final newDebt = _totalAmount - finalPaid;

      if (isEdit) {
        // Save Order to Local Database
        await ref.read(ordersControllerProvider.notifier).updateOrder(newOrder);

        // Find existing transaction to calculate oldDebt
        final txRepo = await ref.read(financialTransactionRepositoryProvider.future);
        final transactions = await txRepo.getByCustomerId(widget.existingOrder!.customerId);
        FinancialTransactionEntity? orderTx;
        for (final t in transactions) {
          if (t.referenceId == widget.existingOrder!.id && t.type == 'sale') {
            orderTx = t;
            break;
          }
        }

        double oldDebt = 0.0;
        if (orderTx != null) {
          oldDebt = orderTx.debtAmount;
        }

        final customerRepo = await ref.read(customerRepositoryProvider.future);
        if (_selectedCustomer!.id == widget.existingOrder!.customerId) {
          final balanceAdjustment = oldDebt - newDebt;
          if (balanceAdjustment != 0) {
            await customerRepo.updateBalance(_selectedCustomer!.id, balanceAdjustment);
          }
        } else {
          // Customer changed: refund old, charge new
          if (oldDebt > 0) {
            await customerRepo.updateBalance(widget.existingOrder!.customerId, oldDebt);
          }
          if (newDebt > 0) {
            await customerRepo.updateBalance(_selectedCustomer!.id, -newDebt);
          }
        }

        // Update transaction row
        if (orderTx != null) {
          final updatedTx = FinancialTransactionEntity(
            id: orderTx.id,
            type: 'sale',
            customerId: _selectedCustomer!.id,
            amount: _totalAmount,
            paidAmount: finalPaid,
            debtAmount: newDebt,
            date: orderTx.date,
            referenceId: widget.existingOrder!.id,
            metadata: orderTx.metadata,
          );
          await txRepo.update(updatedTx);
        } else {
          final transactionId = 'trans-${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(10000).toString().padLeft(4, '0')}';
          await txRepo.create(
            FinancialTransactionEntity(
              id: transactionId,
              type: 'sale',
              customerId: _selectedCustomer!.id,
              amount: _totalAmount,
              paidAmount: finalPaid,
              debtAmount: newDebt,
              date: DateTime.now(),
              referenceId: widget.existingOrder!.id,
            ),
          );
        }
      } else {
        // Save Order to Local Database
        await ref.read(ordersControllerProvider.notifier).addOrder(newOrder);

        final paymentService = await ref.read(paymentServiceProvider.future);
        await paymentService.processSalePayment(
          saleId: newOrder.id,
          customerId: _selectedCustomer!.id,
          totalAmount: _totalAmount,
          paidAmount: finalPaid,
          paymentMethod: _paymentMethod,
        );
      }

      // Refresh customers state so updated balance displays on screens
      await ref.read(customersControllerProvider.notifier).refresh();
      ref.invalidate(customerTransactionsProvider(_selectedCustomer!.id));
      ref.invalidate(customerBalanceDetailsProvider(_selectedCustomer!.id));
      if (isEdit && _selectedCustomer!.id != widget.existingOrder!.customerId) {
        ref.invalidate(customerTransactionsProvider(widget.existingOrder!.customerId));
        ref.invalidate(customerBalanceDetailsProvider(widget.existingOrder!.customerId));
      }

      // Print order receipt & labels
      final settings = ref.read(settingsNotifierProvider).value;
      if (settings != null) {
        final receiptItems = _cart.entries.map((e) => {
          'product_id': e.key.name,
          'quantity': e.value,
          'unit_price': e.key.price,
        }).toList();

        // 1. Print main receipt copies
        if (_printReceipt) {
          for (int i = 0; i < _printCopies; i++) {
            final suffix = _printCopies > 1 ? ' (Kopya ${i + 1})' : '';
            ref.read(printerServiceProvider).enqueue(
              'Sipariş Fişi #${newOrder.id.toShortId}$suffix',
              () => ref.read(printerServiceProvider).printOrderReceipt(
                newOrder,
                receiptItems,
                _selectedCustomer,
                settings,
                paidAmount: finalPaid,
                notes: _notesController.text.trim(),
              ),
            );
          }
        }

        // 2. Print label stickers if label printer toggle is enabled
        if (_printLabel) {
          final prefs = await SharedPreferences.getInstance();
          final labelIp = prefs.getString('label_printer_ip') ?? '';
          final labelPort = int.tryParse(prefs.getString('label_printer_port') ?? '9100') ?? 9100;
          final labelSettings = settings.copyWith(
            printerIp: labelIp.isNotEmpty ? labelIp : settings.printerIp,
            printerPort: labelPort,
          );

          for (int i = 0; i < _labelCopies; i++) {
            final suffix = _labelCopies > 1 ? ' (Kopya ${i + 1})' : '';
            ref.read(printerServiceProvider).enqueue(
              'Sipariş Etiketleri #${newOrder.id.toShortId}$suffix',
              () => ref.read(printerServiceProvider).printOrderLabels(
                newOrder,
                receiptItems,
                labelSettings,
              ),
            );
          }
        }
      }

      ref.invalidate(dashboardProvider);
      ref.invalidate(productsControllerProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Sipariş başarıyla güncellendi.' : 'Sipariş başarıyla oluşturuldu.'),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sipariş kaydedilirken hata: $e'), backgroundColor: _kRed),
        );
      }
    }
  }
}

String _formatQuantity(double qty) {
  if (qty == qty.toInt()) {
    return qty.toInt().toString();
  }
  return qty.toString();
}

class _InlineQuantityField extends StatefulWidget {
  final double quantity;
  final ValueChanged<double> onChanged;
  final VoidCallback? onRemove;
  final bool hasBorder;
  const _InlineQuantityField({
    required this.quantity,
    required this.onChanged,
    this.onRemove,
    this.hasBorder = true,
  });

  @override
  State<_InlineQuantityField> createState() => _InlineQuantityFieldState();
}

class _InlineQuantityFieldState extends State<_InlineQuantityField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatQuantity(widget.quantity));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_InlineQuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity && !_focusNode.hasFocus) {
      _controller.text = _formatQuantity(widget.quantity);
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _submitValue();
    }
  }

  void _submitValue() {
    final text = _controller.text.replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null) {
      if (val <= 0.0001) {
        if (widget.onRemove != null) {
          widget.onRemove!();
        } else {
          widget.onChanged(0.0);
        }
      } else {
        widget.onChanged(val);
      }
    } else {
      _controller.text = _formatQuantity(widget.quantity);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: widget.hasBorder ? Border.all(color: _kBorder) : null,
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _kText),
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
        ],
        onSubmitted: (_) {
          _submitValue();
          _focusNode.unfocus();
        },
      ),
    );
  }
}

class _InlineCopyCountField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool isEnabled;

  const _InlineCopyCountField({
    required this.value,
    required this.onChanged,
    this.isEnabled = true,
  });

  @override
  State<_InlineCopyCountField> createState() => _InlineCopyCountFieldState();
}

class _InlineCopyCountFieldState extends State<_InlineCopyCountField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_InlineCopyCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value.toString();
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _submitValue();
    }
  }

  void _submitValue() {
    final val = int.tryParse(_controller.text);
    if (val != null && val >= 1) {
      widget.onChanged(val);
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color bgColor = widget.isEnabled 
        ? Colors.white 
        : (isDark ? Colors.black26 : Colors.grey.shade100);
        
    final Color borderColor = widget.isEnabled 
        ? _kBorder 
        : (isDark ? Colors.white24 : Colors.grey.shade300);
        
    final Color textColor = widget.isEnabled 
        ? _kText 
        : _kTextSecondary.withValues(alpha: 0.5);

    return Container(
      width: 36,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.isEnabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onSubmitted: (_) {
          _submitValue();
          _focusNode.unfocus();
        },
      ),
    );
  }
}