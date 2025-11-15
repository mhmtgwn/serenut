import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

enum NotificationType {
  success,
  error,
  info,
  warning,
}

class NotificationData {
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  
  NotificationData({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}

class NotificationProvider extends InheritedWidget {
  final NotificationState state;
  
  const NotificationProvider({
    super.key,
    required this.state,
    required Widget child,
  }) : super(child: child);
  
  static NotificationState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<NotificationProvider>();
    if (provider == null) {
      throw Exception('NotificationProvider bulunamadı');
    }
    return provider.state;
  }
  
  @override
  bool updateShouldNotify(NotificationProvider oldWidget) {
    return true;
  }
}

class NotificationState {
  NotificationData? _currentNotification;
  final ValueNotifier<NotificationData?> notificationNotifier = ValueNotifier<NotificationData?>(null);
  
  NotificationData? get currentNotification => _currentNotification;
  
  void showNotification(String message, NotificationType type, {Duration? duration}) {
    _currentNotification = NotificationData(
      message: message,
      type: type,
      timestamp: DateTime.now(),
    );
    notificationNotifier.value = _currentNotification;
    
    // Belirtilen süre sonra bildirimi otomatik olarak kaldır
    Future.delayed(duration ?? const Duration(seconds: 3), () {
      if (_currentNotification?.timestamp == notificationNotifier.value?.timestamp) {
        hideNotification();
      }
    });
  }
  
  void hideNotification() {
    _currentNotification = null;
    notificationNotifier.value = null;
  }
  
  void showSuccess(String message, {Duration? duration}) {
    showNotification(message, NotificationType.success, duration: duration);
  }
  
  void showError(String message, {Duration? duration}) {
    showNotification(message, NotificationType.error, duration: duration);
  }
  
  void showInfo(String message, {Duration? duration}) {
    showNotification(message, NotificationType.info, duration: duration);
  }
  
  void showWarning(String message, {Duration? duration}) {
    showNotification(message, NotificationType.warning, duration: duration);
  }
}

class NotificationBar extends StatefulWidget {
  const NotificationBar({super.key});

  @override
  State<NotificationBar> createState() => _NotificationBarState();
}

class _NotificationBarState extends State<NotificationBar> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  NotificationData? _lastNotification;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = NotificationProvider.of(context);
    
    return ValueListenableBuilder<NotificationData?>(
      valueListenable: state.notificationNotifier,
      builder: (context, notification, child) {
        // Bildirim değiştiğinde animasyonu kontrol et
        if (notification != null && _lastNotification?.timestamp != notification.timestamp) {
          _animationController.forward();
          _lastNotification = notification;
        } else if (notification == null && _lastNotification != null) {
          _animationController.reverse();
          _lastNotification = null;
        }

        if (notification == null && _animationController.isDismissed) {
          return const SizedBox(height: 0);
        }
        
        // Bildirim tipi için renk ve ikon belirle
        final Color backgroundColor;
        final IconData icon;
        
        switch (notification?.type ?? NotificationType.info) {
          case NotificationType.success:
            backgroundColor = Colors.green.shade700;
            icon = Icons.check_circle;
            break;
          case NotificationType.error:
            backgroundColor = Colors.red.shade700;
            icon = Icons.error;
            break;
          case NotificationType.warning:
            backgroundColor = Colors.orange.shade700;
            icon = Icons.warning;
            break;
          case NotificationType.info:
            backgroundColor = AppTheme.primaryColor;
            icon = Icons.info;
            break;
        }
        
        return AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) {
            return SizedBox(
              height: 30 * _slideAnimation.value,
              child: Opacity(
                opacity: _slideAnimation.value,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: backgroundColor,
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          notification?.message ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      GestureDetector(
                        onTap: state.hideNotification,
                        child: Icon(
                          Icons.close,
                          color: Colors.white.withAlpha(230),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;
  
  NotificationService._internal();
  
  late NotificationState _state;
  
  void initialize(NotificationState state) {
    _state = state;
    // Bildirim state'ini başlat
    _state.notificationNotifier.addListener(() {
      // Bildirim değişikliklerini dinle
    });
  }
  
  void showNotification(
    BuildContext context, {
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onTap,
  }) {
    _state.showNotification(message, type, duration: duration);
  }
  
  void showSuccess(BuildContext context, String message, {Duration? duration, VoidCallback? onTap}) {
    _state.showSuccess(message, duration: duration);
  }
  
  void showError(BuildContext context, String message, {Duration? duration, VoidCallback? onTap}) {
    _state.showError(message, duration: duration);
  }
  
  void showInfo(BuildContext context, String message, {Duration? duration, VoidCallback? onTap}) {
    _state.showInfo(message, duration: duration);
  }
  
  void showWarning(BuildContext context, String message, {Duration? duration, VoidCallback? onTap}) {
    _state.showWarning(message, duration: duration);
  }
}
