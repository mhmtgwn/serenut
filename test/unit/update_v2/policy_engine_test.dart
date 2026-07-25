// test/unit/update_v2/policy_engine_test.dart
// Serenut Platform — Extensible Policy Engine Unit Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';
import 'package:serenutos/domain/services/update_v2/policy_engine.dart';

class MockProcessRunner implements ProcessRunner {
  int ramBytes = 8589934592; // 8 GB
  int diskBytes = 10737418240; // 10 GB
  int ramExitCode = 0;
  int diskExitCode = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (executable == 'wmic') {
      return ProcessResult(0, ramExitCode, 'TotalPhysicalMemory\n$ramBytes\n', '');
    } else if (executable == 'powershell') {
      return ProcessResult(0, diskExitCode, '$diskBytes\n', '');
    }
    return ProcessResult(0, 0, '', '');
  }
}

void main() {
  group('DefaultPolicyEngine Tests', () {
    late MockProcessRunner mockRunner;
    late PolicyEngine policyEngine;
    late ReleaseRules rules;

    setUp(() {
      mockRunner = MockProcessRunner();
      policyEngine = DefaultPolicyEngine(
        processRunner: mockRunner,
        platformOverride: 'windows',
      );
      rules = const ReleaseRules(
        isMandatory: false,
        allowRollback: true,
        minFreeDiskMb: 300,
        minRamMb: 2048,
        supportedArchitectures: ['x64'],
      );
    });

    test('Passes when all system specifications and rules are satisfied', () async {
      final result = await policyEngine.evaluate(
        rules: rules,
        isSalesCheckoutActive: false,
      );
      expect(result.isPassed, isTrue);
    });

    test('Fails with UPD-005 when active sales POS checkout is running', () async {
      final result = await policyEngine.evaluate(
        rules: rules,
        isSalesCheckoutActive: true,
      );
      expect(result.isPassed, isFalse);
      expect(result.errorCode, equals('UPD-005'));
      expect(result.reason, contains('Active checkout / POS transaction'));
    });

    test('Fails with UPD-005 when RAM is below minimum requirements', () async {
      mockRunner.ramBytes = 1073741824; // 1 GB (Required: 2048 MB)
      final result = await policyEngine.evaluate(
        rules: rules,
        isSalesCheckoutActive: false,
      );
      expect(result.isPassed, isFalse);
      expect(result.errorCode, equals('UPD-005'));
      expect(result.reason, contains('Insufficient RAM memory'));
    });

    test('Fails with UPD-005 when Disk Space is below minimum requirements', () async {
      mockRunner.diskBytes = 104857600; // 100 MB (Required: 300 MB)
      final result = await policyEngine.evaluate(
        rules: rules,
        isSalesCheckoutActive: false,
      );
      expect(result.isPassed, isFalse);
      expect(result.errorCode, equals('UPD-005'));
      expect(result.reason, contains('Insufficient disk space'));
    });

    test('Fails with UPD-005 when CPU architecture is unsupported', () async {
      final unsupportedRules = const ReleaseRules(
        isMandatory: false,
        allowRollback: true,
        minFreeDiskMb: 300,
        minRamMb: 2048,
        supportedArchitectures: ['arm64'], // Windows x64 host
      );
      final result = await policyEngine.evaluate(
        rules: unsupportedRules,
        isSalesCheckoutActive: false,
      );
      expect(result.isPassed, isFalse);
      expect(result.errorCode, equals('UPD-005'));
      expect(result.reason, contains('CPU architecture is unsupported'));
    });
  });
}
