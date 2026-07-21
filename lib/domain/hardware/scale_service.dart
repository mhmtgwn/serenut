import 'dart:async';

import 'hardware_status.dart';

class ScaleReading {
  final String deviceId;
  final int sequence;
  final int grossGrams;
  final int tareGrams;
  final bool stable;
  final bool overload;
  final DateTime measuredAt;
  final String? rawFrame;

  const ScaleReading({
    required this.deviceId,
    required this.sequence,
    required this.grossGrams,
    this.tareGrams = 0,
    required this.stable,
    this.overload = false,
    required this.measuredAt,
    this.rawFrame,
  });

  int get netGrams => grossGrams - tareGrams;
}

abstract class IScaleAdapter {
  String get deviceId;
  HardwareConnectionState get connectionState;
  Stream<ScaleReading> get readings;

  Future<void> connect();
  Future<void> disconnect();
}

enum ScaleSessionState {
  idle,
  waitingForZero,
  waitingForWeight,
  measuring,
  stable,
  accepted,
  error,
}

class ScaleSession {
  final int minimumWeightGrams;
  final int zeroToleranceGrams;
  final int stabilityToleranceGrams;
  final int requiredStableSamples;
  final Duration maximumReadingAge;

  ScaleSession({
    this.minimumWeightGrams = 20,
    this.zeroToleranceGrams = 5,
    this.stabilityToleranceGrams = 3,
    this.requiredStableSamples = 3,
    this.maximumReadingAge = const Duration(seconds: 2),
  }) : assert(requiredStableSamples > 0);

  ScaleSessionState _state = ScaleSessionState.idle;
  ScaleSessionState get state => _state;

  String? _productId;
  String? get productId => _productId;

  ScaleReading? _acceptedReading;
  ScaleReading? get acceptedReading => _acceptedReading;

  final List<ScaleReading> _samples = [];
  int? _lastAcceptedSequence;
  bool _zeroSeenSinceAcceptance = true;

  void start({required String productId}) {
    if (productId.trim().isEmpty) {
      throw ArgumentError.value(productId, 'productId');
    }
    _productId = productId;
    _acceptedReading = null;
    _samples.clear();
    _state = _zeroSeenSinceAcceptance
        ? ScaleSessionState.waitingForWeight
        : ScaleSessionState.waitingForZero;
  }

  void cancel() {
    _productId = null;
    _acceptedReading = null;
    _samples.clear();
    _state = ScaleSessionState.idle;
  }

  void addReading(ScaleReading reading, {DateTime? now}) {
    if (_state == ScaleSessionState.idle ||
        _state == ScaleSessionState.accepted ||
        _state == ScaleSessionState.error) {
      return;
    }

    final currentTime = now ?? DateTime.now();
    if (currentTime.difference(reading.measuredAt).abs() > maximumReadingAge) {
      return;
    }
    if (reading.overload || reading.netGrams < -zeroToleranceGrams) {
      _state = ScaleSessionState.error;
      return;
    }

    if (reading.netGrams.abs() <= zeroToleranceGrams) {
      _zeroSeenSinceAcceptance = true;
      _samples.clear();
      _state = ScaleSessionState.waitingForWeight;
      return;
    }

    if (!_zeroSeenSinceAcceptance) {
      _state = ScaleSessionState.waitingForZero;
      return;
    }
    if (reading.netGrams < minimumWeightGrams) {
      _samples.clear();
      _state = ScaleSessionState.waitingForWeight;
      return;
    }

    _state = ScaleSessionState.measuring;
    _samples.add(reading);
    if (_samples.length > requiredStableSamples) {
      _samples.removeAt(0);
    }

    if (_samples.length < requiredStableSamples) return;
    final weights = _samples.map((sample) => sample.netGrams);
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    final adapterSaysStable = _samples.every((sample) => sample.stable);
    if (adapterSaysStable && maxWeight - minWeight <= stabilityToleranceGrams) {
      _state = ScaleSessionState.stable;
    }
  }

  ScaleReading accept() {
    if (_state != ScaleSessionState.stable || _samples.isEmpty) {
      throw const HardwareFailure(
        'SCALE_NOT_STABLE',
        'Ağırlık stabil olmadan tartım kabul edilemez.',
      );
    }
    final reading = _samples.last;
    if (_lastAcceptedSequence == reading.sequence) {
      throw const HardwareFailure(
        'SCALE_DUPLICATE_READING',
        'Aynı tartım ikinci kez kullanılamaz.',
      );
    }
    _acceptedReading = reading;
    _lastAcceptedSequence = reading.sequence;
    _zeroSeenSinceAcceptance = false;
    _state = ScaleSessionState.accepted;
    return reading;
  }
}

class SimulatedScaleAdapter implements IScaleAdapter {
  SimulatedScaleAdapter({this.deviceId = 'scale-simulator'});

  @override
  final String deviceId;

  final StreamController<ScaleReading> _controller =
      StreamController<ScaleReading>.broadcast();
  HardwareConnectionState _connectionState =
      HardwareConnectionState.disconnected;
  int _sequence = 0;

  @override
  HardwareConnectionState get connectionState => _connectionState;

  @override
  Stream<ScaleReading> get readings => _controller.stream;

  @override
  Future<void> connect() async {
    _connectionState = HardwareConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    _connectionState = HardwareConnectionState.disconnected;
  }

  void emit({
    required int grams,
    bool stable = true,
    int tareGrams = 0,
    bool overload = false,
    DateTime? measuredAt,
  }) {
    if (_connectionState != HardwareConnectionState.connected) {
      throw const HardwareFailure(
        'SCALE_DISCONNECTED',
        'Simüle terazi bağlı değil.',
      );
    }
    _controller.add(ScaleReading(
      deviceId: deviceId,
      sequence: ++_sequence,
      grossGrams: grams,
      tareGrams: tareGrams,
      stable: stable,
      overload: overload,
      measuredAt: measuredAt ?? DateTime.now(),
    ));
  }

  Future<void> dispose() => _controller.close();
}
