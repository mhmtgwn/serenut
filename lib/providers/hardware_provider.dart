import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/hardware/scale_service.dart';
import 'package:serenutos/domain/hardware/hardware_status.dart';
import 'package:serenutos/providers/hardware_config_provider.dart';

final scaleAdapterProvider = Provider<IScaleAdapter>((ref) {
  final config = ref.watch(hardwareConfigProvider).valueOrNull;
  if (config == null || !config.hasScale) {
    return UnconfiguredScaleAdapter();
  }
  final adapter =
      TcpScaleAdapter(host: config.scaleHost, port: config.scalePort);
  ref.onDispose(adapter.dispose);
  return adapter;
});

class UnconfiguredScaleAdapter implements IScaleAdapter {
  @override
  String get deviceId => 'scale-unconfigured';
  @override
  HardwareConnectionState get connectionState =>
      HardwareConnectionState.disconnected;
  @override
  Stream<ScaleReading> get readings => const Stream.empty();
  @override
  Future<void> connect() => throw const HardwareFailure(
      'SCALE_NOT_CONFIGURED', 'Terazi IP ve port ayarı yapılmamış.');
  @override
  Future<void> disconnect() async {}
}

class ScaleHardwareState {
  final ScaleReading? reading;
  final Object? error;
  final bool connected;

  const ScaleHardwareState({
    this.reading,
    this.error,
    this.connected = false,
  });

  ScaleHardwareState copyWith({
    ScaleReading? reading,
    Object? error,
    bool? connected,
  }) =>
      ScaleHardwareState(
        reading: reading ?? this.reading,
        error: error,
        connected: connected ?? this.connected,
      );
}

class ScaleHardwareNotifier extends StateNotifier<ScaleHardwareState> {
  final IScaleAdapter adapter;
  StreamSubscription<ScaleReading>? _subscription;

  ScaleHardwareNotifier(this.adapter) : super(const ScaleHardwareState()) {
    connect();
  }

  Future<void> connect() async {
    try {
      await adapter.connect();
      await _subscription?.cancel();
      _subscription = adapter.readings.listen(
        (reading) => state = state.copyWith(reading: reading, connected: true),
        onError: (Object error) =>
            state = state.copyWith(error: error, connected: false),
      );
      state = state.copyWith(connected: true);
    } catch (error) {
      state = state.copyWith(error: error, connected: false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    adapter.disconnect();
    super.dispose();
  }
}

final scaleHardwareProvider =
    StateNotifierProvider<ScaleHardwareNotifier, ScaleHardwareState>((ref) {
  return ScaleHardwareNotifier(ref.watch(scaleAdapterProvider));
});
