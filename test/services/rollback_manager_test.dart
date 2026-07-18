import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/rollback_manager.dart';

void main() {
  test('per-user installation does not require administrator privileges', () {
    final result = SystemSpecCheckResult(
      hasRequiredSpace: true,
      hasRequiredRam: true,
      hasAdminPrivileges: false,
      freeSpaceGb: 1,
      issues: const [],
    );

    expect(result.isAllPass, isTrue);
  });
}
