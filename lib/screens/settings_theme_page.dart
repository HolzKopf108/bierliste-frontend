import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/user_settings_service.dart';

class SettingsThemePage extends StatelessWidget {
  const SettingsThemePage({super.key});

  void updateTheme(BuildContext context, ThemeMode mode) async {
    final provider = Provider.of<ThemeProvider>(context, listen: false);

    final currentSettings = await UserSettingsService.load();
    provider.setTheme(mode);

    await UserSettingsService.updateSettings(
      theme: mode.name,
      autoSyncEnabled: currentSettings?.autoSyncEnabled ?? true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ThemeProvider>(context);
    final currentMode = provider.themeMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Theme ändern')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 30),
          RadioListTile<ThemeMode>(
            title: const Text('System'),
            value: ThemeMode.system,
            groupValue: currentMode,
            onChanged: (mode) => updateTheme(context, mode!),
          ),
          const SizedBox(height: 30),
          RadioListTile<ThemeMode>(
            title: const Text('Hell'),
            value: ThemeMode.light,
            groupValue: currentMode,
            onChanged: (mode) => updateTheme(context, mode!),
          ),
          const SizedBox(height: 30),
          RadioListTile<ThemeMode>(
            title: const Text('Dunkel'),
            value: ThemeMode.dark,
            groupValue: currentMode,
            onChanged: (mode) => updateTheme(context, mode!),
          ),
        ],
      ),
    );
  }
}
