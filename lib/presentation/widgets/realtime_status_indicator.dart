// lib/presentation/widgets/realtime_status_indicator.dart
// Premium UI badge and status banner for WebSocket connection

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/realtime/realtime_status.dart';
import 'package:serenutos/providers/realtime/realtime_provider.dart';

class RealtimeStatusIndicator extends ConsumerWidget {
  final bool compact;

  const RealtimeStatusIndicator({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStateProvider);

    if (compact) {
      final Color dotColor;
      final String label;

      switch (status) {
        case RealtimeStatus.connected:
          return const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BreathingDot(),
              SizedBox(width: 6),
              Text(
                'Canlı',
                style: TextStyle(
                  color: Color(0xFF16A34A),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
        case RealtimeStatus.connecting:
        case RealtimeStatus.reconnecting:
          dotColor = const Color(0xFFEAB308);
          label = 'Yeniden Bağlanılıyor...';
          break;
        case RealtimeStatus.disconnected:
          dotColor = const Color(0xFFEF4444);
          label = 'Bağlantı Kesildi';
          break;
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: dotColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    if (status == RealtimeStatus.connected) {
      return const SizedBox.shrink();
    }

    final Color bgColor;
    final Color textColor;
    final String text;
    final IconData icon;

    if (status == RealtimeStatus.reconnecting || status == RealtimeStatus.connecting) {
      bgColor = const Color(0xFFFEF9C3); // light yellow
      textColor = const Color(0xFF854D0E); // dark yellow
      text = 'Sunucuyla bağlantı kesildi. Yeniden bağlanılıyor...';
      icon = Icons.sync_rounded;
    } else {
      bgColor = const Color(0xFFFEE2E2); // light red
      textColor = const Color(0xFF991B1B); // dark red
      text = 'Bağlantı Kesildi. Canlı veri akışı durduruldu.';
      icon = Icons.wifi_off_rounded;
    }

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreathingDot extends StatefulWidget {
  const _BreathingDot();

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF16A34A),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16A34A).withOpacity(0.2 + 0.6 * _controller.value),
                blurRadius: 4 + 6 * _controller.value,
                spreadRadius: 1 + 2 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
