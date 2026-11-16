import 'package:material_ui/material_ui.dart';

Widget googleLoginButton(VoidCallback onPressed) => OutlinedButton.icon(
  onPressed: onPressed,
  icon: const Icon(Icons.login),
  label: const Text('Mit Google anmelden'),
);
