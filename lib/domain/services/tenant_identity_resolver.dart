// lib/domain/services/tenant_identity_resolver.dart
// Serenut OS — Çok Kiracılı İşletme Kimliği Çözümleyicisi (TenantIdentityResolver)
//
// Lisans/JWT ortamında kullanılan resmi bulut merchant/company ID'leri ile
// yerel Core Next ve SQLite şemalarında kullanılan slug kimliklerini
// güvenli, fail-closed ve deterministik olarak eşler.

class TenantIdentityResolver {
  TenantIdentityResolver._();

  /// Doğrulanmış ve resmi Cloud Merchant ID <-> Yerel Slug eşleme haritası.
  static const Map<String, String> _merchantIdToSlug = {
    // Nutopia Fındık Değirmeni (Mehmet Güven)
    'comp-1785241628448-c7f5677d': 'nutopia',
    // Erkul Çeyiz (Tunahan Erkul)
    'comp-1791194455402-bdc6d8d1': 'erkul',
    // Serenut POS / Merkez
    'comp-1785238670379-52219714': 'serenut',
  };

  /// Verilen kimliği (merchant ID veya slug) kanonik slug formatına normalize eder.
  /// Tanınmayan veya geçersiz kimliklerde boşluk temizlenmiş küçük harfli halini döner.
  static String normalize(String? rawId) {
    if (rawId == null) return '';
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) return '';
    return _merchantIdToSlug[trimmed] ?? trimmed.toLowerCase();
  }

  /// İki kiracı kimliğinin (biri cloud merchant ID, diğeri yerel slug olsa dahi)
  /// aynı doğrulanmış işletmeye ait olduğunu kesin olarak karşılaştırır.
  ///
  /// Güvenlik Kuralı (Fail-Closed):
  /// - Her iki kimlik de null veya boş olamaz.
  /// - Normalize edilmiş kimlikler tam olarak eşit olmalıdır.
  /// - Bilinmeyen veya farklı kimliklerde sistem asla açılmaz (fail-closed).
  static bool matches({
    required String? requestedTenantId,
    required String? dbTenantId,
  }) {
    if (requestedTenantId == null || dbTenantId == null) return false;
    final rNorm = normalize(requestedTenantId);
    final dNorm = normalize(dbTenantId);
    if (rNorm.isEmpty || dNorm.isEmpty) return false;
    return rNorm == dNorm;
  }
}
