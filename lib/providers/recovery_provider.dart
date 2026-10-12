// lib/providers/recovery_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/recovery_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_recovery_repository.dart';
import 'package:serenutos/providers/database_provider.dart';

final recoveryRepositoryProvider = Provider<IRecoveryRepository>((ref) {
  final dbManager = ref.watch(databaseManagerProvider);
  return SqliteRecoveryRepository(dbManager);
});
