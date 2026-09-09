import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/trial_manager.dart';

void main() {
  group('TrialManager Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('New installation fails closed until backend entitlement arrives',
        () async {
      final manager = TrialManager(prefs);

      expect(manager.getEntitlementState(), EntitlementState.unknown);
      expect(manager.isTrialActive(), isFalse);
      expect(manager.getRemainingDays(), equals(0));
    });

    test('Missing entitlement remains closed across repeated checks', () async {
      final manager = TrialManager(prefs);

      expect(manager.getEntitlementState(), EntitlementState.unknown);
      expect(manager.getEntitlementState(), EntitlementState.unknown);
    });

    test('Unsigned local subscription cache cannot grant access', () async {
      await prefs.setString(
        'serenut_subscription_cache',
        '{"status":"active","current_period_end":"2099-01-01T00:00:00Z"}',
      );
      final manager = TrialManager(prefs);

      expect(manager.isCommercialActive(), isFalse);
      expect(manager.isEntitlementActive(), isFalse);
    });

    test('Trial expires after 30 days', () async {
      final manager = TrialManager(prefs);
      final pastDate =
          DateTime.now().toUtc().subtract(const Duration(days: 31));
      await manager.cacheSubscription({
        'status': 'trialing',
        'trial_started_at':
            pastDate.subtract(const Duration(days: 30)).toIso8601String(),
        'trial_ends_at': pastDate.toIso8601String(),
        'grace_hours_override': 72,
      });

      expect(manager.isTrialActive(), isFalse);
      expect(manager.getRemainingDays(), equals(0));
    });
  });
}
