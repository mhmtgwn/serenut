// core_next/client_core/lib/domain/models/rbac_models.dart

import 'money_cents.dart';

/// Serenut OS Rol Tabanlı Erişim Kontrolü (RBAC) Modeli
enum AppRole {
  owner,
  admin,
  sysadmin,
  manager,
  cashier,
  staff;

  static AppRole fromString(String? val) {
    if (val == null) return AppRole.cashier;
    final normalized = val.trim().toLowerCase();
    for (final r in AppRole.values) {
      if (r.name == normalized) return r;
    }
    return AppRole.cashier;
  }
}

/// Sistemde denetlenen finansal ve operasyonel izinler
enum AppPermission {
  createSale,
  applyDiscount,
  cancelSale,
  refund,
  creditSale,
  collectDebt,
  stockAdjustment,
  userAndDeviceSettings,
}

/// Rol - İzin Matrisi (En az ayrıcalık ilkesi / Least Privilege)
class RbacPolicy {
  static const Map<AppRole, Set<AppPermission>> _rolePermissions = {
    AppRole.sysadmin: {
      AppPermission.createSale,
      AppPermission.applyDiscount,
      AppPermission.cancelSale,
      AppPermission.refund,
      AppPermission.creditSale,
      AppPermission.collectDebt,
      AppPermission.stockAdjustment,
      AppPermission.userAndDeviceSettings,
    },
    AppRole.admin: {
      AppPermission.createSale,
      AppPermission.applyDiscount,
      AppPermission.cancelSale,
      AppPermission.refund,
      AppPermission.creditSale,
      AppPermission.collectDebt,
      AppPermission.stockAdjustment,
      AppPermission.userAndDeviceSettings,
    },
    AppRole.owner: {
      AppPermission.createSale,
      AppPermission.applyDiscount,
      AppPermission.cancelSale,
      AppPermission.refund,
      AppPermission.creditSale,
      AppPermission.collectDebt,
      AppPermission.stockAdjustment,
      AppPermission.userAndDeviceSettings,
    },
    AppRole.manager: {
      AppPermission.createSale,
      AppPermission.applyDiscount,
      AppPermission.cancelSale,
      AppPermission.refund,
      AppPermission.creditSale,
      AppPermission.collectDebt,
      AppPermission.stockAdjustment,
    },
    AppRole.cashier: {
      AppPermission.createSale,
      AppPermission.creditSale,
      AppPermission.collectDebt,
      // cashier varsayılan olarak iskonto ve iade yapamaz (yönetici onayı gerektirir)
    },
    AppRole.staff: {
      AppPermission.createSale,
      // staff veresiye, iskonto, iade ve kasa yönetimi yapamaz
    },
  };

  static bool hasPermission(AppRole role, AppPermission permission) {
    return _rolePermissions[role]?.contains(permission) ?? false;
  }
}

/// Doğrulanmış yönetici yetki onayı
class ManagerApproval {
  final String managerId;
  final String managerUsername;
  final AppRole managerRole;
  final String? actionReference; // Belirli bir satış ID veya işlem referansı
  final MoneyCents? maxApprovedAmount; // Onaylanan maksimum tutar veya iskonto sınırı
  final DateTime? approvedAt; // Onay zaman damgası

  const ManagerApproval({
    required this.managerId,
    required this.managerUsername,
    required this.managerRole,
    this.actionReference,
    this.maxApprovedAmount,
    this.approvedAt,
  });

  /// Yalnızca gerçek yönetici rolleri (manager, admin, owner) onay verebilir.
  bool get isValidManagerRole =>
      managerRole == AppRole.manager ||
      managerRole == AppRole.admin ||
      managerRole == AppRole.owner;
}

/// İşlemi gerçekleştiren aktör bağlamı (Denetlenebilir kimlik)
class ActorContext {
  final String userId;
  final String username;
  final AppRole role;
  final ManagerApproval? managerApproval;
  final bool isSystem;

  const ActorContext({
    required this.userId,
    required this.username,
    required this.role,
    this.managerApproval,
    this.isSystem = false,
  });

  /// Sistem aktörü (Yalnızca arka plan senkronizasyonu veya dahili migrasyon için)
  static const ActorContext system = ActorContext(
    userId: 'system-actor-internal',
    username: 'system',
    role: AppRole.sysadmin,
    isSystem: true,
  );

  /// Test ve geliştirme ortamı için yetkili kasiyer aktörü
  static const ActorContext testCashier = ActorContext(
    userId: 'test-cashier-id',
    username: 'test_cashier',
    role: AppRole.cashier,
  );

  /// Test ve geliştirme ortamı için yetkili yönetici aktörü
  static const ActorContext testManager = ActorContext(
    userId: 'test-manager-id',
    username: 'test_manager',
    role: AppRole.manager,
  );

  bool hasPermission(AppPermission permission) {
    if (RbacPolicy.hasPermission(role, permission)) {
      return true;
    }
    // Eğer kullanıcının kendi rolü yetersizse ancak doğrulanmış bir yönetici onayı eklenmişse:
    if (managerApproval != null && managerApproval!.isValidManagerRole) {
      return RbacPolicy.hasPermission(managerApproval!.managerRole, permission);
    }
    return false;
  }

  void requirePermission(AppPermission permission, String actionDescription) {
    if (!hasPermission(permission)) {
      throw AuthorizationException(
        'Yetkisiz işlem: $actionDescription. '
        'Gerekli izin: ${permission.name}, Kullanıcı rolü: ${role.name}',
        requiredPermission: permission,
        userRole: role,
      );
    }
  }
}

/// Yetkisiz işlem istisnası
class AuthorizationException implements Exception {
  final String message;
  final AppPermission requiredPermission;
  final AppRole userRole;

  const AuthorizationException(
    this.message, {
    required this.requiredPermission,
    required this.userRole,
  });

  @override
  String toString() => 'AuthorizationException: $message';
}

/// Kimliksiz veya aktörsüz işlem engeli (Fail-Secure)
class AuthenticationRequiredException implements Exception {
  final String message;
  const AuthenticationRequiredException(this.message);

  @override
  String toString() => 'AuthenticationRequiredException: $message';
}
