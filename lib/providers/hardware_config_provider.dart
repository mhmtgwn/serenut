import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HardwareConfig {
  final String scaleConnection;
  final String scaleHost;
  final int scalePort;
  final String scaleSerialPort;
  final int scaleBaudRate;
  final int scaleDataBits;
  final int scaleStopBits;
  final String scaleParity;
  final String scaleDefaultUnit;
  final String posBridgeHost;
  final int posBridgePort;
  final String posVendor;
  final String posProtocol;

  const HardwareConfig({
    this.scaleConnection = 'tcp',
    this.scaleHost = '',
    this.scalePort = 4001,
    this.scaleSerialPort = '',
    this.scaleBaudRate = 9600,
    this.scaleDataBits = 8,
    this.scaleStopBits = 1,
    this.scaleParity = 'none',
    this.scaleDefaultUnit = 'kg',
    this.posBridgeHost = '',
    this.posBridgePort = 4100,
    this.posVendor = 'generic',
    this.posProtocol = 'vendor_sdk',
  });

  bool get hasScale => scaleConnection == 'serial'
      ? scaleSerialPort.trim().isNotEmpty
      : scaleHost.trim().isNotEmpty;
  bool get hasPosBridge => posBridgeHost.trim().isNotEmpty;
}

final hardwareConfigProvider = FutureProvider<HardwareConfig>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return HardwareConfig(
    scaleConnection: prefs.getString('hardware_scale_connection') ?? 'tcp',
    scaleHost: prefs.getString('hardware_scale_host') ?? '',
    scalePort: prefs.getInt('hardware_scale_port') ?? 4001,
    scaleSerialPort: prefs.getString('hardware_scale_serial_port') ?? '',
    scaleBaudRate: prefs.getInt('hardware_scale_baud_rate') ?? 9600,
    scaleDataBits: prefs.getInt('hardware_scale_data_bits') ?? 8,
    scaleStopBits: prefs.getInt('hardware_scale_stop_bits') ?? 1,
    scaleParity: prefs.getString('hardware_scale_parity') ?? 'none',
    scaleDefaultUnit: prefs.getString('hardware_scale_default_unit') ?? 'kg',
    posBridgeHost: prefs.getString('hardware_pos_host') ?? '',
    posBridgePort: prefs.getInt('hardware_pos_port') ?? 4100,
    posVendor: prefs.getString('hardware_pos_vendor') ?? 'generic',
    posProtocol: prefs.getString('hardware_pos_protocol') ?? 'vendor_sdk',
  );
});

Future<void> saveHardwareConfig(HardwareConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('hardware_scale_connection', config.scaleConnection);
  await prefs.setString('hardware_scale_host', config.scaleHost.trim());
  await prefs.setInt('hardware_scale_port', config.scalePort);
  await prefs.setString(
      'hardware_scale_serial_port', config.scaleSerialPort.trim());
  await prefs.setInt('hardware_scale_baud_rate', config.scaleBaudRate);
  await prefs.setInt('hardware_scale_data_bits', config.scaleDataBits);
  await prefs.setInt('hardware_scale_stop_bits', config.scaleStopBits);
  await prefs.setString('hardware_scale_parity', config.scaleParity);
  await prefs.setString('hardware_scale_default_unit', config.scaleDefaultUnit);
  await prefs.setString('hardware_pos_host', config.posBridgeHost.trim());
  await prefs.setInt('hardware_pos_port', config.posBridgePort);
  await prefs.setString('hardware_pos_vendor', config.posVendor);
  await prefs.setString('hardware_pos_protocol', config.posProtocol);
}
