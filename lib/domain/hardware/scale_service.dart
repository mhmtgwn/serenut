import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_libserialport/flutter_libserialport.dart';

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
  Stream<String> get rawFrames;

  Future<void> connect();
  Future<void> disconnect();
}

/// Reads the common continuous ASCII output used by network-enabled scales
/// and RS232-to-Ethernet converters. Frames may contain ST/US, GS/NT and a
/// value suffixed with kg or g (for example: `ST,GS,+001.245kg`).
class TcpScaleAdapter implements IScaleAdapter {
  TcpScaleAdapter(
      {required this.host, required this.port, this.defaultUnit = 'kg'});

  final String host;
  final int port;
  final String defaultUnit;
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  final _controller = StreamController<ScaleReading>.broadcast();
  final _rawController = StreamController<String>.broadcast();
  HardwareConnectionState _state = HardwareConnectionState.disconnected;
  int _sequence = 0;

  @override
  String get deviceId => 'tcp-scale-$host:$port';
  @override
  HardwareConnectionState get connectionState => _state;
  @override
  Stream<ScaleReading> get readings => _controller.stream;
  @override
  Stream<String> get rawFrames => _rawController.stream;

  @override
  Future<void> connect() async {
    if (_socket != null) return;
    _state = HardwareConnectionState.connecting;
    try {
      final socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _socket = socket;
      _state = HardwareConnectionState.connected;
      _subscription = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleFrame, onError: _handleError, onDone: _handleDone);
    } catch (error) {
      _state = HardwareConnectionState.error;
      throw HardwareFailure('SCALE_CONNECT_FAILED',
          'Teraziye bağlanılamadı ($host:$port): $error');
    }
  }

  void _handleFrame(String frame) {
    _rawController.add(frame);
    final reading = ScaleFrameParser.parse(
      frame,
      deviceId: deviceId,
      sequence: ++_sequence,
      defaultUnit: defaultUnit,
    );
    if (reading != null) _controller.add(reading);
  }

  void _handleError(Object error) {
    _state = HardwareConnectionState.error;
    _controller.addError(HardwareFailure(
        'SCALE_READ_FAILED', 'Terazi verisi okunamadı: $error'));
  }

  void _handleDone() {
    _socket = null;
    _state = HardwareConnectionState.disconnected;
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _state = HardwareConnectionState.disconnected;
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
    await _rawController.close();
  }
}

class SerialScaleAdapter implements IScaleAdapter {
  SerialScaleAdapter({
    required this.portName,
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 'none',
    this.defaultUnit = 'kg',
  });

  final String portName;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final String parity;
  final String defaultUnit;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<String>? _subscription;
  final _controller = StreamController<ScaleReading>.broadcast();
  final _rawController = StreamController<String>.broadcast();
  HardwareConnectionState _state = HardwareConnectionState.disconnected;
  int _sequence = 0;

  static List<String> get availablePorts => SerialPort.availablePorts;

  @override
  String get deviceId => 'serial-scale-$portName';
  @override
  HardwareConnectionState get connectionState => _state;
  @override
  Stream<ScaleReading> get readings => _controller.stream;
  @override
  Stream<String> get rawFrames => _rawController.stream;

  @override
  Future<void> connect() async {
    if (_port?.isOpen == true) return;
    _state = HardwareConnectionState.connecting;
    final port = SerialPort(portName);
    try {
      if (!port.openRead()) {
        throw StateError(SerialPort.lastError?.message ?? 'Port açılamadı');
      }
      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = dataBits
        ..stopBits = stopBits
        ..parity = _serialParity(parity)
        ..setFlowControl(SerialPortFlowControl.none);
      port.config = config;
      config.dispose();
      _port = port;
      _reader = SerialPortReader(port);
      _state = HardwareConnectionState.connected;
      _subscription = _reader!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleFrame, onError: _handleError);
    } catch (error) {
      port.close();
      port.dispose();
      _state = HardwareConnectionState.error;
      throw HardwareFailure('SCALE_SERIAL_CONNECT_FAILED',
          '$portName seri terazisine bağlanılamadı: $error');
    }
  }

  void _handleFrame(String frame) {
    _rawController.add(frame);
    final reading = ScaleFrameParser.parse(frame,
        deviceId: deviceId, sequence: ++_sequence, defaultUnit: defaultUnit);
    if (reading != null) _controller.add(reading);
  }

  void _handleError(Object error) {
    _state = HardwareConnectionState.error;
    _controller.addError(HardwareFailure(
        'SCALE_SERIAL_READ_FAILED', 'Seri terazi okunamadı: $error'));
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _reader?.close();
    _reader = null;
    _port?.close();
    _port?.dispose();
    _port = null;
    _state = HardwareConnectionState.disconnected;
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
    await _rawController.close();
  }

  static int _serialParity(String value) => switch (value) {
        'odd' => SerialPortParity.odd,
        'even' => SerialPortParity.even,
        _ => SerialPortParity.none,
      };
}

class ScaleFrameParser {
  static final RegExp _weight = RegExp(
    r'([+-]?\d+(?:[\.,]\d+)?)\s*(kg|g)?\b',
    caseSensitive: false,
  );

  static ScaleReading? parse(
    String frame, {
    required String deviceId,
    required int sequence,
    DateTime? measuredAt,
    String defaultUnit = 'kg',
  }) {
    final normalized = frame.trim();
    final match = _weight.firstMatch(normalized);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (value == null) return null;
    final unit = (match.group(2) ?? defaultUnit).toLowerCase();
    final grams = (unit == 'kg' ? value * 1000 : value).round();
    final upper = normalized.toUpperCase();
    final unstable =
        RegExp(r'(^|[,\s])(US|UNSTABLE|MOTION)([,\s]|$)').hasMatch(upper);
    final overload = upper.contains('OL') || upper.contains('OVERLOAD');
    return ScaleReading(
      deviceId: deviceId,
      sequence: sequence,
      grossGrams: grams,
      stable: !unstable,
      overload: overload,
      measuredAt: measuredAt ?? DateTime.now(),
      rawFrame: frame,
    );
  }
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
  Stream<String> get rawFrames => const Stream.empty();

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
