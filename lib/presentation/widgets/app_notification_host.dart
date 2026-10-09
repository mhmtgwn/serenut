import 'dart:async';

import 'package:flutter/material.dart';

/// App-wide notification surface that reserves layout space instead of
/// painting over controls near the bottom of a screen.
class AppNotificationHost extends StatefulWidget {
  const AppNotificationHost({
    required this.child,
    super.key,
  });

  final Widget child;

  static final GlobalKey<AppNotificationHostState> hostKey =
      GlobalKey<AppNotificationHostState>();
  static final List<SnackBar> _pending = <SnackBar>[];

  /// Routes legacy SnackBar calls through the app's non-blocking notification
  /// area while preserving their content, colors, duration, and action.
  static void show(SnackBar snackBar) {
    final state = hostKey.currentState;
    if (state != null) {
      state.show(snackBar);
    } else if (_pending.length <
        AppNotificationHostState.maxQueuedNotifications) {
      _pending.add(snackBar);
    }
  }

  @override
  State<AppNotificationHost> createState() => AppNotificationHostState();
}

class AppNotificationHostState extends State<AppNotificationHost> {
  static const maxQueuedNotifications = 4;

  final List<SnackBar> _queue = <SnackBar>[];
  SnackBar? _current;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    if (AppNotificationHost._pending.isNotEmpty) {
      _current = AppNotificationHost._pending.removeAt(0);
      _queue.addAll(AppNotificationHost._pending);
      AppNotificationHost._pending.clear();
      _startDismissTimer(_current!);
    }
  }

  void show(SnackBar snackBar) {
    if (!mounted) return;

    final messageKey = snackBar.content.toString();
    if (_current?.content.toString() == messageKey ||
        _queue.any((item) => item.content.toString() == messageKey)) {
      return;
    }

    setState(() {
      if (_current == null) {
        _current = snackBar;
        _startDismissTimer(snackBar);
      } else {
        if (_queue.length == maxQueuedNotifications) _queue.removeAt(0);
        _queue.add(snackBar);
      }
    });
  }

  void _startDismissTimer(SnackBar snackBar) {
    _dismissTimer?.cancel();
    if (snackBar.duration == Duration.zero) return;
    _dismissTimer = Timer(snackBar.duration, _showNext);
  }

  void _showNext() {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    setState(() {
      _current = _queue.isEmpty ? null : _queue.removeAt(0);
      if (_current case final next?) _startDismissTimer(next);
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _current == null
              ? const SizedBox(width: double.infinity, height: 0)
              : SafeArea(
                  bottom: false,
                  child: _NotificationBanner(
                    snackBar: _current!,
                    queuedCount: _queue.length,
                    onDismiss: _showNext,
                  ),
                ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.snackBar,
    required this.queuedCount,
    required this.onDismiss,
  });

  final SnackBar snackBar;
  final int queuedCount;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final action = snackBar.action;
    final foreground = snackBar.backgroundColor == null
        ? Theme.of(context).colorScheme.onInverseSurface
        : Colors.white;

    return Material(
      color: snackBar.backgroundColor ??
          Theme.of(context).colorScheme.inverseSurface,
      elevation: snackBar.elevation ?? 4,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DefaultTextStyle(
                  style: Theme.of(context).snackBarTheme.contentTextStyle ??
                      Theme.of(context).textTheme.bodyMedium!.copyWith(
                            color: foreground,
                          ),
                  child: snackBar.content,
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: () {
                    try {
                      action.onPressed();
                    } finally {
                      onDismiss();
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: action.textColor ??
                        Theme.of(context).snackBarTheme.actionTextColor ??
                        foreground,
                  ),
                  child: Text(action.label),
                ),
              if (queuedCount > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Text(
                    '+$queuedCount',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: foreground.withValues(alpha: 0.8)),
                  ),
                ),
              IconButton(
                tooltip: 'Bildirimi kapat',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: Icon(Icons.close, size: 18, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
