import 'package:flutter/material.dart';
import '../main.dart';

Future<void> safePushReplacementNamed(BuildContext context, String routeName, {Object? arguments}) async {
  await Future.delayed(Duration.zero);
  if (!context.mounted) return;

  if (ModalRoute.of(context)?.settings.name != routeName) {
    Navigator.of(context).pushReplacementNamed(routeName, arguments: arguments);
  }
}

Future<void> safePushNamed(BuildContext context, String routeName, {Object? arguments}) async {
  await Future.delayed(Duration.zero);
  if (!context.mounted) return;

  Navigator.of(context).pushNamed(routeName, arguments: arguments);
}

Future<void> safePushNamedAndRemoveUntil(BuildContext context, String routeName, {Object? arguments}) async {
  await Future.delayed(Duration.zero);
  if (!context.mounted) return;

  Navigator.of(context).pushNamedAndRemoveUntil(routeName, (_) => false, arguments: arguments);
}

Future<void> safeGlobalPushNamedAndRemoveUntil(String routeName, {Object? arguments}) async {
  await Future.delayed(Duration.zero);
  final state = navigatorKey.currentState;

  if (state != null && state.mounted) {
    state.pushNamedAndRemoveUntil(routeName, (_) => false, arguments: arguments);
  } else {
    debugPrint('[Navigation] Warning: navigatorState not available');
  }
}

Future<void> safePop(BuildContext context, [dynamic result]) async {
  await Future.delayed(Duration.zero);
  if (!context.mounted) return;

  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop(result);
  } else {
    debugPrint('[Navigation] Warning: Cannot pop — no route to pop.');
  }
}
