// lib/presentation/pages/orders/widgets/order_creation_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'dart:async';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/math_engine.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart'
    show paymentServiceProvider;
import 'package:serenutos/presentation/widgets/sales/barcode_scanner_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

part 'steps/step_customer.dart';
part 'steps/step_product_selection.dart';
part 'steps/step_cart_summary.dart';
part 'steps/step_checkout.dart';

// Color and layout constants
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kAmberDark = Color(0xFFB45309);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

class OrderCreationDialog extends ConsumerStatefulWidget {
  final OrderEntity? existingOrder;
  const OrderCreationDialog({super.key, this.existingOrder});

  @override
  ConsumerState<OrderCreationDialog> createState() =>
      OrderCreationDialogState();
}

class OrderCreationDialogState extends ConsumerState<OrderCreationDialog> {
  int _activeStep = 0;

  // Step 1: Customer Selection
  CustomerEntity? _selectedCustomer;
  String _customerQuery = '';
  Timer? _customerSearchDebounce;
  final ScrollController _customerScrollController = ScrollController();
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

  void _onCustomerScroll() {
    if (_customerScrollController.position.pixels >=
        _customerScrollController.position.maxScrollExtent - 200) {
      ref.read(ordersCustomersControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  void initState() {
    super.initState();
    _productScrollController.addListener(_onProductScroll);
    _customerScrollController.addListener(_onCustomerScroll);
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
      ref.read(ordersCustomerSearchQueryProvider.notifier).state = '';
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
      _expectedDelivery = order.expectedDeliveryDate ??
          DateTime.now().add(const Duration(days: 1));

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final customers = ref.read(ordersCustomersControllerProvider).value;
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
      final repo =
          await ref.read(financialTransactionRepositoryProvider.future);
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
      // Read label printer settings from SQLite settings (single source of truth)
      final settings = ref.read(settingsNotifierProvider).valueOrNull;
      if (settings != null && mounted) {
        setState(() {
          _printLabel = settings.labelPrinterEnabled;
          _labelCopies = settings.labelPrinterCopies;
        });
      }
    } catch (e) {
      debugPrint('Error loading label printer settings: $e');
    }
  }

  Future<void> _saveLabelPrinterSettings() async {
    try {
      // Write label printer settings to SQLite settings (single source of truth)
      final current = ref.read(settingsNotifierProvider).valueOrNull;
      if (current != null) {
        await ref
            .read(settingsNotifierProvider.notifier)
            .updateSettings(current.copyWith(
              labelPrinterEnabled: _printLabel,
              labelPrinterCopies: _labelCopies,
            ));
      }
    } catch (e) {
      debugPrint('Error saving label printer settings: $e');
    }
  }

  void _onProductScroll() {
    if (_productScrollController.position.pixels >=
        _productScrollController.position.maxScrollExtent - 200) {
      ref.read(productsControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  void dispose() {
    _productScrollController.dispose();
    _customerScrollController.dispose();
    _customerSearchDebounce?.cancel();
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

  double get _totalAmount => MathEngine.calculateCartTotal(_cart);

  // Karma split fields getters
  double get _karmaCash =>
      double.tryParse(_cashSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaCard =>
      double.tryParse(_cardSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaDebt => _selectedCustomer != null
      ? (double.tryParse(_debtSplitController.text.replaceAll(',', '.')) ?? 0.0)
      : 0.0;

  double get _karmaTotal =>
      MathEngine.calculateSplitTotal(_karmaCash, _karmaCard, _karmaDebt);
  double get _karmaRemainder =>
      (_totalAmount - _karmaTotal).clamp(0.0, double.infinity);
  bool get _karmaValid =>
      _totalAmount > 0 && MathEngine.areEqual(_karmaTotal, _totalAmount);

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

  Future<void> _handleBarcodeSubmit(
      String barcode, List<ProductEntity> productsList) async {
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
                    icon: const Icon(Icons.close_rounded,
                        color: _kText, size: 22),
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
                  color: isCurrent
                      ? _kGreen
                      : (isCompleted ? _kGreenLight : Colors.white),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isCurrent || isCompleted ? _kGreen : _kBorder),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : (step['icon'] as IconData),
                  size: 16,
                  color: isCurrent
                      ? Colors.white
                      : (isCompleted ? _kGreenDark : _kTextSecondary),
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

  Widget _buildSummaryRow(
      {required IconData icon,
      required String label,
      required String value,
      Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _kTextSecondary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: _kTextSecondary, fontSize: 12))),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: valueColor ?? _kText)),
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
        border: Border.all(
            color: _karmaValid ? _kGreen.withValues(alpha: 0.4) : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split_rounded,
                  size: 14, color: _kTextSecondary),
              const SizedBox(width: 6),
              const Text('Karma Ödeme Dağılımı',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_karmaValid)
                const Text('✓ Tamam',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kGreenDark,
                        fontWeight: FontWeight.bold)),
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

  Widget _buildSplitField(
      {required TextEditingController controller,
      required String label,
      required IconData icon,
      required Color color}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
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
      {
        'id': 'cash',
        'label': 'Nakit',
        'icon': Icons.payments_rounded,
        'color': _kGreen
      },
      {
        'id': 'card',
        'label': 'Kart',
        'icon': Icons.credit_card_rounded,
        'color': Colors.blue
      },
      {
        'id': 'debt',
        'label': 'Vadeli (Borç)',
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.orange
      },
      {
        'id': 'karma',
        'label': 'Karma (Split)',
        'icon': Icons.call_split_rounded,
        'color': Colors.purple
      },
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                )
              : OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Devam Et',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : ElevatedButton.icon(
                  onPressed: _isSubmitting ||
                          _paymentMethod.isEmpty ||
                          (_paymentMethod == 'karma' && !_karmaValid)
                      ? null
                      : _submitOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(
                      widget.existingOrder != null
                          ? 'Siparişi Güncelle'
                          : 'Siparişi Onayla',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
      final itemsList = _cart.entries
          .map((e) => {
                'product_id': e.key.id,
                'quantity': e.value,
                'unit_price': e.key.price,
                'tax': e.key.vat ?? 0.0,
                'total_price': e.value * e.key.price,
              })
          .toList();

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
        actualDeliveryDate:
            isEdit ? widget.existingOrder!.actualDeliveryDate : null,
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
      if (isEdit) {
        // Save Order to Local Database
        await ref.read(ordersControllerProvider.notifier).updateOrder(newOrder);

        final paymentService = await ref.read(paymentServiceProvider.future);
        await paymentService.reviseOrderPayment(
          orderId: widget.existingOrder!.id,
          oldCustomerId: widget.existingOrder!.customerId,
          newCustomerId: _selectedCustomer!.id,
          totalAmount: _totalAmount,
          paidAmount: finalPaid,
        );
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
      await ref.read(ordersCustomersControllerProvider.notifier).refresh();
      ref.invalidate(customerTransactionsProvider(_selectedCustomer!.id));
      ref.invalidate(customerBalanceDetailsProvider(_selectedCustomer!.id));
      if (isEdit && _selectedCustomer!.id != widget.existingOrder!.customerId) {
        ref.invalidate(
            customerTransactionsProvider(widget.existingOrder!.customerId));
        ref.invalidate(
            customerBalanceDetailsProvider(widget.existingOrder!.customerId));
      }

      // Print order receipt & labels
      final settings = ref.read(settingsNotifierProvider).value;
      if (settings != null) {
        final receiptItems = _cart.entries
            .map((e) => {
                  'product_id': e.key.name,
                  'quantity': e.value,
                  'unit_price': e.key.price,
                })
            .toList();

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
          // Read label printer config from SQLite settings (single source of truth)
          final labelIp = settings.labelPrinterIp ?? '';
          final labelPort = settings.labelPrinterPort ?? 9100;
          final labelSettings = settings.copyWith(
            printerName: 'network',
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
            content: Text(isEdit
                ? 'Sipariş başarıyla güncellendi.'
                : 'Sipariş başarıyla oluşturuldu.'),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Sipariş kaydedilirken hata: $e'),
              backgroundColor: _kRed),
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
        style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 13, color: _kText),
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

    final Color textColor =
        widget.isEnabled ? _kText : _kTextSecondary.withValues(alpha: 0.5);

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
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
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
