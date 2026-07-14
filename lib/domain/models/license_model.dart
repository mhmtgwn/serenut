// lib/domain/models/license_model.dart
enum LicenseTier {
  basic('BASIC', 3),
  pro('PRO', 6),
  proPlus('PRO_PLUS', 9);

  final String name;
  final int deviceLimit;

  const LicenseTier(this.name, this.deviceLimit);
}

class CompanyLicense {
  final String companyId;
  final LicenseTier tier;
  final List<String> activeDeviceIds;
  final bool isActive;

  CompanyLicense({
    required this.companyId,
    required this.tier,
    required this.activeDeviceIds,
    required this.isActive,
  });

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'tier': tier.name,
        'activeDeviceIds': activeDeviceIds,
        'isActive': isActive,
      };

  factory CompanyLicense.fromJson(Map<String, dynamic> json) {
    final tierStr = json['tier'] as String? ?? 'BASIC';
    final tier = LicenseTier.values.firstWhere(
      (t) => t.name == tierStr,
      orElse: () => LicenseTier.basic,
    );

    return CompanyLicense(
      companyId: json['companyId'] as String? ?? '',
      tier: tier,
      activeDeviceIds:
          List<String>.from(json['activeDeviceIds'] as List? ?? []),
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}
