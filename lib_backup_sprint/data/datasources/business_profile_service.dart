import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class BusinessProfileService {
  static final BusinessProfileService _instance = BusinessProfileService._internal();

  // İşletme bilgileri
  Map<String, dynamic>? _profileCache;
  static const String _profileKey = 'business_profile';

  factory BusinessProfileService() {
    return _instance;
  }

  BusinessProfileService._internal();

  // Singleton instance getter
  static BusinessProfileService get instance => _instance;

  // İşletme bilgilerini getir
  Future<Map<String, dynamic>> getBusinessProfile() async {
    try {
      if (_profileCache != null) {
        return _profileCache!;
      }

      // SharedPreferences'tan oku
      final prefs = await SharedPreferences.getInstance();
      final profileJson = prefs.getString(_profileKey);
      
      if (profileJson != null) {
        try {
          _profileCache = json.decode(profileJson) as Map<String, dynamic>;
          debugPrint('Profil SharedPreferences\'tan alındı');
          
          // Logo dosyasını kontrol et, eğer dosya yoksa null yap
          if (_profileCache!['logo_path'] != null) {
            final file = File(_profileCache!['logo_path']);
            if (!await file.exists()) {
              _profileCache!['logo_path'] = null;
              debugPrint('Logo dosyası bulunamadı, logo yolu null yapıldı');
            }
          }
          
          return _profileCache!;
        } catch (e) {
          debugPrint('SharedPreferences profil dönüşüm hatası: $e');
        }
      }
      
      // Profil bulunamadı, varsayılan profil oluştur
      final Map<String, dynamic> defaultProfile = {
        'id': 1,
        'company_name': 'Şirket Adı',
        'phone': '+90 555 123 4567',
        'address': 'İstanbul, Türkiye',
        'email': 'işletme@email.com',
        'store_name': 'Shaman Market',
        'note': 'Bizi tercih ettiğiniz için teşekkür ederiz!',
        'tax_number': '1234567890',
        'currency': '₺ TL',
        'logo_path': null,
        'password': '123456'  // Varsayılan şifre
      };
      
      // SharedPreferences'a kaydet
      await prefs.setString(_profileKey, json.encode(defaultProfile));
      
      _profileCache = defaultProfile;
      return defaultProfile;
    } catch (e) {
      debugPrint('BusinessProfileService.getBusinessProfile hatası: $e');
      return {
        'id': 1,
        'company_name': 'Şirket Adı',
        'phone': '+90 555 123 4567',
        'address': 'İstanbul, Türkiye',
        'email': 'işletme@email.com',
        'store_name': 'Shaman Market',
        'note': 'Bizi tercih ettiğiniz için teşekkür ederiz!',
        'tax_number': '1234567890',
        'currency': '₺ TL',
        'logo_path': null,
        'password': '123456'  // Varsayılan şifre
      };
    }
  }

  // Belirli bir alanı güncelle
  Future<bool> updateField(String field, dynamic value) async {
    try {
      // Mevcut profili al
      final profile = await getBusinessProfile();

      // Değeri güncelle
      profile[field] = value;

      // SharedPreferences'a kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey, json.encode(profile));

      // Önbelleği güncelle
      _profileCache = profile;

      return true;
    } catch (e) {
      debugPrint('İşletme bilgisi güncellenirken hata: $e');
      return false;
    }
  }

  // Tüm profili güncelle
  Future<bool> updateProfile({
    String? companyName,
    String? phone,
    String? address,
    String? email,
    String? storeName,
    String? note,
    String? taxNumber,
    String? currency,
    String? logoPath,
  }) async {
    try {
      // Mevcut profili al
      final profile = await getBusinessProfile();

      // Null olmayan değerleri güncelle
      if (companyName != null) profile['company_name'] = companyName;
      if (phone != null) profile['phone'] = phone;
      if (address != null) profile['address'] = address;
      if (email != null) profile['email'] = email;
      if (storeName != null) profile['store_name'] = storeName;
      if (note != null) profile['note'] = note;
      if (taxNumber != null) profile['tax_number'] = taxNumber;
      if (currency != null) profile['currency'] = currency;
      if (logoPath != null) profile['logo_path'] = logoPath;

      // SharedPreferences'a kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey, json.encode(profile));

      // Önbelleği güncelle
      _profileCache = profile;

      return true;
    } catch (e) {
      debugPrint('İşletme profili güncellenirken hata: $e');
      return false;
    }
  }

  // Şifre değiştirme
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      // Mevcut kullanıcı bilgilerini al
      final profile = await getBusinessProfile();
      
      // Mevcut şifreyi kontrol et
      final storedPassword = profile['password'] ?? '123456'; // Varsayılan şifre
      
      if (currentPassword != storedPassword) {
        debugPrint('Mevcut şifre yanlış');
        return false;
      }
      
      // Yeni şifreyi kaydet
      profile['password'] = newPassword;
      
      // SharedPreferences'a kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey, json.encode(profile));
      
      // Önbelleği güncelle
      _profileCache = profile;
      
      return true;
    } catch (e) {
      debugPrint('Şifre değiştirme hatası: $e');
      return false;
    }
  }
  
  // Önbelleği temizle (profil bilgilerinin yeniden yüklenmesini sağlar)
  void clearCache() {
    _profileCache = null;
  }
} 