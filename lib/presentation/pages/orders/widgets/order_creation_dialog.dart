// lib/presentation/pages/orders/widgets/order_creation_dialog.dart
import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/math_engine.dart';
import 'package:serenutos/domain/services/mixed_payment_calculator.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/domain/services/inventory_service.dart'
    show SaleItemInput;
import 'package:serenutos/presentation/controllers/sales_controller.dart'
    show paymentServiceProvider, inventoryServiceProvider;
import 'package:serenutos/presentation/widgets/sales/barcode_scanner_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/payment_terminal_provider.dart';
import 'package:serenutos/providers/hardware_config_provider.dart';
import 'package:serenutos/presentation/widgets/sales/checkout/cash_dialog.dart';
import 'package:serenutos/presentation/widgets/karma_payment_summary_bar.dart';
import 'package:serenutos/presentation/widgets/discount_dialog.dart';
import 'package:serenutos/presentation/widgets/sales/product_filter_sort_dialog.dart';
import 'package:serenutos/presentation/widgets/common/customer_picker_widget.dart';
import 'package:serenutos/presentation/mixins/barcode_scanner_mixin.dart';

part 'steps/step_customer.dart';
part 'steps/step_product_selection.dart';
part 'steps/step_cart.dart';
part 'steps/step_checkout.dart';
part 'steps/step_stepper_header.dart';
part 'steps/step_bottom_bar.dart';
part 'steps/step_shared_widgets.dart';

// Color and layout constants
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber = Color(0xFFEAB308);
const _kAmberLight = Color(0xFFFEF9C3);
const _kOrange = Color(0xFFEA580C);
const _kRed = Color(0xFFDC2626);
const _kRedLight = Color(0xFFFEE2E2);
const _kSurface = POSColors.surface;
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

class OrderCreationDialog extends ConsumerStatefulWidget {
  final OrderEntity? existingOrder;
  const OrderCreationDialog({super.key, this.existingOrder});

  /// Opens the OrderCreationDialog as a centered modal dialog on desktop
  /// or full-screen on mobile devices.
  static Future<T?> show<T>(BuildContext context, {OrderEntity? existingOrder}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    if (isDesktop) {
      return showDialog<T>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 920,
              maxHeight: 820,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: OrderCreationDialog(existingOrder: existingOrder),
            ),
          ),
        ),
      );
    } else {
      return Navigator.push<T>(
        context,
        MaterialPageRoute(
          builder: (context) => OrderCreationDialog(existingOrder: existingOrder),
          fullscreenDialog: true,
        ),
      );
    }
  }

  @override
  ConsumerState<OrderCreationDialog> createState() =>
      OrderCreationDialogState();
}

