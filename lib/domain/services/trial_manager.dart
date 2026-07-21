// lib/domain/services/trial_manager.dart
// Serenut OS — Entitlement Cache Manager
// Relies solely on backend-authoritative subscription state.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum EntitlementState {
  active,
  graceActive,
  graceExpired,
  revoked,
  unknown,
  bootstrapPending
}

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
      return EntitlementState.bootstrapPending;
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

  String getSubscriptionStatus() {
    final sub = _getCache();
    return sub?['status'] as String? ?? 'unknown';
  }

  /// Returns true ONLY if subscription is in trial status ('trialing' or 'trial')
  bool isTrialActive() {
    final status = getSubscriptionStatus();
    final state = getEntitlementState();
    return (status == 'trialing' || status == 'trial') &&
        (state == EntitlementState.active || state == EntitlementState.graceActive);
  }

  /// Returns true if paid commercial subscription is active ('active')
  bool isCommercialActive() {
    final status = getSubscriptionStatus();
    final state = getEntitlementState();
    return status == 'active' &&
        (state == EntitlementState.active || state == EntitlementState.graceActive);
  }

  /// Returns true if ANY entitlement (trial OR commercial) is active
  bool isEntitlementActive() {
    final state = getEntitlementState();
    return state == EntitlementState.active ||
        state == EntitlementState.graceActive;
  }

  Future<bool> isTrialActiveAsync() async {
    return isTrialActive();
  }

  Future<bool> isEntitlementActiveAsync() async {
    return isEntitlementActive();
  }

  int getRemainingDays() {
    final sub = _getCache();
    if (sub == null) {
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
