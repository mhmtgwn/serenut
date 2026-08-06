import 'printing_models.dart';

abstract interface class PrintingRepository {
  Future<List<PrintDesignProfile>> getDesignProfiles(PrintDocumentKind kind);
  Future<void> saveDesignProfile(PrintDesignProfile profile);
  Future<List<PrinterDeviceProfile>> getDevices();
  Future<PrinterDeviceProfile?> getDevice(String id);
  Future<void> saveDevice(PrinterDeviceProfile device);
  Future<void> deleteDevice(String id);
  Future<PrinterRoute?> getRoute(PrintDocumentKind kind);
  Future<void> saveRoute(PrinterRoute route);
  Future<void> createJob(PrintJobRecord job);
  Future<PrintJobRecord> enqueue({
    required PrintDocumentKind kind,
    required String payloadJson,
    int copies = 1,
  });
  Future<PrintJobRecord> enqueueForDevice({
    required PrintDocumentKind kind,
    required String deviceId,
    required String payloadJson,
    int copies = 1,
  });
  Future<PrintJobRecord?> getJob(String id);
  Future<List<PrintJobRecord>> getJobs();
  Future<PrintJobRecord?> claimNext(String deviceId);
  Future<void> markRendered(String id, String checksum);
  Future<void> markDelivered(String id, String observationJson);
  Future<void> markDeliveryUncertain(String id, String message);
  Future<void> markAttemptFailed(
    String id, {
    required String errorCode,
    required String errorMessage,
    required bool retryable,
  });
  Future<void> cancelJob(String id);
  Future<void> retryJob(String id);
  Future<void> confirmUncertainDelivery(String id, {required bool printed});
  Future<void> requestPhysicalConfirmation(String id);
  Future<void> resolvePhysicalConfirmation(String id, {required bool passed});
  Future<PrintRecoverySummary> recoverInterruptedJobs();
  Future<List<PrintJobRecord>> getRecoverableJobs();
}
