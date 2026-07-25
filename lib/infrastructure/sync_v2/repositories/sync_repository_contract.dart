abstract class ISyncRepositoryV2<T> {
  // Local CRUD Operations (Offline Instant)
  Future<void> insertLocal(T entity, {required String clientMutationId, int priority = 1});
  Future<void> updateLocal(T entity, {required String clientMutationId, int priority = 1});
  Future<void> deleteLocal(String id, {required String clientMutationId, int priority = 0});

  // Reactive UI Streams
  Stream<List<T>> watchAll();
  Stream<T?> watchById(String id);

  // Recovery & Rollback
  Future<void> rollbackLocalMutation(String clientMutationId);
}
