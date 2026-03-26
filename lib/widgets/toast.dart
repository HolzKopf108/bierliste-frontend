import 'dart:async';
import 'package:flutter/material.dart';

enum ToastType { error, success, info, warning }

class Toast {
  static OverlayEntry? _currentToast;
  static Timer? _toastTimer;

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.error,
    String? actionLabel,
    VoidCallback? onActionTap,
    InlineSpan? messageSpan,
  }) {
    _removeCurrentToast();

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: _ToastWidget(
          message: message,
          type: type,
          actionLabel: actionLabel,
          onActionTap: onActionTap,
          messageSpan: messageSpan,
        ),
      ),
    );

    overlay.insert(entry);
    _currentToast = entry;

    _toastTimer = Timer(const Duration(seconds: 3), _removeCurrentToast);
  }

  static void _removeCurrentToast() {
    _toastTimer?.cancel();
    _toastTimer = null;

    _currentToast?.remove();
    _currentToast = null;
  }
}

class _ToastWidget extends StatelessWidget {
  final String message;
  final ToastType type;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final InlineSpan? messageSpan;

  const _ToastWidget({
    required this.message,
    required this.type,
    this.actionLabel,
    this.onActionTap,
    this.messageSpan,
  });

  ({Color backgroundColor, IconData icon}) _config(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (type) {
      case ToastType.success:
        return (
          backgroundColor: Colors.green.shade600,
          icon: Icons.check_circle,
        );
      case ToastType.info:
        return (backgroundColor: colorScheme.primary, icon: Icons.info);
      case ToastType.warning:
        return (
          backgroundColor: Colors.orange.shade700,
          icon: Icons.warning_amber_rounded,
        );
      case ToastType.error:
        return (backgroundColor: colorScheme.error, icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config(context);

    return Material(
      color: Colors.transparent,
      child: Dismissible(
        key: const Key('toast'),
        direction: DismissDirection.up,
        onDismissed: (_) => Toast._removeCurrentToast(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: config.backgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(config.icon, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: messageSpan != null
                    ? RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.white),
                          children: [messageSpan!],
                        ),
                      )
                    : Text(
                        message,
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: () {
                    Toast._removeCurrentToast();
                    onActionTap?.call();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel!),
                ),
              GestureDetector(
                onTap: () => Toast._removeCurrentToast(),
                child: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
