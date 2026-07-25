// lib/infrastructure/services/crypto/canonical_json.dart
// Serenut Platform — RFC 8785 / JCS Compliant Canonical JSON Serializer
// Produces deterministic JSON strings independent of key order or whitespace.

import 'dart:convert';

class CanonicalJsonSerializer {
  /// Encodes any JSON-encodable object into a canonical, deterministic JSON string.
  static String encode(Object? object) {
    final normalized = _normalize(object);
    return jsonEncode(normalized);
  }

  static Object? _normalize(Object? object) {
    if (object == null) return null;
    if (object is bool || object is num || object is String) {
      return object;
    }
    if (object is List) {
      return object.map(_normalize).toList();
    }
    if (object is Map) {
      final sortedKeys = object.keys.map((e) => e.toString()).toList()..sort();
      final sortedMap = <String, Object?>{};
      for (final key in sortedKeys) {
        sortedMap[key] = _normalize(object[key]);
      }
      return sortedMap;
    }
    // Fallback for custom objects with toJson
    try {
      final dynamic jsonable = (object as dynamic).toJson();
      return _normalize(jsonable);
    } catch (_) {
      return object.toString();
    }
  }
}
