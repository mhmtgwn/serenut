// bin/serenut_updater.dart
// Serenut Platform — CLI Independent Bootstrapper Update Utility

import 'dart:io';
import 'package:serenutos/infrastructure/services/update_v2/bootstrapper_executor.dart';

Future<void> main(List<String> args) async {
  final Map<String, String> parsedArgs = {};
  for (int i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      parsedArgs[args[i]] = args[i + 1];
    }
  }

  final pidStr = parsedArgs['--pid'];
  final targetPath = parsedArgs['--target'];
  final newFilePath = parsedArgs['--new-file'];
  final backupPath = parsedArgs['--backup'];

  if (targetPath == null || newFilePath == null || backupPath == null) {
    stdout.writeln('Usage: serenut_updater.exe --target <path> --new-file <path> --backup <path> [--pid <number>]');
    exit(BootstrapperResult.installFailed.exitCode);
  }

  final parentPid = pidStr != null ? int.tryParse(pidStr) : null;
  final executor = BootstrapperExecutor();

  final result = await executor.executeReplacement(
    targetFile: File(targetPath),
    newFile: File(newFilePath),
    backupFile: File(backupPath),
    parentPid: parentPid,
  );

  stdout.writeln('Installation ended with status: ${result.name} (Code: ${result.exitCode})');
  exit(result.exitCode);
}
