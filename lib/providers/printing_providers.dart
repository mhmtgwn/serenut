import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_application_service.dart';
import 'package:serenutos/infrastructure/printing/printing_renderers.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/printing/printing_transports.dart';
import 'package:serenutos/infrastructure/printing/physical_print_test_service.dart';
import 'package:serenutos/infrastructure/printing/sqlite_printing_application_service.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_printing_repository.dart';
import 'package:serenutos/providers/database_provider.dart';

final printingRepositoryProvider = Provider<PrintingRepository>((ref) {
  return SqlitePrintingRepository(ref.watch(dbGatewayProvider));
});

final printQueueCoordinatorProvider = Provider<PrintQueueCoordinator>((ref) {
  final coordinator = PrintQueueCoordinator(
    repository: ref.watch(printingRepositoryProvider),
    renderers: [
      LegacyRawPrintRenderer(),
      EscPosReceiptRenderer(),
      TsplProductLabelRenderer(),
      TsplOrderLabelRenderer(),
    ],
    transports: [
      TcpPrintTransport(),
      WindowsSpoolerPrintTransport(),
      BluetoothPrintTransport(),
      EmbeddedPrintTransport(),
    ],
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final printingRuntimeProvider = Provider<PrintingRuntime>((ref) {
  final runtime = PrintingRuntime(
    repository: ref.watch(printingRepositoryProvider),
    coordinator: ref.watch(printQueueCoordinatorProvider),
  );
  ref.onDispose(() => unawaited(runtime.dispose()));
  return runtime;
});

final printingRuntimeSnapshotProvider =
    StreamProvider<PrintingRuntimeSnapshot>((ref) {
  return ref.watch(printingRuntimeProvider).snapshots;
});

final physicalPrintTestServiceProvider =
    Provider<PhysicalPrintTestService>((ref) {
  return PhysicalPrintTestService(
    repository: ref.watch(printingRepositoryProvider),
    runtime: ref.watch(printingRuntimeProvider),
  );
});

final printingApplicationServiceProvider =
    Provider<PrintingApplicationService>((ref) {
  return SqlitePrintingApplicationService(
    repository: ref.watch(printingRepositoryProvider),
    runtime: ref.watch(printingRuntimeProvider),
  );
});

final printDesignProfilesProvider =
    FutureProvider.family<List<PrintDesignProfile>, PrintDocumentKind>(
        (ref, kind) {
  return ref.watch(printingRepositoryProvider).getDesignProfiles(kind);
});

final activePrinterDeviceProvider =
    FutureProvider.family<PrinterDeviceProfile?, PrintDocumentKind>(
        (ref, kind) async {
  final repository = ref.watch(printingRepositoryProvider);
  final route = await repository.getRoute(kind);
  return route == null ? null : repository.getDevice(route.deviceId);
});
