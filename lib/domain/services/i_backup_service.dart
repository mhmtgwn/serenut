import 'dart:io';

abstract class IBackupService {
  Future<String> backupDatabase();
  Future<void> autoBackupIfNeeded();
  Future<void> shareBackup(String backupPath);
  Future<List<File>> getBackupFiles();
  Future<bool> restoreDatabase(String backupPath, [String? recoveryKey]);
  Future<void> clearAllBackups();
}
