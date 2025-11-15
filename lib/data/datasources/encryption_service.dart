import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/utils/error_handler.dart';

/// Veri şifreleme ve güvenlik servisi
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  static const String _keyPrefix = 'enc_key_';
  static const String _saltPrefix = 'enc_salt_';
  
  /// Basit XOR şifreleme (gerçek uygulamalarda AES kullanılmalı)
  /// Bu implementasyon eğitim amaçlıdır
  String encryptData(String data, String key) {
    try {
      final dataBytes = utf8.encode(data);
      final keyBytes = utf8.encode(key);
      final encrypted = <int>[];
      
      for (int i = 0; i < dataBytes.length; i++) {
        encrypted.add(dataBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      
      return base64.encode(encrypted);
    } catch (e) {
      debugPrint('Şifreleme hatası: $e');
      return data; // Hata durumunda orijinal veriyi döndür
    }
  }

  /// Basit XOR şifre çözme
  String decryptData(String encryptedData, String key) {
    try {
      final encryptedBytes = base64.decode(encryptedData);
      final keyBytes = utf8.encode(key);
      final decrypted = <int>[];
      
      for (int i = 0; i < encryptedBytes.length; i++) {
        decrypted.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      
      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('Şifre çözme hatası: $e');
      return encryptedData; // Hata durumunda şifreli veriyi döndür
    }
  }

  /// Güvenli anahtar oluştur
  String generateSecureKey({int length = 32}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#\$%^&*';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  /// Salt oluştur
  String generateSalt({int length = 16}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  /// Şifre hash'le (PBKDF2 benzeri basit implementasyon)
  String hashPassword(String password, String salt) {
    final combined = password + salt;
    final bytes = utf8.encode(combined);
    
    // Birden fazla hash işlemi uygula (basit PBKDF2 benzeri)
    var hash = sha256.convert(bytes);
    for (int i = 0; i < 1000; i++) {
      hash = sha256.convert(hash.bytes);
    }
    
    return hash.toString();
  }

  /// Şifre doğrula
  bool verifyPassword(String password, String salt, String hashedPassword) {
    final computedHash = hashPassword(password, salt);
    return computedHash == hashedPassword;
  }

  /// Şifreleme anahtarını güvenli şekilde sakla
  Future<bool> storeEncryptionKey(String keyName, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString('$_keyPrefix$keyName', key);
      
      if (success) {
        debugPrint('Şifreleme anahtarı kaydedildi: $keyName');
      }
      
      return success;
    } catch (e) {
      ErrorHandler.reportError(
        'Anahtar Kaydetme Hatası',
        'Şifreleme anahtarı kaydedilemedi.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Şifreleme anahtarını al
  Future<String?> getEncryptionKey(String keyName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_keyPrefix$keyName');
    } catch (e) {
      ErrorHandler.reportError(
        'Anahtar Alma Hatası',
        'Şifreleme anahtarı alınamadı.',
        details: e.toString(),
      );
      return null;
    }
  }

  /// Salt'ı sakla
  Future<bool> storeSalt(String saltName, String salt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString('$_saltPrefix$saltName', salt);
    } catch (e) {
      ErrorHandler.reportError(
        'Salt Kaydetme Hatası',
        'Salt kaydedilemedi.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Salt'ı al
  Future<String?> getSalt(String saltName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_saltPrefix$saltName');
    } catch (e) {
      ErrorHandler.reportError(
        'Salt Alma Hatası',
        'Salt alınamadı.',
        details: e.toString(),
      );
      return null;
    }
  }

  /// Hassas veriyi şifrele ve sakla
  Future<bool> encryptAndStore(String dataKey, String data, {String? customKey}) async {
    try {
      // Şifreleme anahtarını al veya oluştur
      String? encKey = customKey ?? await getEncryptionKey('default');
      if (encKey == null) {
        encKey = generateSecureKey();
        await storeEncryptionKey('default', encKey);
      }

      // Veriyi şifrele
      final encryptedData = encryptData(data, encKey);
      
      // Şifreli veriyi sakla
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString('encrypted_$dataKey', encryptedData);
      
      if (success) {
        debugPrint('Hassas veri şifrelendi ve kaydedildi: $dataKey');
      }
      
      return success;
    } catch (e) {
      ErrorHandler.reportError(
        'Veri Şifreleme Hatası',
        'Hassas veri şifrelenemedi.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Şifreli veriyi al ve çöz
  Future<String?> decryptAndRetrieve(String dataKey, {String? customKey}) async {
    try {
      // Şifreli veriyi al
      final prefs = await SharedPreferences.getInstance();
      final encryptedData = prefs.getString('encrypted_$dataKey');
      
      if (encryptedData == null) {
        return null;
      }

      // Şifreleme anahtarını al
      String? encKey = customKey ?? await getEncryptionKey('default');
      if (encKey == null) {
        ErrorHandler.reportError(
          'Anahtar Bulunamadı',
          'Şifreleme anahtarı bulunamadı.',
        );
        return null;
      }

      // Veriyi çöz
      final decryptedData = decryptData(encryptedData, encKey);
      debugPrint('Hassas veri çözüldü: $dataKey');
      
      return decryptedData;
    } catch (e) {
      ErrorHandler.reportError(
        'Veri Çözme Hatası',
        'Şifreli veri çözülemedi.',
        details: e.toString(),
      );
      return null;
    }
  }

  /// Şifreli veriyi sil
  Future<bool> deleteEncryptedData(String dataKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.remove('encrypted_$dataKey');
      
      if (success) {
        debugPrint('Şifreli veri silindi: $dataKey');
      }
      
      return success;
    } catch (e) {
      ErrorHandler.reportError(
        'Veri Silme Hatası',
        'Şifreli veri silinemedi.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Müşteri bilgilerini şifrele
  Map<String, dynamic> encryptCustomerData(Map<String, dynamic> customerData, String key) {
    final encryptedData = Map<String, dynamic>.from(customerData);
    
    // Hassas alanları şifrele
    final sensitiveFields = ['phone', 'email', 'notes'];
    
    for (final field in sensitiveFields) {
      if (encryptedData[field] != null && encryptedData[field].toString().isNotEmpty) {
        encryptedData[field] = encryptData(encryptedData[field].toString(), key);
      }
    }
    
    return encryptedData;
  }

  /// Müşteri bilgilerini çöz
  Map<String, dynamic> decryptCustomerData(Map<String, dynamic> encryptedData, String key) {
    final decryptedData = Map<String, dynamic>.from(encryptedData);
    
    // Hassas alanları çöz
    final sensitiveFields = ['phone', 'email', 'notes'];
    
    for (final field in sensitiveFields) {
      if (decryptedData[field] != null && decryptedData[field].toString().isNotEmpty) {
        decryptedData[field] = decryptData(decryptedData[field].toString(), key);
      }
    }
    
    return decryptedData;
  }

  /// Ödeme bilgilerini şifrele
  Map<String, dynamic> encryptPaymentData(Map<String, dynamic> paymentData, String key) {
    final encryptedData = Map<String, dynamic>.from(paymentData);
    
    // Hassas ödeme alanlarını şifrele
    final sensitiveFields = ['card_number', 'card_holder', 'notes'];
    
    for (final field in sensitiveFields) {
      if (encryptedData[field] != null && encryptedData[field].toString().isNotEmpty) {
        encryptedData[field] = encryptData(encryptedData[field].toString(), key);
      }
    }
    
    return encryptedData;
  }

  /// Ödeme bilgilerini çöz
  Map<String, dynamic> decryptPaymentData(Map<String, dynamic> encryptedData, String key) {
    final decryptedData = Map<String, dynamic>.from(encryptedData);
    
    // Hassas ödeme alanlarını çöz
    final sensitiveFields = ['card_number', 'card_holder', 'notes'];
    
    for (final field in sensitiveFields) {
      if (decryptedData[field] != null && decryptedData[field].toString().isNotEmpty) {
        decryptedData[field] = decryptData(decryptedData[field].toString(), key);
      }
    }
    
    return decryptedData;
  }

  /// Tüm şifreleme anahtarlarını sil (güvenlik sıfırlama)
  Future<bool> clearAllEncryptionKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => 
        key.startsWith(_keyPrefix) || key.startsWith(_saltPrefix)
      ).toList();
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      ErrorHandler.showSuccess('Tüm şifreleme anahtarları temizlendi');
      return true;
    } catch (e) {
      ErrorHandler.reportError(
        'Anahtar Temizleme Hatası',
        'Şifreleme anahtarları temizlenemedi.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Güvenlik durumunu kontrol et
  Future<Map<String, dynamic>> getSecurityStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      final encryptionKeys = keys.where((key) => key.startsWith(_keyPrefix)).length;
      final salts = keys.where((key) => key.startsWith(_saltPrefix)).length;
      final encryptedData = keys.where((key) => key.startsWith('encrypted_')).length;
      
      return {
        'encryption_keys': encryptionKeys,
        'salts': salts,
        'encrypted_data_count': encryptedData,
        'security_enabled': encryptionKeys > 0,
        'last_check': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      ErrorHandler.reportError(
        'Güvenlik Durumu Hatası',
        'Güvenlik durumu kontrol edilemedi.',
        details: e.toString(),
      );
      return {
        'encryption_keys': 0,
        'salts': 0,
        'encrypted_data_count': 0,
        'security_enabled': false,
        'error': e.toString(),
      };
    }
  }

  /// Veri bütünlüğünü kontrol et
  String calculateDataIntegrity(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Veri bütünlüğünü doğrula
  bool verifyDataIntegrity(Map<String, dynamic> data, String expectedHash) {
    final calculatedHash = calculateDataIntegrity(data);
    return calculatedHash == expectedHash;
  }
}
