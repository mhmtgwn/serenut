// lib/domain/services/update_v2/policy_engine.dart
// Serenut Platform — Extensible Policy Engine for Update Decisions

import 'dart:io';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';

abstract class ProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
}

class RealProcessRunner implements ProcessRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    return Process.run(executable, arguments);
  }
}

class PolicyEvaluationResult {
  final bool isPassed;
  final String? errorCode; // e.g., 'UPD-005'
  final String? reason;

  PolicyEvaluationResult({
    required this.isPassed,
    this.errorCode,
    this.reason,
  });

  factory PolicyEvaluationResult.pass() => PolicyEvaluationResult(isPassed: true);

  factory PolicyEvaluationResult.fail(String code, String reason) =>
      PolicyEvaluationResult(isPassed: false, errorCode: code, reason: reason);
}

abstract class PolicyEngine {
  Future<PolicyEvaluationResult> evaluate({
    required ReleaseRules rules,
    required bool isSalesCheckoutActive,
  });
}

class DefaultPolicyEngine implements PolicyEngine {
  final ProcessRunner _processRunner;
  final String _currentPlatform;

  DefaultPolicyEngine({
    ProcessRunner? processRunner,
    String? platformOverride,
  })  : _processRunner = processRunner ?? RealProcessRunner(),
        _currentPlatform = platformOverride ?? (Platform.isAndroid ? 'android' : 'windows');

  @override
  Future<PolicyEvaluationResult> evaluate({
    required ReleaseRules rules,
    required bool isSalesCheckoutActive,
  }) async {
    // 1. Check Active POS Sales Transaction Guard (Blocking updates during checkout)
    if (isSalesCheckoutActive) {
      return PolicyEvaluationResult.fail(
        'UPD-005',
        'Update blocked: Active checkout / POS transaction is currently running in memory.',
      );
    }

    // 2. Evaluate Operating System / Architecture Rules
    if (_currentPlatform == 'windows') {
      if (!rules.supportedArchitectures.contains('x64')) {
        return PolicyEvaluationResult.fail(
          'UPD-005',
          'Update blocked: CPU architecture is unsupported by target release.',
        );
      }

      // Check RAM Capacity (Min requirements evaluation, e.g. rules.minRamMb)
      try {
        final res = await _processRunner.run('wmic', ['computersystem', 'get', 'TotalPhysicalMemory']);
        if (res.exitCode == 0) {
          final lines = res.stdout.toString().split('\n');
          if (lines.length > 1) {
            final rawBytes = int.tryParse(lines[1].trim()) ?? 0;
            final double ramMb = rawBytes / (1024 * 1024);
            if (ramMb < rules.minRamMb) {
              return PolicyEvaluationResult.fail(
                'UPD-005',
                'Update blocked: Insufficient RAM memory capacity ($ramMb MB / Required: ${rules.minRamMb} MB).',
              );
            }
          }
        }
      } catch (_) {
        // Fallback soft-pass on process execution error
      }

      // Check Disk Space (Min requirements evaluation, e.g. rules.minFreeDiskMb)
      try {
        final res = await _processRunner.run('powershell', ['-Command', '(Get-Volume -DriveLetter C).SizeRemaining']);
        if (res.exitCode == 0) {
          final bytes = int.tryParse(res.stdout.toString().trim()) ?? 0;
          final double freeMb = bytes / (1024 * 1024);
          if (freeMb < rules.minFreeDiskMb) {
            return PolicyEvaluationResult.fail(
              'UPD-005',
              'Update blocked: Insufficient disk space ($freeMb MB / Required: ${rules.minFreeDiskMb} MB).',
            );
          }
        }
      } catch (_) {
        // Fallback soft-pass on process execution error
      }
    }

    return PolicyEvaluationResult.pass();
  }
}