class OrderCreationDialogState extends ConsumerState<OrderCreationDialog>
    with BarcodeScannerMixin<OrderCreationDialog> {
  int _activeStep = 0;


  // Step 1: Customer Selection
  CustomerEntity? _selectedCustomer;


  // Step 2: Product Catalog
  final Map<ProductEntity, double> _cart = {};
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _isProductSearching = false;
  final _productSearchController = TextEditingController();
  final _productSearchFocusNode = FocusNode();
  final ScrollController _productScrollController = ScrollController();

  // Step 3: Cart Review
  DateTime _expectedDelivery = DateTime.now().add(const Duration(days: 1));
  final _notesController = TextEditingController();

  // Step 4: Checkout
  String _paymentMethod = '';
  final GlobalKey _karmaFieldsKey = GlobalKey();
  final TextEditingController _givenCashController = TextEditingController();
  final TextEditingController _cashSplitController = TextEditingController();
  final TextEditingController _cardSplitController = TextEditingController();
  final TextEditingController _debtSplitController = TextEditingController();
  bool _printReceipt = true;
  int _printCopies = 1;
  bool _printLabel = false;
  int _labelCopies = 1;
  bool _isSubmitting = false;
  double _discountAmount = 0.0;

  void updateState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _productScrollController.addListener(_onProductScroll);
    initBarcodeScanner();

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

  @override
  bool canHandleBarcodeScan() {
    if (!super.canHandleBarcodeScan()) return false;
    if (_activeStep != 1) return false;
    if (_productSearchFocusNode.hasFocus) return false;
    return true;
  }

  @override
  void onBarcodeScanned(String barcode) {

    _productSearchController.clear();
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
      _discountAmount = order.discountAmount;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        CustomerEntity? cust;
        if (order.customerId.isNotEmpty) {
          try {
            final repo = await ref.read(customerRepositoryProvider.future);
            cust = await repo.findById(order.customerId);
          } catch (_) {}
        }
        if (cust == null) {
          final customers = ref.read(ordersCustomersControllerProvider).value;
          cust = customers?.where((c) => c.id == order.customerId).firstOrNull;
        }
        if (mounted && cust != null) {
          setState(() {
            _selectedCustomer = cust;
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
      final transactions = await repo.getByReferenceId(order.id);
      FinancialTransactionEntity? orderTx = transactions
          .where((t) => t.type == 'sale')
          .firstOrNull;

      // Fallback if not found by referenceId
      if (orderTx == null && order.customerId.isNotEmpty) {
        final custTransactions = await repo.getByCustomerId(order.customerId);
        orderTx = custTransactions
            .where((t) => t.referenceId == order.id && t.type == 'sale')
            .firstOrNull;
      }
      if (orderTx != null) {
        setState(() {
          final total = orderTx!.amount;
          final paid = orderTx.paidAmount;
          final debt = orderTx.debtAmount;
          if (paid == total) {
            _paymentMethod = 'cash';
          } else if (paid == 0) {
            _paymentMethod = 'debt';
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
    if (_productScrollController.hasClients &&
        _productScrollController.position.pixels >=
            _productScrollController.position.maxScrollExtent - 400) {
      ref.read(ordersProductsControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  void dispose() {
    _productScrollController.dispose();
    disposeBarcodeScanner();

    _notesController.dispose();

    _cashSplitController.dispose();
    _cardSplitController.dispose();
    _debtSplitController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _productSearchController.dispose();
    _productSearchFocusNode.dispose();
    super.dispose();
  }

  double get _subtotalAmount => MathEngine.calculateCartTotal(_cart);
  double get _totalAmount => max(0.0, _subtotalAmount - _discountAmount);

  // Karma split fields getters
  double get _karmaCash =>
      double.tryParse(_cashSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaCard =>
      double.tryParse(_cardSplitController.text.replaceAll(',', '.')) ?? 0.0;
  double get _karmaDebt => _selectedCustomer != null
      ? (double.tryParse(_debtSplitController.text.replaceAll(',', '.')) ?? 0.0)
      : 0.0;

  MixedPaymentResult get _karmaResult => MixedPaymentCalculator.calculate(
        total: _totalAmount,
        cashTendered: _karmaCash,
        card: _karmaCard,
        debt: _karmaDebt,
      );
  double get _karmaRemainder => _karmaResult.remaining;
  bool get _karmaValid => _karmaResult.isValid;

  Future<void> _pickDeliveryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDelivery,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Teslimat Tarihi SeÃ§in',
      confirmText: 'SeÃ§',
      cancelText: 'Ä°ptal',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kGreen,
              onPrimary: Colors.white,
              onSurface: _kText,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      updateState(() {
        _expectedDelivery = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _expectedDelivery.hour,
          _expectedDelivery.minute,
        );
      });
    }
  }

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

  void _showNotification(String message,
      {bool isError = false,
      Duration duration = const Duration(milliseconds: 1800)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _kRed : _kGreenDark,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 84, left: 24, right: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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

    if (!mounted) return;

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
      _showNotification('${matched.name} sipariÅŸe eklendi.');
    } else {
      _showNotification('Barkod ile eÅŸleÅŸen Ã¼rÃ¼n bulunamadÄ±: $barcode',
          isError: true);
      _barcodeFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 960;
        final Widget innerScaffold = Scaffold(
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
                        child: buildStepperHeader(),
                      ),

                    ],
                  ),
                ),
                const Divider(height: 1, color: _kBorder),
                // Step Body
                Expanded(
                  child: buildStepBody(),
                ),

              ],
            ),
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            child: SafeArea(
              top: false,
              child: buildBottomActionBar(),
            ),
          ),
        );

        if (isWide) {
          return Scaffold(
            backgroundColor: Colors.black.withValues(alpha: 0.45),
            body: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: innerScaffold,
              ),
            ),
          );
        }

        return innerScaffold;
      },
    );
  }
}
