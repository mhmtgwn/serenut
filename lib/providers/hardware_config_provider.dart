import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HardwareConfig {
  final String scaleConnection;
  final String scaleHost;
  final int scalePort;
  final String scaleSerialPort;
  final int scaleBaudRate;
  final String posBridgeHost;
  final int posBridgePort;

  const HardwareConfig({
    this.scaleConnection = 'tcp',
    this.scaleHost = '',
    this.scalePort = 4001,
    this.scaleSerialPort = '',
    this.scaleBaudRate = 9600,
    this.posBridgeHost = '',
    this.posBridgePort = 4100,
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
    posBridgeHost: prefs.getString('hardware_pos_host') ?? '',
    posBridgePort: prefs.getInt('hardware_pos_port') ?? 4100,
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
  await prefs.setString('hardware_pos_host', config.posBridgeHost.trim());
  await prefs.setInt('hardware_pos_port', config.posBridgePort);
}
