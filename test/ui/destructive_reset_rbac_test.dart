import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

void main() {
  Widget appFor(UserRole role) {
    final user = AuthUser(
      id: 'user-1',
      name: 'Test User',
      email: 'test@example.com',
      role: role,
      permissions: const ['settings:recovery'],
      createdAt: DateTime(2026),
    );
    return ProviderScope(
      overrides: [currentUserProvider.overrideWithValue(user)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => requirePermissionAccess(
                context,
                permission: Permission.settingsRecovery,
                allowedRoles: const [UserRole.owner, UserRole.sysadmin],
                onGranted: (_, __) =>
                    ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('granted')),
                ),
              ),
              child: const Text('reset'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('admin permission alone cannot run destructive tenant reset',
      (tester) async {
    await tester.pumpWidget(appFor(UserRole.admin));
    await tester.tap(find.text('reset'));
    await tester.pumpAndSettle();
    expect(find.text('Yetki Hatası'), findsOneWidget);
    expect(find.text('granted'), findsNothing);
  });

  testWidgets('owner with recovery permission can run destructive reset',
      (tester) async {
    await tester.pumpWidget(appFor(UserRole.owner));
    await tester.tap(find.text('reset'));
    await tester.pump();
    expect(find.text('granted'), findsOneWidget);
  });
}
