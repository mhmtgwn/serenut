// lib/domain/repositories/recovery_repository.dart

abstract class IRecoveryRepository {
  Future<List<Map<String, dynamic>>> getDeletedItems(String type);
  Future<void> restore(String type, String id);
  Future<void> purge(String type, String id);
}
