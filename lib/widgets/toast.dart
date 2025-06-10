import 'dart:async';
import 'package:flutter/material.dart';

class Toast {
  static OverlayEntry? _currentToast;
  static Timer? _toastTimer;

  static void show(BuildContext context, String message) {
    _removeCurrentToast(); // entfernt bestehenden Toast und Timer

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: _ToastWidget(message: message),
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

  const _ToastWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Dismissible(
        key: const Key('toast'),
        direction: DismissDirection.up,
        onDismissed: (_) => Toast._removeCurrentToast(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.red[400],
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 6),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
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
