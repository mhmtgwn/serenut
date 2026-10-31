// lib/presentation/controllers/backup_controller.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/service_providers.dart';

class BackupState {
  final List<File> backupFiles;
  final bool isLoading;
  final String? errorMessage;

  const BackupState({
    this.backupFiles = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  BackupState copyWith({
    List<File>? backupFiles,
    bool? isLoading,
    String? errorMessage,
  }) {
    return BackupState(
      backupFiles: backupFiles ?? this.backupFiles,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class BackupController extends StateNotifier<BackupState> {
  final Ref _ref;

  BackupController(this._ref) : super(const BackupState());

  Future<List<File>> getBackupFiles() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final files = await _ref.read(backupServiceProvider).getBackupFiles();
      state = state.copyWith(backupFiles: files, isLoading: false);
      return files;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<String> backupDatabase() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final path = await _ref.read(backupServiceProvider).backupDatabase();
      await getBackupFiles();
      return path;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> restoreDatabase(String path) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _ref.read(backupServiceProvider).restoreDatabase(path);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> shareBackup(String path) async {
    await _ref.read(backupServiceProvider).shareBackup(path);
  }

  Future<void> clearAllBackups() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _ref.read(backupServiceProvider).clearAllBackups();
      state = state.copyWith(backupFiles: const [], isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }
}

final backupControllerProvider =
    StateNotifierProvider<BackupController, BackupState>((ref) {
  return BackupController(ref);
});

