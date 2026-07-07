// lib/providers/realtime/connection_state_notifier.dart
// Riverpod notifier to propagate connection status changes

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/realtime/realtime_status.dart';

class ConnectionStateNotifier extends StateNotifier<RealtimeStatus> {
  ConnectionStateNotifier() : super(RealtimeStatus.disconnected);

  void updateStatus(RealtimeStatus newStatus) {
    state = newStatus;
  }
}
