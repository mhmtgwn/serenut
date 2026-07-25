// test/unit/update_v2/bootstrapper_executor_test.dart
// Serenut Platform — Bootstrapper Executor Unit Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/update_v2/bootstrapper_executor.dart';

void main() {
  group('BootstrapperExecutor Tests', () {
    late File targetFile;
    late File newFile;
    late File backupFile;
    late BootstrapperExecutor executor;

    setUp(() async {
      targetFile = File(path('serenutos.exe'));
      newFile = File(path('serenutos.new'));
      backupFile = File(path('serenutos.bak'));

      if (await targetFile.exists()) await targetFile.delete();
      if (await newFile.exists()) await newFile.delete();
      if (await backupFile.exists()) await backupFile.delete();

      await targetFile.writeAsString('ORIGINAL_EXE_CONTENT');
      await newFile.writeAsString('NEW_EXE_CONTENT');
      executor = BootstrapperExecutor();
    });

    tearDown(() async {
      if (await targetFile.exists()) await targetFile.delete();
      if (await newFile.exists()) await newFile.delete();
      if (await backupFile.exists()) await backupFile.delete();
    });

    test('Replaces target file atomically and cleans up backup', () async {
      final result = await executor.executeReplacement(
        targetFile: targetFile,
        newFile: newFile,
        backupFile: backupFile,
      );

      expect(result, equals(BootstrapperResult.success));
      expect(await targetFile.readAsString(), equals('NEW_EXE_CONTENT'));
      expect(await backupFile.exists(), isFalse);
    });

    test('Rolls back to original target if copy fails', () async {
      // Simulate copy failure by deleting new file before execution
      await newFile.delete();

      final result = await executor.executeReplacement(
        targetFile: targetFile,
        newFile: newFile,
        backupFile: backupFile,
      );

      // Should fail to copy and restore backup (which is the original target content)
      expect(result, equals(BootstrapperResult.rollbackCompleted));
      expect(await targetFile.readAsString(), equals('ORIGINAL_EXE_CONTENT'));
    });
  });
}

String path(String name) {
  return Directory.systemTemp.path + Platform.pathSeparator + name;
}
