import 'package:flutter/material.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'rbac_guard.dart';

/// PinGateDialog is deprecated. Use [requireAdminAccess] in rbac_guard.dart instead.
@Deprecated('Use requireAdminAccess in rbac_guard.dart instead')
class PinGateDialog {
  PinGateDialog._();

  @Deprecated('Use requireAdminAccess in rbac_guard.dart instead')
  static Future<void> checkAndShow(
    BuildContext context, {
    required VoidCallback onVerified,
    String title = 'Yönetici Doğrulaması',
    List<UserRole> allowedRoles = const [UserRole.admin],
  }) async {
    await requireAdminAccess(
      context,
      onGranted: (approvedByUserId, approvedByUserName) => onVerified(),
      title: title,
      allowedRoles: allowedRoles,
    );
  }
}
