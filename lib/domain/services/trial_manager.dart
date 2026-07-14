// lib/domain/services/trial_manager.dart
// Serenut OS — Entitlement Cache Manager
// Relies solely on backend-authoritative subscription state.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EntitlementState { active, graceActive, graceExpired, revoked, unknown }

class TrialManager {
  static const String _subCacheKey = 'serenut_subscription_cache';

  final SharedPreferences _prefs;

  TrialManager(this._prefs);

  /// Saves the subscription payload from backend into local cache
  Future<void> cacheSubscription(Map<String, dynamic> subData) async {
    await _prefs.setString(_subCacheKey, jsonEncode(subData));
  }

  Map<String, dynamic>? _getCache() {
    final str = _prefs.getString(_subCacheKey);
    if (str == null) return null;
    try {
      return jsonDecode(str);
    } catch (_) {
      return null;
    }
  }

  EntitlementState getEntitlementState() {
    final sub = _getCache();
    if (sub == null) {
      // PHASE 1: Legacy Migration & Backward Compatibility
      // Fallback for existing devices that haven't synced yet
      final firstLaunchMs = _prefs.getInt('nutopiano_first_launch_timestamp');
      if (firstLaunchMs != null) {
        final firstLaunch = DateTime.fromMillisecondsSinceEpoch(firstLaunchMs);
        final now = DateTime.now();
        if (now.difference(firstLaunch).inDays <= 30) {
          return EntitlementState.active;
        } else {
          return EntitlementState
              .graceExpired; // Or we could let it be graceActive, but strict is 30 days
        }
      }
      return EntitlementState.unknown;
    }

    final status = sub['status'] as String?;
    if (status == 'canceled' || status == 'revoked') {
      return EntitlementState.revoked;
    }

    final graceHours = sub['grace_hours_override'] as int? ?? 72;
    DateTime? expirationDate;

    if (status == 'trialing') {
      final trialEndsStr = sub['trial_ends_at'] as String?;
      if (trialEndsStr != null) {
        expirationDate = DateTime.tryParse(trialEndsStr);
      }
    } else {
      final currentPeriodEndStr = sub['current_period_end'] as String?;
      if (currentPeriodEndStr != null) {
        expirationDate = DateTime.tryParse(currentPeriodEndStr);
      }
    }

    if (expirationDate == null) return EntitlementState.unknown;

    final now = DateTime.now().toUtc();
    if (now.isBefore(expirationDate)) {
      return EntitlementState.active;
    }

    final graceExpiration = expirationDate.add(Duration(hours: graceHours));
    if (now.isBefore(graceExpiration)) {
      return EntitlementState.graceActive;
    }

    return EntitlementState.graceExpired;
  }

  bool isTrialActive() {
    return getEntitlementState() == EntitlementState.active ||
        getEntitlementState() == EntitlementState.graceActive;
  }

  Future<bool> isTrialActiveAsync() async {
    return isTrialActive();
  }

  int getRemainingDays() {
    final sub = _getCache();
    if (sub == null) {
      final firstLaunchMs = _prefs.getInt('nutopiano_first_launch_timestamp');
      if (firstLaunchMs != null) {
        final firstLaunch = DateTime.fromMillisecondsSinceEpoch(firstLaunchMs);
        final elapsed = DateTime.now().difference(firstLaunch).inDays;
        return (30 - elapsed).clamp(0, 30);
      }
      return 0;
    }

    final status = sub['status'] as String?;
    DateTime? expirationDate;
    if (status == 'trialing') {
      final trialEndsStr = sub['trial_ends_at'] as String?;
      if (trialEndsStr != null) {
        expirationDate = DateTime.tryParse(trialEndsStr);
      }
    } else {
      final currentPeriodEndStr = sub['current_period_end'] as String?;
      if (currentPeriodEndStr != null) {
        expirationDate = DateTime.tryParse(currentPeriodEndStr);
      }
    }

    if (expirationDate == null) return 0;

    final remaining = expirationDate.difference(DateTime.now().toUtc()).inDays;
    return remaining > 0 ? remaining : 0;
  }

  Future<int> getRemainingDaysAsync() async {
    return getRemainingDays();
  }

  Future<DateTime?> getExpiryDate() async {
    final sub = _getCache();
    if (sub == null) return null;

    final status = sub['status'] as String?;
    if (status == 'trialing') {
      final trialEndsStr = sub['trial_ends_at'] as String?;
      if (trialEndsStr != null) return DateTime.tryParse(trialEndsStr);
    } else {
      final currentPeriodEndStr = sub['current_period_end'] as String?;
      if (currentPeriodEndStr != null)
        return DateTime.tryParse(currentPeriodEndStr);
    }
    return null;
  }

  // No-op for backwards compatibility during transition
  void setDbCallbacks({required dynamic loader, required dynamic saver}) {}
  Future<void> startTrial(DateTime startDate) async {}
  Future<void> initTrialIfNeeded() async {}
}
