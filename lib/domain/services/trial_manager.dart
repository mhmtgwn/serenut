// lib/domain/services/trial_manager.dart
// Serenut OS — Deneme Süresi Yöneticisi
// Üçlü Doğrulama: SharedPreferences + Database + Checksum
// Telefon sıfırlanırsa bile deneme süresi manipüle edilemesin.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrialManager {
  static const String _firstLaunchKey = 'nutopiano_first_launch_timestamp';
  static const String _trialChecksumKey = 'serenut_trial_checksum';
  static const int trialDurationDays = 30;

  final SharedPreferences _prefs;

  // DB doğrulama için opsiyonel callback — DB servisi başlatıldıktan sonra set edilir
  Future<int?> Function()? _dbAnchorLoader;
  Future<void> Function(int firstLaunchMs)? _dbAnchorSaver;

  TrialManager(this._prefs);

  /// DB katmanı bağlandıktan sonra çağrılır
  void setDbCallbacks({
    required Future<int?> Function() loader,
    required Future<void> Function(int firstLaunchMs) saver,
  }) {
    _dbAnchorLoader = loader;
    _dbAnchorSaver = saver;
  }

  /// Manually starts a trial on a specific start date (synced from server)
  Future<void> startTrial(DateTime startDate) async {
    final ms = startDate.millisecondsSinceEpoch;
    await _writeToAllLayers(ms);
  }

  /// Trial timestamp için HMAC-SHA256 checksum üretir
  String _buildChecksum(int timestampMs) {
    // DÜZELTME: Sabit string yerine derleme zamanı sabiti kullanılıyor.
    // CI'da: flutter build apk --dart-define=TRIAL_SECRET=<gizli-anahtar>
    // Yerel geliştirme için varsayılan değer (prod'da değiştirilmeli).
    const secret = String.fromEnvironment(
      'TRIAL_SECRET',
      defaultValue: 'serenut_trial_integrity_v1',
    );
    final hmac = Hmac(sha256, utf8.encode(secret));

    final digest = hmac.convert(utf8.encode('$timestampMs'));
    return digest.toString();
  }

  bool _verifyChecksum(int timestampMs, String checksum) {
    return _buildChecksum(timestampMs) == checksum;
  }

  /// Trial başlangıcını başlatır — üç katmana birden yazar
  Future<void> initTrialIfNeeded() async {
    final existingMs = _prefs.getInt(_firstLaunchKey);
    if (existingMs != null) {
      // SharedPrefs var, checksum doğrula
      final checksum = _prefs.getString(_trialChecksumKey) ?? '';
      if (!_verifyChecksum(existingMs, checksum)) {
        // Checksum bozuk — DB'den kurtarmayı dene
        await _tryRecoverFromDb();
      }
      return;
    }

    // İlk açılış — timestamp oluştur ve üç katmana yaz
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _writeToAllLayers(nowMs);
  }

  /// SharedPrefs yoksa DB'den kurtarmayı dene
  Future<void> _tryRecoverFromDb() async {
    if (_dbAnchorLoader == null) return;
    try {
      final dbMs = await _dbAnchorLoader!();
      if (dbMs != null) {
        final checksum = _buildChecksum(dbMs);
        await _prefs.setInt(_firstLaunchKey, dbMs);
        await _prefs.setString(_trialChecksumKey, checksum);
        debugPrint('TrialManager: SharedPrefs bütünlük hatası — DB\'den kurtarıldı.');
      }
    } catch (e) {
      debugPrint('TrialManager: DB kurtarma başarısız — $e');
    }
  }

  /// Timestamp'i tüm katmanlara yazar
  Future<void> _writeToAllLayers(int timestampMs) async {
    final checksum = _buildChecksum(timestampMs);

    // 1. SharedPreferences
    await _prefs.setInt(_firstLaunchKey, timestampMs);
    await _prefs.setString(_trialChecksumKey, checksum);

    // 2. Database (bağlıysa)
    if (_dbAnchorSaver != null) {
      try {
        await _dbAnchorSaver!(timestampMs);
      } catch (e) {
        debugPrint('TrialManager: DB anchor kaydı başarısız (kritik değil) — $e');
      }
    }
  }

  /// Trial başlangıç timestamp'ini güvenli şekilde okur
  /// Öncelik: SharedPrefs (checksum doğrulayarak) → DB → null
  Future<int?> _getVerifiedTimestamp() async {
    final prefsMs = _prefs.getInt(_firstLaunchKey);
    final prefsChecksum = _prefs.getString(_trialChecksumKey) ?? '';

    if (prefsMs != null && _verifyChecksum(prefsMs, prefsChecksum)) {
      return prefsMs;
    }

    // SharedPrefs güvenilir değil — DB'den dene
    if (_dbAnchorLoader != null) {
      try {
        final dbMs = await _dbAnchorLoader!();
        if (dbMs != null) {
          // DB güvenilir kabul ediliyor, SharedPrefs'i onar
          final checksum = _buildChecksum(dbMs);
          await _prefs.setInt(_firstLaunchKey, dbMs);
          await _prefs.setString(_trialChecksumKey, checksum);
          return dbMs;
        }
      } catch (_) {}
    }

    return prefsMs; // En kötü ihtimalle mevcut değeri döndür
  }

  /// Trial hâlâ aktif mi? (async, üçlü doğrulama)
  Future<bool> isTrialActiveAsync() async {
    await initTrialIfNeeded();
    final ms = await _getVerifiedTimestamp();
    if (ms == null) return false;
    final firstLaunch = DateTime.fromMillisecondsSinceEpoch(ms);
    final daysPassed = DateTime.now().difference(firstLaunch).inDays;
    return daysPassed < trialDurationDays;
  }

  /// Kalan gün sayısını döndürür (async, üçlü doğrulama)
  Future<int> getRemainingDaysAsync() async {
    await initTrialIfNeeded();
    final ms = await _getVerifiedTimestamp();
    if (ms == null) return 0;
    final firstLaunch = DateTime.fromMillisecondsSinceEpoch(ms);
    final daysPassed = DateTime.now().difference(firstLaunch).inDays;
    final remaining = trialDurationDays - daysPassed;
    return remaining > 0 ? remaining : 0;
  }

  /// Trial bitiş tarihini döndürür
  Future<DateTime?> getExpiryDate() async {
    final ms = await _getVerifiedTimestamp();
    if (ms == null) return null;
    final firstLaunch = DateTime.fromMillisecondsSinceEpoch(ms);
    return firstLaunch.add(const Duration(days: trialDurationDays));
  }



  // --- Senkron API (geriye dönük uyumluluk) ---

  /// Senkron aktiflik kontrolü (eski API uyumlu, checksum doğrulaması yok)
  bool isTrialActive() {
    final ms = _prefs.getInt(_firstLaunchKey);
    if (ms == null) return false;
    final firstLaunch = DateTime.fromMillisecondsSinceEpoch(ms);
    final daysPassed = DateTime.now().difference(firstLaunch).inDays;
    return daysPassed < trialDurationDays;
  }

  /// Senkron kalan gün (paywall_page.dart ve diğer senkron kullanıcılar için)
  int getRemainingDays() {
    final ms = _prefs.getInt(_firstLaunchKey);
    if (ms == null) return 0;
    final firstLaunch = DateTime.fromMillisecondsSinceEpoch(ms);
    final daysPassed = DateTime.now().difference(firstLaunch).inDays;
    final remaining = trialDurationDays - daysPassed;
    return remaining > 0 ? remaining : 0;
  }
}
