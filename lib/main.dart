import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'app.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();
  await dotenv.load();

  runApp(
    ChangeNotifierProvider.value(
      value: themeProvider,
      child: const BierlisteApp(),
    ),
  );
}
