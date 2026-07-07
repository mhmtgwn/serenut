// lib/domain/models/business_profile.dart
// Serenut OS — İşletme Profili Domain Modeli
// BusinessProfile: İşletmenin kalıcı verilerini tutar.
// Raporlarda, filtrelerde ve gelecekteki multi-tenant yapıda kullanılabilir.

class BusinessProfile {
  final int? id;
  final String name;         // İşletme adı
  final String ownerName;    // Yetkili adı soyadı
  final String type;         // Market, Kafe, Restoran, vb.
  final String phone;
  final String? email;
  final String? taxNumber;
  final String city;
  final String district;
  final String currency;
  final bool taxIncluded;    // Vergi dahil fiyat mı?
  final String? logoPath;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const BusinessProfile({
    this.id,
    required this.name,
    required this.ownerName,
    required this.type,
    required this.phone,
    this.email,
    this.taxNumber,
    required this.city,
    required this.district,
    this.currency = '₺',
    this.taxIncluded = true,
    this.logoPath,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isValid =>
      name.isNotEmpty && ownerName.isNotEmpty && phone.isNotEmpty && city.isNotEmpty;

  Map<String, dynamic> toMap({bool includeId = false}) {
    final map = <String, dynamic>{
      'name': name,
      'owner_name': ownerName,
      'type': type,
      'phone': phone,
      'email': email,
      'tax_number': taxNumber,
      'city': city,
      'district': district,
      'currency': currency,
      'tax_included': taxIncluded ? 1 : 0,
      'logo_path': logoPath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
    if (includeId && id != null) map['id'] = id;
    return map;
  }

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      ownerName: map['owner_name'] as String? ?? '',
      type: map['type'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String?,
      taxNumber: map['tax_number'] as String?,
      city: map['city'] as String? ?? '',
      district: map['district'] as String? ?? '',
      currency: map['currency'] as String? ?? '₺',
      taxIncluded: (map['tax_included'] as int?) == 1,
      logoPath: map['logo_path'] as String?,
      createdAt: DateTime.parse(
        map['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  BusinessProfile copyWith({
    int? id,
    String? name,
    String? ownerName,
    String? type,
    String? phone,
    String? email,
    String? taxNumber,
    String? city,
    String? district,
    String? currency,
    bool? taxIncluded,
    String? logoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BusinessProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerName: ownerName ?? this.ownerName,
      type: type ?? this.type,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      taxNumber: taxNumber ?? this.taxNumber,
      city: city ?? this.city,
      district: district ?? this.district,
      currency: currency ?? this.currency,
      taxIncluded: taxIncluded ?? this.taxIncluded,
      logoPath: logoPath ?? this.logoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'BusinessProfile($name, type: $type, city: $city)';
}
