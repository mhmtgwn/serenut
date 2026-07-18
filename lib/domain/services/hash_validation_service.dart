import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

class HashValidationService {
  /// Local SQLite veri tabanındaki belirlenen tabloların deterministik sırayla
  /// JSON (Canonical) çıktısını oluşturup SHA-256 checksum özetini döner.
  Future<String> calculateLocalChecksum() async {
    final db = await DatabaseManager().getDatabase();
    
    // Determinism için dikkate alınacak tablolar
    final tables = [
      'products',
      'customers',
      'sales',
      'sale_items',
      'financial_transactions'
    ];
    
    final Map<String, List<Map<String, dynamic>>> canonicalData = {};

    for (final table in tables) {
      // id alanına göre sıralayarak her zaman aynı dizilimi (deterministic order) elde ederiz.
      final records = await db.query(table, orderBy: 'id ASC');
      canonicalData[table] = records;
    }

    // Canonical Serialization: Key'leri A'dan Z'ye sıralayarak oluştur
    final sortedData = _sortMapKeys(canonicalData);
    
    // Json stringine çevir (boşluksuz, canonical form)
    final jsonString = jsonEncode(sortedData);
    
    // SHA-256 hash hesaplaması
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    
    return digest.toString();
  }

  /// Sunucudan dönen hash ile lokal hash'in doğruluğunu (Checksum Matching) kıyaslar.
  Future<bool> verifyChecksumMatch(String serverChecksum) async {
    final localChecksum = await calculateLocalChecksum();
    final bool isMatch = localChecksum == serverChecksum;

    if (!isMatch) {
      await TelemetryService().logStructured(
        event: 'sync_checksum_mismatch',
        level: LogLevel.critical,
        metadata: {
          'localHash': localChecksum,
          'serverHash': serverChecksum,
        },
      );
    }

    return isMatch;
  }

  /// Map veya List objelerindeki tüm key değerlerini özyinelemeli (recursive) olarak alfabetik sıralar.
  dynamic _sortMapKeys(dynamic value) {
    if (value is Map) {
      // Map'in anahtarlarını sırala
      final sortedKeys = value.keys.toList()..sort();
      final sortedMap = <String, dynamic>{};
      for (final key in sortedKeys) {
        sortedMap[key.toString()] = _sortMapKeys(value[key]);
      }
      return sortedMap;
    } else if (value is List) {
      return value.map(_sortMapKeys).toList();
    }
    return value; // Primitive value types
  }
}
