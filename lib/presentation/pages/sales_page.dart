// lib/presentation/pages/sales_page.dart
// Serenut POS — Satış Sayfası / POS Sepet Ekranı
// Yeşil + Sarı + Premium POS Teması
// Revized: 22 Jun 2026 (Modularized)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sales_service.dart' show SaleItemInput;
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/widgets/sales/catalog_panel.dart';
import 'package:serenutos/presentation/widgets/app_shell.dart';
import 'package:serenutos/presentation/widgets/sales/cart_panel.dart';
import 'package:serenutos/presentation/widgets/sales/checkout_section.dart';
import 'package:serenutos/config/utils.dart';


const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kRed = Color(0xFFDC2626);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);


class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  SaleEntity? _lastCompletedSale;
  bool _showSuccessNotification = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _paidController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  String _barcodeBuffer = '';
  DateTime? _lastBufferTime;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _searchController.dispose();
    _paidController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final activeIndex = ref.read(activeShellIndexProvider);
    if (activeIndex != 1) return false;

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter || 
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;

    // Consume both KeyDown and KeyUp events for Enter to prevent focus activation triggers.
    if (isEnter) {
      if (_barcodeBuffer.length >= 3) {
        if (event is KeyDownEvent) {
          final code = _barcodeBuffer;
          _barcodeBuffer = '';
          _onBarcodeScanned(code);
        }
        return true; // Swallow all Enter events (down/up) when barcode is scanned
      }
      if (event is KeyDownEvent) {
        _barcodeBuffer = '';
      }
      return false;
    }

    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastBufferTime != null) {
      final diff = now.difference(_lastBufferTime!).inMilliseconds;
      if (diff > 80) {
        _barcodeBuffer = '';
      }
    }
    _lastBufferTime = now;

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
    return false;
  }

  void _onBarcodeScanned(String barcode) {
    _searchController.clear();
    ref.read(salesProductSearchQueryProvider.notifier).state = '';
    _handleBarcodeSubmit(barcode, const []);
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      ref.read(salesFlowProvider.notifier).addToCart(matched);
      _barcodeController.clear();
      _barcodeFocusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${matched.name} sepete eklendi.'),
          backgroundColor: _kGreen,
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _showErrorSnackBar('Barkod ile eşleşen ürün bulunamadı: $barcode');
      _barcodeFocusNode.requestFocus();
    }
  }

  Future<void> _submitSale() async {
    final flowState = ref.read(salesFlowProvider);

    if (flowState.cartQuantities.isEmpty) {
      _showErrorSnackBar('Lütfen sepete ürün ekleyin.');
      return;
    }

    final double totalAmount = flowState.total;

    if (flowState.paymentMethod == 'debt' && flowState.selectedCustomer == null) {
      _showErrorSnackBar('Vadeli satış için müşteri seçilmesi zorunludur!');
      return;
    }

    if (flowState.paymentMethod == 'karma') {
      final double paidAmount = flowState.paidAmount;
      if (paidAmount < totalAmount && flowState.selectedCustomer == null) {
        _showErrorSnackBar('Kalan borç tutarı (Vadeli) için müşteri seçilmesi zorunludur!');
        return;
      }
    }

    ref.read(salesFlowProvider.notifier).setSubmitting(true);

    try {
      final itemsInput = flowState.cartQuantities.entries.map((entry) {
        final prod = flowState.cartProducts[entry.key]!;
        return SaleItemInput(
          productId: prod.id,
          quantity: entry.value,
          unitPrice: prod.price,
        );
      }).toList();

      final customerId = flowState.selectedCustomer?.id ?? '';
      
      double finalPaid = totalAmount;
      if (flowState.paymentMethod == 'debt') {
        finalPaid = 0.0;
      } else if (flowState.paymentMethod == 'karma') {
        finalPaid = flowState.paidAmount;
      }

      final createdSale = await ref.read(salesControllerProvider.notifier).createSale(
        customerId: customerId,
        items: itemsInput,
        paymentMethod: flowState.paymentMethod,
        paidAmount: finalPaid,
      );

      if (createdSale == null) {
        throw Exception('Satış kaydı oluşturulamadı.');
      }

      // Play audio notification if enabled
      try {
        final settings = ref.read(settingsNotifierProvider).valueOrNull;
        if (settings?.soundNotificationEnabled ?? false) {
          SystemSound.play(SystemSoundType.click);
        }
      } catch (_) {}

      ref.invalidate(dashboardProvider);
      ref.invalidate(productsControllerProvider);
      ref.invalidate(salesProductsControllerProvider);

      // Transition to completed status first
      ref.read(salesFlowProvider.notifier).setSubmitting(false);

      // Print receipt automatically if checked in settings (no confirmation request)
      final settings = ref.read(settingsNotifierProvider).value;
      if (settings != null && settings.printReceipt) {
        _printReceipt(createdSale, flowState.selectedCustomer);
      }

      setState(() {
        _lastCompletedSale = createdSale;
        _showSuccessNotification = true;
      });

      // Automatically hide after 1.5 seconds
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _showSuccessNotification = false;
          });
        }
      });

      ref.read(salesFlowProvider.notifier).clearCart();
      _paidController.clear();
    } catch (e, stack) {
      debugPrint('🔴 ERROR in _submitSale: $e\n$stack');
      ref.read(salesFlowProvider.notifier).failPayment();
      _showErrorSnackBar('Satış tamamlanırken hata oluştu: $e');
    } finally {
      ref.read(salesFlowProvider.notifier).setSubmitting(false);
      _barcodeFocusNode.requestFocus();
    }
  }

  void _printReceipt(SaleEntity sale, CustomerEntity? selectedCustomer) {
    final settingsAsync = ref.read(settingsNotifierProvider);
    final settings = settingsAsync.value;
    if (settings == null) {
      _showErrorSnackBar('Yazıcı ayarları yüklenemedi.');
      return;
    }
    final hasPrinter = (settings.printerIp != null && settings.printerIp!.isNotEmpty) ||
                       (settings.printerName != null && settings.printerName!.isNotEmpty);
    if (!hasPrinter) {
      _showErrorSnackBar('Lütfen Ayarlar sayfasından bir yazıcı tanımlayın.');
      return;
    }

    try {
      final customer = selectedCustomer ?? CustomerEntity(id: '', name: 'Bilinmeyen Müşteri', email: '', phone: '', balance: 0, createdAt: DateTime.now());

      final products = ref.read(productsControllerProvider).value ?? [];
      final receiptItems = sale.items.map((item) {
        final prod = products.firstWhere(
          (p) => p.id == item['product_id'],
          orElse: () => ProductEntity(
            id: item['product_id'] ?? '',
            name: item['product_id'] ?? 'Ürün',
            description: '',
            price: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
            quantity: 0,
            category: '',
          ),
        );
        return {
          'product_id': prod.name,
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
        };
      }).toList();

      ref.read(printerServiceProvider).enqueue(
        'Satış Fişi #${sale.id.toShortId}',
        () => ref.read(printerServiceProvider).printSaleReceipt(
          sale,
          receiptItems,
          customer.id.isNotEmpty ? customer : null,
          settings,
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yazdırma işlemi sıraya eklendi.'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Yazdırma sırasına eklenirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Stack(
          children: [
            Consumer(
              builder: (context, ref, child) {
                final isProcessing = ref.watch(salesFlowProvider.select((state) => state.status == SalesFlowStatus.processing));
                return AbsorbPointer(
                  absorbing: isProcessing,
                  child: child!,
                );
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
  
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: CatalogPanel(
                            searchController: _searchController,
                            barcodeController: _barcodeController,
                            barcodeFocusNode: _barcodeFocusNode,
                            onAddToCart: (p) => ref.read(salesFlowProvider.notifier).addToCart(p),
                            onBarcodeSubmit: _handleBarcodeSubmit,
                          ),
                        ),
                        Container(width: 1, color: _kBorder),
                        Expanded(
                          flex: 2,
                          child: Consumer(
                            builder: (context, ref, child) {
                              final flowState = ref.watch(salesFlowProvider);
                              final customersAsyncVal = ref.watch(salesCustomersControllerProvider);

                              final checkoutWidget = CheckoutSection(
                                total: flowState.total,
                                selectedCustomer: flowState.selectedCustomer,
                                paymentMethod: flowState.paymentMethod,
                                paidAmount: flowState.paidAmount,
                                paidController: _paidController,
                                isSubmitting: flowState.isSubmitting,
                                customersAsyncVal: customersAsyncVal,
                                onCustomerChanged: (cust) => ref.read(salesFlowProvider.notifier).selectCustomer(cust),
                                onPaymentMethodChanged: (method) => ref.read(salesFlowProvider.notifier).setPaymentMethod(method),
                                onPaidAmountChanged: (amt) => ref.read(salesFlowProvider.notifier).setPaidAmount(amt),
                                onSubmitSale: _submitSale,
                              );

                              return CartPanel(
                                cartQuantities: flowState.cartQuantities,
                                cartProducts: flowState.cartProducts,
                                onClearCart: () => ref.read(salesFlowProvider.notifier).clearCart(),
                                onRemoveFromCart: (p) => ref.read(salesFlowProvider.notifier).removeFromCart(p),
                                onAddToCart: (p) => ref.read(salesFlowProvider.notifier).addToCart(p),
                                onDeleteFromCart: (p) => ref.read(salesFlowProvider.notifier).deleteFromCart(p),
                                onQuantityChanged: (p, qty) => ref.read(salesFlowProvider.notifier).updateQuantity(p, qty),
                                checkoutSectionWidget: checkoutWidget,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }
 
                  return DefaultTabController(
                    length: 2,
                    child: Scaffold(
                      backgroundColor: _kSurface,
                      body: TabBarView(
                        children: [
                          CatalogPanel(
                            searchController: _searchController,
                            barcodeController: _barcodeController,
                            barcodeFocusNode: _barcodeFocusNode,
                            onAddToCart: (p) => ref.read(salesFlowProvider.notifier).addToCart(p),
                            onBarcodeSubmit: _handleBarcodeSubmit,
                          ),
                          Consumer(
                            builder: (context, ref, child) {
                              final flowState = ref.watch(salesFlowProvider);
                              final customersAsyncVal = ref.watch(salesCustomersControllerProvider);

                              final checkoutWidget = CheckoutSection(
                                total: flowState.total,
                                selectedCustomer: flowState.selectedCustomer,
                                paymentMethod: flowState.paymentMethod,
                                paidAmount: flowState.paidAmount,
                                paidController: _paidController,
                                isSubmitting: flowState.isSubmitting,
                                customersAsyncVal: customersAsyncVal,
                                onCustomerChanged: (cust) => ref.read(salesFlowProvider.notifier).selectCustomer(cust),
                                onPaymentMethodChanged: (method) => ref.read(salesFlowProvider.notifier).setPaymentMethod(method),
                                onPaidAmountChanged: (amt) => ref.read(salesFlowProvider.notifier).setPaidAmount(amt),
                                onSubmitSale: _submitSale,
                              );

                              return CartPanel(
                                cartQuantities: flowState.cartQuantities,
                                cartProducts: flowState.cartProducts,
                                onClearCart: () => ref.read(salesFlowProvider.notifier).clearCart(),
                                onRemoveFromCart: (p) => ref.read(salesFlowProvider.notifier).removeFromCart(p),
                                onAddToCart: (p) => ref.read(salesFlowProvider.notifier).addToCart(p),
                                onDeleteFromCart: (p) => ref.read(salesFlowProvider.notifier).deleteFromCart(p),
                                onQuantityChanged: (p, qty) => ref.read(salesFlowProvider.notifier).updateQuantity(p, qty),
                                checkoutSectionWidget: checkoutWidget,
                              );
                            },
                          ),
                        ],
                      ),
                      bottomNavigationBar: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(top: BorderSide(color: _kBorder, width: 1)),
                        ),
                        child: SafeArea(
                          child: TabBar(
                            indicatorColor: _kGreen,
                            indicatorWeight: 3,
                            labelColor: _kGreen,
                            unselectedLabelColor: _kTextSecondary,
                            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
                            tabs: const [
                              Tab(
                                icon: Icon(Icons.grid_view_rounded, size: 20),
                                text: 'Katalog',
                              ),
                              Tab(
                                icon: _AnimatedCartTab(),
                                text: 'Sepet',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_showSuccessNotification)
            Positioned.fill(
              child: Center(
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: const Color(0xFF22C55E).withValues(alpha: 0.7),
                  size: 96,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedCartTab extends ConsumerStatefulWidget {
  const _AnimatedCartTab();

  @override
  ConsumerState<_AnimatedCartTab> createState() => _AnimatedCartTabState();
}

class _AnimatedCartTabState extends ConsumerState<_AnimatedCartTab> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.3), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.3, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 0.9, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = ref.watch(salesFlowProvider.select(
      (state) => state.cartQuantities.values.fold(0, (a, b) => a + b),
    ));

    if (cartCount > _lastCount) {
      _controller.forward(from: 0.0);
    }
    _lastCount = cartCount;

    return ScaleTransition(
      scale: _animation,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.shopping_basket_rounded, size: 20),
          if (cartCount > 0)
            Positioned(
              top: -6,
              right: -8,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFDC2626), // _kRed
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$cartCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
