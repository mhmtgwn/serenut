import 'dart:io';

class BackupEntryInfo {
  final String dbIdentifier; // 'legacy' | 'core_next'
  final String originalPath;
  final String backupPath;
  final int fileSizeBytes;
  final String sha256Hash;
  final bool integrityVerified;
  final DateTime backedUpAt;

  const BackupEntryInfo({
    required this.dbIdentifier,
    required this.originalPath,
    required this.backupPath,
    required this.fileSizeBytes,
    required this.sha256Hash,
    required this.integrityVerified,
    required this.backedUpAt,
  });

  Map<String, dynamic> toJson() => {
        'dbIdentifier': dbIdentifier,
        'originalPath': originalPath,
        'backupPath': backupPath,
        'fileSizeBytes': fileSizeBytes,
        'sha256Hash': sha256Hash,
        'integrityVerified': integrityVerified,
        'backedUpAt': backedUpAt.toIso8601String(),
      };
}

class DualDatabaseBackupResult {
  final bool isSuccess;
  final BackupEntryInfo? legacyBackup;
  final BackupEntryInfo? coreNextBackup;
  final String? manifestPath;
  final String? errorMessage;
  final String? failedDatabase; // 'legacy' | 'core_next'
  final String? failedStep;
  final String atomicityLimitationNotice;

  const DualDatabaseBackupResult({
    required this.isSuccess,
    this.legacyBackup,
    this.coreNextBackup,
    this.manifestPath,
    this.errorMessage,
    this.failedDatabase,
    this.failedStep,
    this.atomicityLimitationNotice =
        'Each database backup is internally consistent via SQLite VACUUM INTO / WAL checkpoint. '
        'Cross-database atomicity between independent SQLite database files is not guaranteed by SQLite.',
  });

  Map<String, dynamic> toJson() => {
        'isSuccess': isSuccess,
        'legacyBackup': legacyBackup?.toJson(),
        'coreNextBackup': coreNextBackup?.toJson(),
        'manifestPath': manifestPath,
        'errorMessage': errorMessage,
        'failedDatabase': failedDatabase,
        'failedStep': failedStep,
        'atomicityLimitationNotice': atomicityLimitationNotice,
      };
}

abstract class IBackupService {
  Future<String> backupDatabase();
  Future<DualDatabaseBackupResult> backupDualDatabases({
    String? customBackupDir,
    bool requireBoth = false,
  });
  Future<void> autoBackupIfNeeded();
  Future<void> shareBackup(String backupPath);
  Future<List<File>> getBackupFiles();
  Future<bool> restoreDatabase(String backupPath, [String? recoveryKey]);
  Future<void> clearAllBackups();
}
