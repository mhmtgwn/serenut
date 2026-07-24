enum HardwareDeviceType {
  receiptPrinter,
  labelPrinter,
  scale,
  paymentTerminal,
  barcodeScanner,
}

enum HardwareConnectionType {
  embedded,
  windows,
  bluetooth,
  serial,
  tcp,
  keyboard,
}

enum HardwareDeviceStatus {
  unverified,
  testing,
  ready,
  offline,
  error,
  disabled,
}

class HardwareDevice {
  final String id;
  final String name;
  final HardwareDeviceType type;
  final HardwareConnectionType connectionType;
  final Map<String, Object?> configuration;
  final bool enabled;
  final HardwareDeviceStatus status;
  final DateTime? lastTestedAt;
  final String? lastMessage;
  final String? lastError;

  const HardwareDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.connectionType,
    this.configuration = const {},
    this.enabled = true,
    this.status = HardwareDeviceStatus.unverified,
    this.lastTestedAt,
    this.lastMessage,
    this.lastError,
  });

  HardwareDevice copyWith({
    String? name,
    HardwareDeviceType? type,
    HardwareConnectionType? connectionType,
    Map<String, Object?>? configuration,
    bool? enabled,
    HardwareDeviceStatus? status,
    DateTime? lastTestedAt,
    String? lastMessage,
    String? lastError,
    bool clearLastError = false,
  }) {
    return HardwareDevice(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      connectionType: connectionType ?? this.connectionType,
      configuration: configuration ?? this.configuration,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'connection_type': connectionType.name,
        'configuration': configuration,
        'enabled': enabled,
        'status': status.name,
        'last_tested_at': lastTestedAt?.toIso8601String(),
        'last_message': lastMessage,
        'last_error': lastError,
      };

  factory HardwareDevice.fromJson(Map<String, Object?> json) {
    return HardwareDevice(
      id: json['id']! as String,
      name: json['name']! as String,
      type: HardwareDeviceType.values.byName(json['type']! as String),
      connectionType: HardwareConnectionType.values
          .byName(json['connection_type']! as String),
      configuration: Map<String, Object?>.from(json['configuration']! as Map),
      enabled: json['enabled'] as bool? ?? true,
      status: HardwareDeviceStatus.values
          .byName(json['status'] as String? ?? 'unverified'),
      lastTestedAt: json['last_tested_at'] == null
          ? null
          : DateTime.parse(json['last_tested_at']! as String),
      lastMessage: json['last_message'] as String?,
      lastError: json['last_error'] as String?,
    );
  }
}

class HardwareTestResult {
  final bool success;
  final String message;
  final String? technicalDetail;
  final Duration elapsed;
  final DateTime completedAt;

  const HardwareTestResult({
    required this.success,
    required this.message,
    required this.elapsed,
    required this.completedAt,
    this.technicalDetail,
  });
}
