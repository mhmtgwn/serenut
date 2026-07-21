// lib/config/router.dart
// Navigation Router — StatefulShellRoute with 5-tab Bottom Navigation Bar
// Settings → free route (AppBar icon), Reports → free route
// Generated: 21 Jun 2026 (v2)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_wizard_page.dart';
import 'package:serenutos/presentation/pages/onboarding/bootstrap_loading_view.dart';
import 'package:serenutos/presentation/pages/onboarding/splash_screen.dart';
import 'package:serenutos/presentation/pages/login_page.dart';
import 'package:serenutos/presentation/pages/register_page.dart';
import 'package:serenutos/presentation/pages/operational_error_page.dart';
import 'package:serenutos/presentation/pages/home_page.dart';
import 'package:serenutos/presentation/pages/sales_page.dart';
import 'package:serenutos/presentation/pages/customers_page.dart';
import 'package:serenutos/presentation/pages/products_page.dart';
import 'package:serenutos/presentation/pages/reports_page.dart';
import 'package:serenutos/presentation/pages/orders_page.dart';
import 'package:serenutos/presentation/pages/settings_page.dart';
import 'package:serenutos/presentation/pages/customer_details_page.dart';
import 'package:serenutos/presentation/pages/customer_form_page.dart';
import 'package:serenutos/presentation/pages/collection_page.dart';
import 'package:serenutos/presentation/pages/product_form_page.dart';
import 'package:serenutos/presentation/pages/order_details_page.dart';
import 'package:serenutos/presentation/pages/sale_details_page.dart';
import 'package:serenutos/presentation/pages/sales_history_page.dart';
import 'package:serenutos/presentation/widgets/app_shell.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

import 'package:serenutos/presentation/pages/license_page.dart'
    show LicenseManagementPage;
import 'package:serenutos/presentation/pages/admin/admin_page.dart';
import 'package:serenutos/presentation/pages/settings/catalog_import_wizard_page.dart';
import 'package:serenutos/domain/models/permission.dart'
    show UserRole, Permission;
import 'package:serenutos/presentation/pages/operations_hub_page.dart';
import 'package:serenutos/presentation/pages/finance_hub_page.dart';
import 'package:serenutos/presentation/pages/system_hub_page.dart';
import 'package:serenutos/presentation/pages/settings/print_queue_page.dart';
import 'package:serenutos/presentation/pages/settings/sms_history_page.dart';
import 'package:serenutos/presentation/pages/settings/db_health_page.dart';

import 'package:serenutos/presentation/pages/paywall_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Navigation routes
class AppRoutes {
  static const login = '/login';
  static const loginSub = '/login/sub';
  static const onboarding =
      '/onboarding'; // Onboarding wizard — tek giriş noktası
  static const activation = '/onboarding'; // Eski alias
  static const paywall = '/paywall';
  static const home = '/';
  static const sales = '/sales';
  static const customers = '/customers';
  static const customerDetail = '/customers/detail';
  static const customerAdd = '/customers/add';
  static const customerEdit = '/customers/edit';
  static const customerCollect = '/customers/collect';
  static const products = '/products';
  static const productAdd = '/products/add';
  static const productEdit = '/products/edit';
  static const reports = '/reports';
  static const orders = '/orders';
  static const orderDetail = '/orders/detail';
  static const orderAdd = '/orders/add';
  static const orderEdit = '/orders/edit';
  static const settings = '/settings';
  static const catalogImportWizard = '/settings/catalog-import';
  static const license = '/settings/license';
  static const admin = '/admin';
  static const finance = '/finance';
  static const printing = '/printing';
  static const operations = '/operations';
  static const system = '/system';
  static const printQueue = '/settings/print-queue';
  static const smsHistory = '/settings/sms-history';
  static const dbHealth = '/settings/db-health';
  static const management = '/management';
}

String? _adminOnlyRedirect(BuildContext context, GoRouterState state) {
  final user = ProviderScope.containerOf(context).read(currentUserProvider);
  if (user == null ||
      !(user.role == UserRole.admin ||
          user.role == UserRole.owner ||
          user.role == UserRole.sysadmin)) {
    return AppRoutes.home;
  }
  return null;
}

String? _roleOrPermissionRedirect(BuildContext context, Permission permission) {
  final user = ProviderScope.containerOf(context).read(currentUserProvider);
  if (user == null) return AppRoutes.login;
  if (user.role == UserRole.owner || user.role == UserRole.admin) {
    return null;
  }
  if (user.hasPermission(permission.value)) {
    return null;
  }
  return AppRoutes.home;
}

