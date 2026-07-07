// lib/providers/recovery_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/recovery_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_recovery_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

final recoveryRepositoryProvider = Provider<IRecoveryRepository>((ref) {
  final dbManager = DatabaseManager();
  return SqliteRecoveryRepository(dbManager);
});
