import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'pin_verification_dialog.dart';

typedef GatedActionCallback = void Function(
    String? approvedByUserId, String? approvedByUserName);

/// Centralized RBAC check utility.
/// Checks if the logged-in user has the required role. If requirePin is true,
/// displays a modal PIN dialog. If requireConfirm is true, also requires a confirmation checkbox.
Future<void> requireAdminAccess(
  BuildContext context, {
  required GatedActionCallback onGranted,
  String title = 'Yönetici Doğrulaması',
  List<UserRole> allowedRoles = const [UserRole.admin],
  bool requirePin = false,
  bool requireConfirm = false,
}) async {
  final container = ProviderScope.containerOf(context);
  final user = container.read(currentUserProvider);

  if (user == null ||
      !(user.role == UserRole.admin ||
          user.role == UserRole.owner ||
          user.role == UserRole.sysadmin ||
          allowedRoles.contains(user.role))) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Yetki Hatası', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bu işlem için gerekli yetkiye sahip değilsiniz.\n(İşlem: $title)',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return;
  }

  if (!requirePin) {
    onGranted(user.id, user.name);
    return;
  }

  if (!context.mounted) return;
  final result = await showDialog<PinVerificationResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PinVerificationDialog(
      actionTitle: title,
      requireConfirm: requireConfirm,
    ),
  );

  if (result != null && result.success) {
    onGranted(result.userId, result.userName);
  }
}

/// Centralized Permission-based check utility.
/// Checks if the logged-in user has the required permission. If requirePin is true,
/// displays a modal PIN dialog. If requireConfirm is true, also requires a confirmation checkbox.
Future<void> requirePermissionAccess(
  BuildContext context, {
  required Permission permission,
  required GatedActionCallback onGranted,
  String title = 'İşlem Doğrulaması',
  bool requirePin = false,
  bool requireConfirm = false,
}) async {
  final container = ProviderScope.containerOf(context);
  final user = container.read(currentUserProvider);

  final hasAccess = user != null &&
      (user.role == UserRole.sysadmin ||
          user.role == UserRole.owner ||
          user.hasPermission(permission.value));

  if (!hasAccess) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Yetki Hatası', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bu işlem için gerekli yetkiye sahip değilsiniz.\n(İşlem: $title)',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return;
  }

  if (!requirePin) {
    onGranted(user.id, user.name);
    return;
  }

  if (!context.mounted) return;
  final result = await showDialog<PinVerificationResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PinVerificationDialog(
      actionTitle: title,
      requireConfirm: requireConfirm,
    ),
  );

  if (result != null && result.success) {
    onGranted(result.userId, result.userName);
  }
}
