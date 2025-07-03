import 'package:flutter/material.dart';
import '../services/user_settings_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  Future<void> loadTheme() async {
    final settings = await UserSettingsService.load();
    final themeString = settings?.theme ?? 'system';

    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == themeString,
      orElse: () => ThemeMode.system,
    );

    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    final currentSettings = await UserSettingsService.load();
    
    _themeMode = mode;

    await UserSettingsService.updateSettings(
      theme: mode.name,
      autoSyncEnabled: currentSettings?.autoSyncEnabled ?? true,
    );

    notifyListeners();
  }
}
