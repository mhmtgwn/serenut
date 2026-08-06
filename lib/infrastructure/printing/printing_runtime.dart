import 'dart:async';

import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';

class PrintingRuntimeSnapshot {
  final bool running;
  final bool processing;
  final PrintRecoverySummary? recovery;
  final PrintCoordinatorEvent? latestEvent;
  final String? error;

  const PrintingRuntimeSnapshot({
    required this.running,
    required this.processing,
    this.recovery,
    this.latestEvent,
    this.error,
  });
}

class PrintingRuntime {
  final PrintingRepository repository;
  final PrintQueueCoordinator coordinator;
  final Duration pollInterval;
  final _snapshots = StreamController<PrintingRuntimeSnapshot>.broadcast();

  Timer? _timer;
  StreamSubscription<PrintCoordinatorEvent>? _eventSubscription;
  bool _processing = false;
  bool _running = false;
  PrintRecoverySummary? _recovery;
  PrintCoordinatorEvent? _latestEvent;
  String? _error;

  PrintingRuntime({
    required this.repository,
    required this.coordinator,
    this.pollInterval = const Duration(seconds: 2),
  });

  PrintingRuntimeSnapshot get snapshot => PrintingRuntimeSnapshot(
        running: _running,
        processing: _processing,
        recovery: _recovery,
        latestEvent: _latestEvent,
        error: _error,
      );

  Stream<PrintingRuntimeSnapshot> get snapshots async* {
    yield snapshot;
    yield* _snapshots.stream;
  }

  bool get isRunning => _running;

  Future<PrintRecoverySummary> start() async {
    if (_running) {
      return _recovery ??
          const PrintRecoverySummary(
            safelyRequeued: 0,
            awaitingUserCheck: 0,
          );
    }
    _error = null;
    _running = true;
    _eventSubscription = coordinator.events.listen((event) {
      _latestEvent = event;
      _emit();
    });
    try {
      await _validateActiveRoutes();
      _recovery = await coordinator.recoverOnStartup();
      _emit();
      await processNow();
      _timer = Timer.periodic(pollInterval, (_) => unawaited(processNow()));
      return _recovery!;
    } catch (error) {
      _running = false;
      _emit(error: error.toString());
      rethrow;
    }
  }

  Future<void> _validateActiveRoutes() async {
    for (final kind in PrintDocumentKind.values) {
      final route = await repository.getRoute(kind);
      if (route == null) continue;
      final profiles = await repository.getDesignProfiles(kind);
      final matching = profiles.where(
        (profile) => profile.id == route.designProfileId,
      );
      if (matching.isEmpty) {
        throw StateError('${kind.name} rotasının tasarım profili bulunamadı.');
      }
      final profile = matching.single;
      if (!coordinator.supportsRenderer(kind, profile.rendererVersion)) {
        throw StateError(
          '${kind.name} rotası için ${profile.rendererVersion} renderer kayıtlı değil.',
        );
      }
    }
  }

  Future<void> processNow() async {
    if (!_running || _processing) return;
    _processing = true;
    _emit();
    try {
      final devices = (await repository.getDevices())
          .where((device) => device.enabled)
          .toList(growable: false);
      await Future.wait(devices.map(_drainDevice));
    } catch (error) {
      _emit(error: error.toString());
    } finally {
      _processing = false;
      _emit();
    }
  }

  Future<void> _drainDevice(PrinterDeviceProfile device) async {
    // Bound one cycle so a continuously growing queue cannot starve the UI.
    for (var processed = 0; processed < 20; processed++) {
      if (!await coordinator.processNext(device.id)) return;
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _emit();
  }

  void _emit({String? error}) {
    if (_snapshots.isClosed) return;
    if (error != null) _error = error;
    _snapshots.add(snapshot);
  }

  Future<void> dispose() async {
    await stop();
    await _snapshots.close();
  }
}
