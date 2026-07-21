import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/hardware/payment_terminal_service.dart';
import 'package:serenutos/providers/hardware_config_provider.dart';

final paymentTerminalAdapterProvider = Provider<IPaymentTerminalAdapter>((ref) {
  final config = ref.watch(hardwareConfigProvider).valueOrNull;
  if (config == null || !config.hasPosBridge) {
    return UnconfiguredPaymentTerminal();
  }
  return TcpPaymentTerminalAdapter(
    host: config.posBridgeHost,
    port: config.posBridgePort,
  );
});
