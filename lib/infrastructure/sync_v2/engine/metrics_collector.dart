class SyncMetricsCollector {
  int pushCount = 0;
  int pullCount = 0;
  int retryCount = 0;
  int conflictCount = 0;
  int queueDepth = 0;
  int socketReconnects = 0;
  int snapshotDownloads = 0;
  int totalSyncDurationMs = 0;

  void recordPush() => pushCount++;
  void recordPull() => pullCount++;
  void recordRetry() => retryCount++;
  void recordConflict() => conflictCount++;
  void updateQueueDepth(int depth) => queueDepth = depth;
  void recordSocketReconnect() => socketReconnects++;
  void recordSnapshotDownload() => snapshotDownloads++;
  void recordSyncDuration(int ms) => totalSyncDurationMs += ms;

  Map<String, dynamic> toJson() {
    return {
      'push_count': pushCount,
      'pull_count': pullCount,
      'retry_count': retryCount,
      'conflict_count': conflictCount,
      'queue_depth': queueDepth,
      'socket_reconnects': socketReconnects,
      'snapshot_downloads': snapshotDownloads,
      'total_sync_duration_ms': totalSyncDurationMs,
    };
  }

  void reset() {
    pushCount = 0;
    pullCount = 0;
    retryCount = 0;
    conflictCount = 0;
    queueDepth = 0;
    socketReconnects = 0;
    snapshotDownloads = 0;
    totalSyncDurationMs = 0;
  }
}
