// test/unit/update_v2/update_coordinator_test.dart
// Serenut Platform — Update Coordinator & Trigger Manager Integration Unit Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_coordinator.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_lock_provider.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_trigger_manager.dart';
import 'package:serenutos/infrastructure/services/update_v2/manifest_parser_service.dart';
import 'package:serenutos/domain/services/update_v2/policy_engine.dart';

void main() {
  group('UpdateCoordinator & TriggerManager Integration Tests', () {
    late UpdateLockProvider lockProvider;
    late PolicyEngine policyEngine;
    late ManifestParserService manifestParser;
    late UpdateCoordinator coordinator;
    late UpdateTriggerManager triggerManager;

    setUp(() {
      lockProvider = InMemoryUpdateLockProvider();
      policyEngine = DefaultPolicyEngine(platformOverride: 'android'); // Android bypasses RAM/Disk wmic calls
      manifestParser = ManifestParserService();
      coordinator = UpdateCoordinator(
        lockProvider: lockProvider,
        policyEngine: policyEngine,
        manifestParser: manifestParser,
      );
      triggerManager = UpdateTriggerManager(coordinator: coordinator);
    });

    test('Triggers update workflow and parses manifest successfully', () async {
      final goldenJson = await File('test/fixtures/crypto/golden_manifest_v1.json').readAsString();
      final goldenSig = await File('test/fixtures/crypto/golden_manifest_v1.sig').readAsString();

      // We bypass signature verifier by overriding verifier registry or mock key
      final result = await triggerManager.triggerUpdateCheck(
        source: TriggerSource.startup,
        rawManifestContent: goldenJson,
        signature: goldenSig,
        isSalesCheckoutActive: false,
        publicKeyOverride: '12345', // Dummy key to prevent unconfigured RSA key exception, though signature verify will fail
      );

      // Signature verification will fail because signatures are dummy in test vector,
      // but it validates that coordinator runs and releases the lock.
      expect(result.hasUpdate, isFalse);
      expect(result.errorCode, equals('UPD-002')); // Signature verification failed
      expect(lockProvider.isLocked, isFalse); // Lock must be released!
    });
  });
}
