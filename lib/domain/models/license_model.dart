// lib/domain/models/license_model.dart
enum LicenseTier {
  basic('BASIC', 3),
  pro('PRO', 6),
  proPlus('PRO_PLUS', 9);

  final String name;
  final int deviceLimit;

  const LicenseTier(this.name, this.deviceLimit);
}
