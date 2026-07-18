import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/presentation/pages/settings_page.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/presentation/pages/settings/db_health_page.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/domain/services/i_printer_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mock binary messenger for assets/data/cities.json to prevent async leaks in tests
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        if (message == null) return null;
        final Uint8List list = message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes);
        final String key = utf8.decode(list);
        if (key == 'assets/data/cities.json') {
          final jsonStr = jsonEncode({
            'countries': [
              {
                'code': 'TR',
                'cities': [
                  {
                    'name': 'Istanbul',
                    'districts': ['Kadikoy', 'Besiktas']
                  }
                ]
              }
            ]
          });
          return ByteData.sublistView(utf8.encode(jsonStr));
        }
        return null;
      },
    );

    try {
      await rootBundle.loadString('assets/data/cities.json');
    } catch (_) {}

    InMemoryDb.settings = Settings(
      businessName: 'Test Market',
      businessPhone: '05554443322',
      businessAddress: 'Istanbul',
      ownerName: 'Test Owner',
      printerIp: '192.168.1.100',
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  group('SettingsPage Granular RBAC Authorization Tests', () {
    testWidgets(
        'Sysadmin sees all sections including platform-level Admin Kontrol Merkezi',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = AuthUser(
        id: 'usr-sysadmin',
        name: 'Sys Admin',
        email: 'sys@serenut.com',
        role: UserRole.sysadmin,
        permissions:
            Permission.forRole(UserRole.sysadmin).map((p) => p.value).toList(),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(mockUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kullanıcı Yönetimi'), findsOneWidget);
      expect(find.text('Cari Hesap Bütünlüğü & Replay'), findsOneWidget);
      expect(find.text('Veritabanı Sağlık Kontrolü'), findsOneWidget);
      expect(find.text('Finans Hub & Raporlar'), findsOneWidget);
      expect(find.text('Denetim Merkezi (Audit Center)'), findsOneWidget);
      expect(find.text('Veri Kurtarma Merkezi'), findsOneWidget);
      expect(find.text('Admin Kontrol Merkezi'), findsOneWidget);

      await tester.pump();
    });

    testWidgets(
        'Owner sees all tenant-level sections but NOT Admin Kontrol Merkezi (platform level)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = AuthUser(
        id: 'usr-owner',
        name: 'Owner User',
        email: 'owner@serenut.com',
        role: UserRole.owner,
        permissions:
            Permission.forRole(UserRole.owner).map((p) => p.value).toList(),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(mockUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kullanıcı Yönetimi'), findsOneWidget);
      expect(find.text('Cari Hesap Bütünlüğü & Replay'), findsOneWidget);
      expect(find.text('Veritabanı Sağlık Kontrolü'), findsOneWidget);
      expect(find.text('Finans Hub & Raporlar'), findsOneWidget);
      expect(find.text('Denetim Merkezi (Audit Center)'), findsOneWidget);
      expect(find.text('Veri Kurtarma Merkezi'), findsOneWidget);
      expect(find.text('Admin Kontrol Merkezi'), findsNothing);

      await tester.pump();
    });

    testWidgets(
        'Admin with all permissions sees all tenant-level sections but NOT Admin Kontrol Merkezi',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = AuthUser(
        id: 'usr-admin',
        name: 'Admin User',
        email: 'admin@serenut.com',
        role: UserRole.admin,
        permissions:
            Permission.forRole(UserRole.admin).map((p) => p.value).toList(),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(mockUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kullanıcı Yönetimi'), findsOneWidget);
      expect(find.text('Veritabanı Sağlık Kontrolü'), findsOneWidget);
      expect(find.text('Admin Kontrol Merkezi'), findsNothing);

      await tester.pump();
    });

    testWidgets(
        'Admin with customized restricted permissions cannot see options without permission',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = AuthUser(
        id: 'usr-admin-restricted',
        name: 'Restricted Admin',
        email: 'radmin@serenut.com',
        role: UserRole.admin,
        permissions: [
          'settings:view',
          'settings:printer',
          'settings:users',
          'settings:finance'
        ], // lacks settings:database
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(mockUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Database health options should not be visible
      expect(find.text('Veritabanı Sağlık Kontrolü'), findsNothing);
      expect(find.text('Veri İçeri / Dışarı Aktar'), findsNothing);

      // Allowed options visible
      expect(find.text('Kullanıcı Yönetimi'), findsOneWidget);

      await tester.pump();
    });

    testWidgets(
        'Cashier with printer permission sees Settings & Printer options, but Admin options are hidden',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cashierUser = AuthUser(
        id: 'usr-cashier',
        name: 'Test Cashier',
        email: 'cashier@serenut.com',
        role: UserRole.cashier,
        permissions: ['settings:view', 'settings:printer'],
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(cashierUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Settings screen and safe printer settings visible
      expect(find.text('Fiş Yazıcı Ayarları'), findsOneWidget);
      expect(find.text('Etiket Yazıcı Ayarları'), findsOneWidget);
      expect(find.text('Donanım Diagnostics Testleri'), findsOneWidget);

      // Admin actions hidden
      expect(find.text('Kullanıcı Yönetimi'), findsNothing);
      expect(find.text('Cari Hesap Bütünlüğü & Replay'), findsNothing);
      expect(find.text('Veritabanı Sağlık Kontrolü'), findsNothing);
      expect(find.text('Veri Kurtarma Merkezi'), findsNothing);

      await tester.pump();
    });

    testWidgets(
        'Staff without printer permission sees Settings & Safe settings, but Printer options are hidden',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final staffUser = AuthUser(
        id: 'usr-staff',
        name: 'Test Staff',
        email: 'staff@serenut.com',
        role: UserRole.staff,
        permissions: ['settings:view'], // no settings:printer
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(staffUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Safe self/debug settings are visible
      expect(find.text('Hata Ayıklama Modu (Debug)'), findsOneWidget);
      expect(find.text('Satışta Sesli Bildirim'), findsOneWidget);

      // Printer options are hidden
      expect(find.text('Fiş Yazıcı Ayarları'), findsNothing);
      expect(find.text('Etiket Yazıcı Ayarları'), findsNothing);

      await tester.pump();
    });

    testWidgets(
        'User with empty/restricted permissions can still access Settings shell for safe/local settings',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = AuthUser(
        id: 'usr-1',
        name: 'Restricted Staff',
        email: 'staff@serenut.com',
        role: UserRole.staff,
        permissions: [], // empty permissions
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(mockUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Access is allowed (no blocked entry message)
      expect(find.text('Ayarlar sayfasına erişim yetkiniz bulunmuyor.'),
          findsNothing);

      // Safe local settings visible
      expect(find.text('Hata Ayıklama Modu (Debug)'), findsOneWidget);
      expect(find.text('Satışta Sesli Bildirim'), findsOneWidget);

      // Sensitive modules hidden
      expect(find.text('Fiş Yazıcı Ayarları'), findsNothing);
      expect(find.text('Kullanıcı Yönetimi'), findsNothing);

      await tester.pump();
    });

    testWidgets(
        'Action bypass protection: direct navigation to DbHealthPage without database permission blocks access',
        (WidgetTester tester) async {
      final mockUser = AuthUser(
        id: 'usr-staff',
        name: 'Restricted Staff',
        email: 'staff@serenut.com',
        role: UserRole.staff,
        permissions: ['settings:view'], // has view, but not settings:database
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(mockUser),
            settingsRepositoryProvider
                .overrideWith((ref) => InMemorySettingsRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DbHealthPage(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Assert DbHealthPage is blocked because of missing settings:database permission
      expect(
          find.text('Bu sayfaya erişim yetkiniz bulunmuyor.'), findsOneWidget);

      await tester.pump();
    });
  });
}
