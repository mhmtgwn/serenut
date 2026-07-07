// lib/domain/realtime/realtime_status.dart
// Connection states for the multi-tenant WebSocket client

enum RealtimeStatus {
  connected,
  disconnected,
  connecting,
  reconnecting;

  String get label => switch (this) {
        RealtimeStatus.connected => 'Canlı',
        RealtimeStatus.disconnected => 'Bağlantı Kesildi',
        RealtimeStatus.connecting => 'Bağlanıyor...',
        RealtimeStatus.reconnecting => 'Yeniden Bağlanılıyor...',
      };
}