/// GoRouter configuration provider
final routerProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  ref.watch(currentUserProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: isAuthenticated ? AppRoutes.home : AppRoutes.login,
    redirect: (context, state) {
      final loggedIn = isAuthenticated;

      final onLogin = state.matchedLocation == AppRoutes.login;
      final onLoginForm = state.matchedLocation == '/login/form';
      final onLoginSub = state.matchedLocation == AppRoutes.loginSub;
      final onRegister = state.matchedLocation.startsWith('/register');
      final onOnboarding = state.matchedLocation.startsWith('/onboarding');
      final onAuthScreen =
          onLogin || onLoginForm || onLoginSub || onRegister || onOnboarding;

      if (!loggedIn) {
        if (!onAuthScreen) return AppRoutes.login;
        return null;
      }

      if (onAuthScreen) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      // ── Login (karşılama ekranı)
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),

      // ── Login formu (giriş yap ekranı)
      GoRoute(
        path: '/login/form',
        name: 'login-form',
        builder: (context, state) => const LoginFormPage(),
      ),

      // ── Personel Girişi (PIN-based)
      GoRoute(
        path: AppRoutes.loginSub,
        name: 'login-sub',
        builder: (context, state) => const SubUserLoginPage(),
      ),

      // ── Hesap Oluştur (2 adımlı kayıt)
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),

      // ── Onboarding Wizard (ActivationPage yerini aldı) ────────────────
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingSplashScreen(),
        routes: [
          GoRoute(
            path: 'business',
            name: 'onboardingBusiness',
            builder: (context, state) => const OnboardingStep1Page(),
          ),
          GoRoute(
            path: 'admin',
            name: 'onboardingAdmin',
            builder: (context, state) => const OnboardingStep2Page(),
          ),
          GoRoute(
            path: 'success',
            name: 'onboardingSuccess',
            builder: (context, state) => const OnboardingSuccessPage(),
          ),
          GoRoute(
            path: 'license',
            name: 'onboardingLicense',
            builder: (context, state) => const OnboardingLicensePage(),
          ),
          GoRoute(
            path: 'bootstrap',
            name: 'onboardingBootstrap',
            builder: (context, state) => BootstrapLoadingView(
              onCompleted: () => context.go(AppRoutes.login),
            ),
          ),
        ],
      ),

      // ── Paywall Screen (no shell) ──────────────────────────────────────
      GoRoute(
        path: AppRoutes.paywall,
        name: 'paywall',
        builder: (context, state) => const PaywallPage(),
      ),

      // ── Operational Error (Cashier/Staff Restricted State) ─────────────
      GoRoute(
        path: '/operational-error',
        name: 'operationalError',
        builder: (context, state) => const OperationalErrorPage(),
      ),

      // ── Settings (free route — accessed via AppBar icon) ─────────────
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.settingsView),
      ),
      GoRoute(
        path: AppRoutes.catalogImportWizard,
        name: 'catalogImportWizard',
        builder: (context, state) => const CatalogImportWizardPage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.settingsDatabase),
      ),

      // ── Phase 4-6 New Free Routes ─────────────────────────────────────
      GoRoute(
        path: AppRoutes.license,
        name: 'license',
        builder: (context, state) => const LicenseManagementPage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.settingsLicense),
      ),
      GoRoute(
        path: AppRoutes.admin,
        name: 'admin',
        builder: (context, state) => const AdminPage(),
        redirect: _adminOnlyRedirect,
      ),
      GoRoute(
        path: AppRoutes.printQueue,
        name: 'printQueue',
        builder: (context, state) => const PrintQueuePage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.settingsPrinter),
      ),
      GoRoute(
        path: AppRoutes.smsHistory,
        name: 'smsHistory',
        builder: (context, state) => const SmsHistoryPage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.settingsView),
      ),
      GoRoute(
        path: AppRoutes.dbHealth,
        name: 'dbHealth',
        builder: (context, state) => const DbHealthPage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.settingsDatabase),
      ),

      // ── Reports (free route — no navbar tab) ─────────────────────────
      GoRoute(
        path: AppRoutes.reports,
        name: 'reports',
        builder: (context, state) => const ReportsPage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.reportsView),
      ),

      GoRoute(
        path: AppRoutes.finance,
        name: 'finance',
        builder: (context, state) => const FinanceHubPage(),
        redirect: (context, state) =>
            _roleOrPermissionRedirect(context, Permission.settingsFinance),
      ),
      GoRoute(
        path: AppRoutes.system,
        name: 'system',
        builder: (context, state) => const SystemHubPage(),
      ),
      GoRoute(
        path: AppRoutes.operations,
        name: 'operations',
        builder: (context, state) => const OperationsHubPage(),
      ),
      GoRoute(
        path: AppRoutes.management,
        name: 'management',
        builder: (context, state) => const SettingsPage(),
      ),

      // ── Main shell with 5-tab Bottom Navigation Bar ───────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0 — Home (Dashboard / Command Center)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: 'home',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),

          // Branch 1 — Sales (Kasa / Satış)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.sales,
                name: 'sales',
                builder: (context, state) => const SalesPage(),
                redirect: (context, state) =>
                    _roleOrPermissionRedirect(context, Permission.salesView),
                routes: [
                  GoRoute(
                    path: 'detail/:id',
                    name: 'saleDetail',
                    builder: (context, state) => SaleDetailsPage(
                      saleId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'history',
                    name: 'salesHistory',
                    builder: (context, state) => const SalesHistoryPage(),
                  ),
                ],
              ),
            ],
          ),

          // Branch 2 — Orders (Siparişler)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.orders,
                name: 'orders',
                builder: (context, state) => const OrdersPage(),
                redirect: (context, state) =>
                    _roleOrPermissionRedirect(context, Permission.ordersView),
                routes: [
                  GoRoute(
                    path: 'detail/:id',
                    name: 'orderDetail',
                    builder: (context, state) => OrderDetailsPage(
                      orderId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Branch 3 — Customers (Müşteriler / Cariler)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.customers,
                name: 'customers',
                builder: (context, state) => const CustomersPage(),
                redirect: (context, state) => _roleOrPermissionRedirect(
                    context, Permission.customersView),
                routes: [
                  GoRoute(
                    path: 'detail/:id',
                    name: 'customerDetail',
                    builder: (context, state) => CustomerDetailsPage(
                      customerId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'add',
                    name: 'customerAdd',
                    builder: (context, state) => const CustomerFormPage(
                      isEditing: false,
                    ),
                    redirect: (context, state) => _roleOrPermissionRedirect(
                        context, Permission.customersCreate),
                  ),
                  GoRoute(
                    path: 'edit/:id',
                    name: 'customerEdit',
                    builder: (context, state) => CustomerFormPage(
                      isEditing: true,
                      existingCustomer: state.extra as CustomerEntity?,
                    ),
                    redirect: (context, state) => _roleOrPermissionRedirect(
                        context, Permission.customersEdit),
                  ),
                  GoRoute(
                    path: ':id/collect',
                    name: 'customerCollect',
                    builder: (context, state) => CollectionPage(
                      customerId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Branch 4 — Products (Ürünler)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.products,
                name: 'products',
                builder: (context, state) => const ProductsPage(),
                redirect: (context, state) => _roleOrPermissionRedirect(
                    context, Permission.inventoryView),
                routes: [
                  GoRoute(
                    path: 'add',
                    name: 'productAdd',
                    builder: (context, state) => const ProductFormPage(
                      isEditing: false,
                    ),
                    redirect: (context, state) => _roleOrPermissionRedirect(
                        context, Permission.inventoryAdjust),
                  ),
                  GoRoute(
                    path: 'edit/:id',
                    name: 'productEdit',
                    builder: (context, state) => ProductFormPage(
                      isEditing: true,
                      existingProduct: state.extra as ProductEntity?,
                    ),
                    redirect: (context, state) => _roleOrPermissionRedirect(
                        context, Permission.inventoryAdjust),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],

    // Error page
    errorBuilder: (context, state) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                'Sayfa bulunamadı',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Ana sayfaya dön'),
              ),
            ],
          ),
        ),
      );
    },
  );
});

/// GoRouter extension for easy navigation
extension GoRouterX on GoRouter {
  void goLogin() => go(AppRoutes.login);
  void goHome() => go(AppRoutes.home);
  void goSales() => go(AppRoutes.sales);
  void goCustomers() => go(AppRoutes.customers);
  void goProducts() => go(AppRoutes.products);
  void goReports() => go(AppRoutes.reports);
  void goOrders() => go(AppRoutes.orders);
  void goSettings() => go(AppRoutes.settings);
  void goOperations() => go(AppRoutes.operations);
  void goFinance() => go(AppRoutes.finance);
  void goSystem() => go(AppRoutes.system);
  void goManagement() => go(AppRoutes.management);
}
