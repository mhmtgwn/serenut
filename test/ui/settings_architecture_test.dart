import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/presentation/pages/data_transfer_page.dart';
import 'package:serenutos/presentation/pages/operations_center_page.dart';
import 'package:serenutos/presentation/pages/settings/account_page.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('data management modes expose only their own responsibility',
      (tester) async {
    Future<void> pump(DataManagementMode mode) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: DataTransferPage(mode: mode)),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(DataManagementMode.transfer);
    expect(find.text('Ürün Kataloğu İçe Aktar (.zip / .xlsx)'), findsOneWidget);
    expect(find.text('Tüm Verileri Sıfırla (Fabrika Ayarları)'), findsNothing);

    await pump(DataManagementMode.backup);
    expect(find.text('Yedekleme ve Geri Yükleme'), findsWidgets);
    expect(find.text('Ürün Kataloğu İçe Aktar (.zip / .xlsx)'), findsNothing);

    await pump(DataManagementMode.dangerous);
    expect(
        find.text('Tüm Verileri Sıfırla (Fabrika Ayarları)'), findsOneWidget);
    expect(find.text('Yedekleme ve Geri Yükleme'), findsNothing);
  });

  testWidgets('operations center owns queue, history and bulk messaging',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider
              .overrideWith((ref) => InMemorySettingsRepository()),
        ],
        child: const MaterialApp(home: OperationsCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yazıcı Kuyruğu'), findsOneWidget);
    expect(find.text('SMS Gönderim Geçmişi'), findsOneWidget);
    expect(find.text('Toplu SMS İşlemleri'), findsOneWidget);
  });

  testWidgets('account center exposes session actions and permissions',
      (tester) async {
    final user = AuthUser(
      id: 'owner',
      name: 'Test Owner',
      email: 'owner@example.com',
      role: UserRole.owner,
      permissions: const ['settings:view'],
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(user)],
        child: const MaterialApp(home: AccountPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Owner'), findsOneWidget);
    expect(find.text('Kullanıcı değiştir'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Oturumu kapat'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Oturumu kapat'), findsOneWidget);
  });
}
